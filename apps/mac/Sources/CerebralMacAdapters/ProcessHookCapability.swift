// Allowlisted hook process adapter (NIC-80, MAC-ADAPTER-2).
#if canImport(AppKit)
import Darwin
import Dispatch
import Foundation
import CerebralCore
import CerebralTools

/// Executes exactly one pre-resolved ``HookInvocation`` as a real process
/// (FR-TOL-05, FR-SAF-03). The allowlist lives upstream (`HookCatalog` — an
/// unregistered id never reaches this adapter, and there is no shell: the
/// executable is exec'd directly with the configured arguments, so free-form
/// shell text cannot execute by construction).
///
/// Boundedness guarantees:
/// - **Environment:** the child receives *exactly* `invocation.environment` —
///   nothing inherited, nothing added.
/// - **File descriptors:** everything except stdout/stderr pipes is closed in
///   the child (`POSIX_SPAWN_CLOEXEC_DEFAULT`).
/// - **Process tree:** the child starts as the leader of a new process group
///   (`POSIX_SPAWN_SETPGROUP`), so cancellation and executor timeouts signal the
///   *whole group* — SIGTERM, then SIGKILL after a grace period — and no
///   grandchild survives unmanaged. The child is always reaped (`waitpid`)
///   before this call returns or throws.
/// - **Output:** stdout/stderr are captured up to `outputLimitBytes` each, with
///   an explicit truncation marker; the pipes are drained to EOF regardless so
///   a chatty hook can never deadlock on a full pipe.
/// - **Threads:** no cooperative-pool thread ever blocks while the child runs.
///   All waiting is event-driven — a kqueue-backed exit source instead of a
///   blocking `waitpid`, `DispatchIO` instead of blocking pipe reads, and a GCD
///   timer for the SIGKILL escalation. A slow hook therefore cannot starve the
///   executor's timeout timer or any other async work (two concurrent hooks
///   previously pinned six pool threads, which deadlocked timeouts on the
///   3-core CI runner).
///
/// Deadlines are owned by the executor (`ToolExecutor` races the handler against
/// the descriptor timeout and cancels it): this adapter's job on cancellation is
/// only to kill the group, reap, and rethrow `CancellationError`.
public struct ProcessHookCapability: ProcessCapability {
    private let outputLimitBytes: Int
    private let terminationGraceMs: Int

    /// Serial queue for exit sources, zombie reaping, and SIGKILL escalation
    /// timers. Every block scheduled here completes in microseconds (`waitpid`
    /// on an already-exited child, a `kill` call), so one shared queue serves
    /// all concurrent runs.
    private static let eventQueue = DispatchQueue(label: "com.cerebralhelm.hook-process-events")

    public init(outputLimitBytes: Int = 64 * 1024, terminationGraceMs: Int = 500) {
        self.outputLimitBytes = outputLimitBytes
        self.terminationGraceMs = terminationGraceMs
    }

    public func run(_ invocation: HookInvocation) async throws -> ProcessRunResult {
        let executablePath = Self.resolveExecutablePath(invocation)
        try Self.checkExecutable(at: executablePath, configured: invocation.executable)

        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            [stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1]].filter { $0 >= 0 }.forEach { close($0) }
            throw NativeCapabilityError.adapterFailure("Creating output pipes failed (errno \(errno)).")
        }

        let started = DispatchTime.now()
        let pid: pid_t
        do {
            pid = try Self.spawn(
                executablePath: executablePath,
                invocation: invocation,
                stdoutWriteFD: stdoutPipe[1],
                stderrWriteFD: stderrPipe[1]
            )
        } catch {
            [stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1]].forEach { close($0) }
            throw error
        }
        // The child owns the write ends now; the parent must close its copies or
        // the drain streams never see EOF.
        close(stdoutPipe[1])
        close(stderrPipe[1])

        async let stdoutCapture = Self.drain(fd: stdoutPipe[0], limit: outputLimitBytes)
        async let stderrCapture = Self.drain(fd: stderrPipe[0], limit: outputLimitBytes)

        let reaped = ReapFlag()
        let graceMs = terminationGraceMs
        let status = await withTaskCancellationHandler {
            await Self.awaitExit(of: pid)
        } onCancel: {
            // Signal the whole group; escalate to SIGKILL if it lingers past the
            // grace period. The flag stops a late SIGKILL from reaching a
            // (theoretically) reused pgid after the child is already reaped.
            kill(-pid, SIGTERM)
            Self.eventQueue.asyncAfter(deadline: .now() + .milliseconds(graceMs)) {
                if !reaped.isDone { kill(-pid, SIGKILL) }
            }
        }
        reaped.markDone()

        let stdout = await stdoutCapture
        let stderr = await stderrCapture

        // The child is reaped and the pipes are drained on every path — only now
        // may cancellation propagate (the executor maps it to cancelled/timeout).
        try Task.checkCancellation()

        let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        return ProcessRunResult(
            exitCode: Self.exitCode(from: status),
            stdout: stdout,
            stderr: stderr,
            environment: invocation.environment,
            timedOut: false,
            durationMs: elapsedMs
        )
    }

    // MARK: - Spawning

    /// A relative configured executable resolves against the invocation's working
    /// directory — never against PATH, because no shell is involved.
    private static func resolveExecutablePath(_ invocation: HookInvocation) -> String {
        if invocation.executable.hasPrefix("/") { return invocation.executable }
        return (invocation.workingDirectory as NSString).appendingPathComponent(invocation.executable)
    }

    private static func checkExecutable(at path: String, configured: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw NativeCapabilityError.notFound(
                "Configured hook executable '\(configured)' does not exist at '\(path)'. Fix the hook reference under Settings → Tools."
            )
        }
        guard access(path, X_OK) == 0 else {
            throw NativeCapabilityError.permissionDenied
        }
    }

    private static func spawn(
        executablePath: String,
        invocation: HookInvocation,
        stdoutWriteFD: Int32,
        stderrWriteFD: Int32
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addchdir_np(&fileActions, invocation.workingDirectory)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutWriteFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stderrWriteFD, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // New process group (leader pid == child pid) so signals reach the whole
        // tree; close every fd the file actions did not explicitly map. The child
        // starts SUSPENDED — frozen before its first instruction — so the exit
        // source in `awaitExit` is always registered before the child can exit;
        // `awaitExit` sends the SIGCONT. Without this handshake a fast-exiting
        // child could die before the kqueue watch exists and the exit event
        // would be lost forever.
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_START_SUSPENDED)
        )
        posix_spawnattr_setpgroup(&attributes, 0)

        let argv = [executablePath] + invocation.arguments
        let envp = invocation.environment.map { "\($0.key)=\($0.value)" }.sorted()
        var argvPointers: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        var envpPointers: [UnsafeMutablePointer<CChar>?] = envp.map { strdup($0) } + [nil]
        defer {
            argvPointers.forEach { free($0) }
            envpPointers.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executablePath, &fileActions, &attributes, &argvPointers, &envpPointers)
        guard result == 0 else {
            switch result {
            case ENOENT, ENOTDIR:
                throw NativeCapabilityError.notFound(
                    "Spawning configured hook '\(invocation.executable)' failed: executable or working directory missing."
                )
            case EACCES, EPERM:
                throw NativeCapabilityError.permissionDenied
            default:
                throw NativeCapabilityError.adapterFailure(
                    "Spawning configured hook '\(invocation.executable)' failed (posix_spawn error \(result))."
                )
            }
        }
        return pid
    }

    // MARK: - Exit waiting

    /// Suspends until the (suspended-at-birth) child exits, without occupying a
    /// thread: registers a kqueue-backed exit source, *then* releases the child
    /// with SIGCONT. When the source fires the child is already a zombie, so the
    /// `waitpid` reap returns immediately instead of blocking.
    ///
    /// This await is deliberately non-cancellable: cancellation is handled by the
    /// caller's `onCancel` (group SIGTERM/SIGKILL), which guarantees the exit
    /// event — and therefore this continuation — always arrives.
    private static func awaitExit(of pid: pid_t) async -> Int32 {
        await withCheckedContinuation { continuation in
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: eventQueue)
            source.setEventHandler {
                source.cancel()
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                continuation.resume(returning: status)
            }
            source.resume()
            kill(pid, SIGCONT)
        }
    }

    // MARK: - Output and exit

    /// Streams `fd` to EOF via DispatchIO (no thread blocks in `read`), keeping
    /// at most `limit` bytes and marking truncation. Always drains fully so the
    /// child can never block on a full pipe.
    private static func drain(fd: Int32, limit: Int) async -> String {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.cerebralhelm.hook-drain")
            let collector = OutputCollector(limit: limit)
            let io = DispatchIO(type: .stream, fileDescriptor: fd, queue: queue) { _ in
                close(fd)
            }
            // Deliver chunks as they arrive instead of buffering toward a high-water mark.
            io.setLimit(lowWater: 1)
            io.read(offset: 0, length: .max, queue: queue) { done, data, _ in
                if let data { collector.append(data) }
                // `done` fires exactly once — at EOF or on a read error — so the
                // continuation resumes exactly once, with whatever was captured.
                if done {
                    io.close()
                    continuation.resume(returning: collector.text())
                }
            }
        }
    }

    /// Normal exit reports the exit status; death by signal reports the shell
    /// convention `128 + signal` so callers can still distinguish outcomes.
    private static func exitCode(from status: Int32) -> Int {
        let signal = status & 0x7f
        if signal == 0 { return Int((status >> 8) & 0xff) }
        return Int(128 + signal)
    }
}

/// Accumulates capped output across DispatchIO chunk callbacks. The lock makes
/// the handler-side mutation and the final read safely publishable across the
/// GCD queue → continuation-resumer boundary.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var collected = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: DispatchData) {
        lock.lock()
        defer { lock.unlock() }
        let room = limit - collected.count
        if room > 0 {
            collected.append(contentsOf: chunk.prefix(room))
        }
        if chunk.count > room { truncated = true }
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = String(decoding: collected, as: UTF8.self)
        return truncated ? text + "\n…[output truncated]" : text
    }
}

/// Guards the late-SIGKILL escalation against firing after the child was reaped.
private final class ReapFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    var isDone: Bool {
        lock.lock(); defer { lock.unlock() }
        return done
    }

    func markDone() {
        lock.lock(); done = true; lock.unlock()
    }
}
#endif
