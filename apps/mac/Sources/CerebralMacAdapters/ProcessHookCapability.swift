// Allowlisted hook process adapter (NIC-80, MAC-ADAPTER-2).
#if canImport(AppKit)
import Darwin
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
///
/// Deadlines are owned by the executor (`ToolExecutor` races the handler against
/// the descriptor timeout and cancels it): this adapter's job on cancellation is
/// only to kill the group, reap, and rethrow `CancellationError`.
public struct ProcessHookCapability: ProcessCapability {
    private let outputLimitBytes: Int
    private let terminationGraceMs: Int

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
        // the drain loops never see EOF.
        close(stdoutPipe[1])
        close(stderrPipe[1])

        async let stdoutCapture = Self.drain(fd: stdoutPipe[0], limit: outputLimitBytes)
        async let stderrCapture = Self.drain(fd: stderrPipe[0], limit: outputLimitBytes)

        let reaped = ReapFlag()
        let graceMs = terminationGraceMs
        let exitTask = Task.detached { () -> Int32 in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            return status
        }
        let status = await withTaskCancellationHandler {
            await exitTask.value
        } onCancel: {
            // Signal the whole group; escalate to SIGKILL if it lingers past the
            // grace period. The flag stops a late SIGKILL from reaching a
            // (theoretically) reused pgid after the child is already reaped.
            kill(-pid, SIGTERM)
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(graceMs) * 1_000_000)
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
        // tree; close every fd the file actions did not explicitly map.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
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

    // MARK: - Output and exit

    /// Reads `fd` to EOF, keeping at most `limit` bytes and marking truncation.
    /// Always drains fully so the child can never block on a full pipe.
    private static func drain(fd: Int32, limit: Int) async -> String {
        await Task.detached { () -> String in
            var collected = Data()
            var truncated = false
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                let room = limit - collected.count
                if room > 0 {
                    collected.append(contentsOf: buffer[0..<min(count, room)])
                }
                if count > room { truncated = true }
            }
            close(fd)
            let text = String(decoding: collected, as: UTF8.self)
            return truncated ? text + "\n…[output truncated]" : text
        }.value
    }

    /// Normal exit reports the exit status; death by signal reports the shell
    /// convention `128 + signal` so callers can still distinguish outcomes.
    private static func exitCode(from status: Int32) -> Int {
        let signal = status & 0x7f
        if signal == 0 { return Int((status >> 8) & 0xff) }
        return Int(128 + signal)
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
