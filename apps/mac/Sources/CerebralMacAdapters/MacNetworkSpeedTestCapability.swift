// On-demand internet capacity measurement (NIC-135).
#if canImport(AppKit)
import Foundation
import CerebralTools

/// Measures internet download/upload capacity against Cloudflare's well-peered
/// speed endpoints (`speed.cloudflare.com`) with `URLSession`.
///
/// Apple's `networkQuality` was the first engine, but it measures against Apple's
/// own CDN with an L4S/HTTP-3 methodology that badly under-reports download on many
/// networks (observed ~9 Mbps against a real ~145). Cloudflare is the same kind of
/// well-peered path browser speed tests use, so the number matches what users
/// cross-check against. Read-only: it measures and mutates nothing.
///
/// Each direction saturates the link with several parallel streams for a fixed
/// **time window** (not a fixed byte count), so the result stays accurate on fast
/// links and bounded in time on slow ones; a byte cap bounds the data cost on very
/// fast links. Download and upload run sequentially so they never contend and drag
/// each other down (asymmetric-link bufferbloat) — the flaw that made the old
/// engine's download read low while upload looked fine.
public struct MacNetworkSpeedTestCapability: NetworkSpeedTestCapability {
    private let session: URLSession
    private let downloadChunkURL: URL
    private let uploadURL: URL
    private let downloadChunkBytes: Int
    private let uploadChunkBytes: Int
    private let downloadStreams: Int
    private let uploadStreams: Int
    private let downloadWindow: Duration
    private let uploadWindow: Duration
    private let downloadByteCapPerStream: Int
    private let uploadByteCapPerStream: Int

    public init(
        session: URLSession? = nil,
        downloadBase: String = "https://speed.cloudflare.com/__down?bytes=",
        uploadURL: URL = URL(string: "https://speed.cloudflare.com/__up")!,
        resourceTimeout: TimeInterval = 20
    ) {
        let downloadStreams = 6
        let uploadStreams = 4
        let downloadChunkBytes = 4_000_000
        let uploadChunkBytes = 2_000_000
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.httpMaximumConnectionsPerHost = downloadStreams + uploadStreams
            self.session = URLSession(configuration: config)
        }
        self.downloadChunkURL = URL(string: "\(downloadBase)\(downloadChunkBytes)")!
        self.uploadURL = uploadURL
        self.downloadChunkBytes = downloadChunkBytes
        self.uploadChunkBytes = uploadChunkBytes
        self.downloadStreams = downloadStreams
        self.uploadStreams = uploadStreams
        self.downloadWindow = .seconds(5)
        self.uploadWindow = .seconds(4)
        self.downloadByteCapPerStream = 150_000_000 / downloadStreams // ≤150 MB total
        self.uploadByteCapPerStream = 80_000_000 / uploadStreams // ≤80 MB total
    }

    public func measure() async throws -> NetworkSpeedTestReading {
        let downloadMbps = await measureDownload()
        let uploadMbps = await measureUpload()
        return Self.classify(downloadMbps: downloadMbps, uploadMbps: uploadMbps)
    }

    // MARK: - Directions

    private func measureDownload() async -> Double? {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: downloadWindow)
        let bytes = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<downloadStreams {
                group.addTask {
                    var streamBytes = 0
                    while clock.now < deadline, streamBytes < self.downloadByteCapPerStream {
                        streamBytes += await self.downloadOneChunk()
                    }
                    return streamBytes
                }
            }
            var total = 0
            for await streamBytes in group { total += streamBytes }
            return total
        }
        return Self.throughputMbps(bytes: bytes, seconds: Self.seconds(since: start, clock: clock))
    }

    private func downloadOneChunk() async -> Int {
        do {
            let (fileURL, response) = try await session.download(from: downloadChunkURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            guard Self.isSuccess(response) else { return 0 }
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int
            return size ?? downloadChunkBytes
        } catch {
            return 0
        }
    }

    private func measureUpload() async -> Double? {
        let payload = Data(count: uploadChunkBytes) // zero-filled; shared copy-on-write across streams
        let request: URLRequest = {
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            return request
        }()

        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: uploadWindow)
        let bytes = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<uploadStreams {
                group.addTask {
                    var streamBytes = 0
                    while clock.now < deadline, streamBytes < self.uploadByteCapPerStream {
                        streamBytes += await self.uploadOneChunk(request, payload: payload)
                    }
                    return streamBytes
                }
            }
            var total = 0
            for await streamBytes in group { total += streamBytes }
            return total
        }
        return Self.throughputMbps(bytes: bytes, seconds: Self.seconds(since: start, clock: clock))
    }

    private func uploadOneChunk(_ request: URLRequest, payload: Data) async -> Int {
        do {
            let (_, response) = try await session.upload(for: request, from: payload)
            return Self.isSuccess(response) ? payload.count : 0
        } catch {
            return 0
        }
    }

    // MARK: - Pure helpers (unit-tested)

    static func isSuccess(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Aggregate throughput in Mbps (÷1e6 — decimal mega, matching the rest of the
    /// metrics), or `nil` when nothing transferred or the clock is degenerate.
    static func throughputMbps(bytes: Int, seconds: Double) -> Double? {
        guard bytes > 0, seconds > 0 else { return nil }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    /// Maps measured directions onto a reading: both = ok, one = partial, none =
    /// unavailable — never a fabricated figure.
    static func classify(downloadMbps: Double?, uploadMbps: Double?) -> NetworkSpeedTestReading {
        switch (downloadMbps, uploadMbps) {
        case let (down?, up?):
            return NetworkSpeedTestReading(status: .ok, downloadMbps: down, uploadMbps: up)
        case (nil, nil):
            return NetworkSpeedTestReading(status: .unavailable, downloadMbps: nil, uploadMbps: nil)
        default:
            return NetworkSpeedTestReading(status: .partial, downloadMbps: downloadMbps, uploadMbps: uploadMbps)
        }
    }

    private static func seconds(since start: ContinuousClock.Instant, clock: ContinuousClock) -> Double {
        let (secs, attos) = start.duration(to: clock.now).components
        return Double(secs) + Double(attos) / 1e18
    }
}
#endif
