// Streaming ambient weather events (NIC-169) — the bottom bar's weather producer.
#if canImport(AppKit)
import Foundation
import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// Resolves the device location, fetches current conditions, and emits one `weather.changed`
/// event per tick (NIC-169). The dashboard folds it into `liveWeather`, which the bottom bar
/// renders over the per-mode bootstrap value.
///
/// Mirrors ``ActiveReposPublisher``'s battery/visibility discipline, but on a **slow cadence**
/// (default 15 min — weather changes slowly and each tick makes a network request): the loop is
/// deactivated while the dashboard is not visible (the shell flips `setActive` from the
/// dashboard window's occlusion state) and reactivation emits immediately. The location fix is
/// point-of-use: the first tick triggers the authorization prompt via ``CoreLocationProvider``;
/// a denied grant or a fetch failure emits an honest `unavailable` channel — "Location
/// unavailable" vs "Weather unavailable" — never a fabricated reading (FR-SAF-07).
public actor WeatherPublisher {
    private let location: any LocationProvider
    private let weather: any WeatherProvider
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        location: any LocationProvider,
        weather: any WeatherProvider,
        intervalMs: Int = 900_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.location = location
        self.weather = weather
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the widget
    /// populates as soon as the stream starts rather than after one (long) interval.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tickIfActive()
                try? await Task.sleep(nanoseconds: self.intervalNanos)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample
    /// immediately instead of waiting out the current interval.
    public func setActive(_ nowActive: Bool) async {
        let wasActive = active
        active = nowActive
        if nowActive && !wasActive {
            await tick()
        }
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick()
    }

    private func tick() async {
        let result: Swift.Result<WeatherReading, Error>
        do {
            let fix = try await location.currentLocation()
            let reading = try await weather.currentWeather(latitude: fix.latitude, longitude: fix.longitude)
            result = .success(reading)
        } catch is LocationError {
            // A denied/undetermined grant or no fix: the channel reads "Location unavailable".
            result = .failure(WeatherError.locationUnavailable)
        } catch {
            // A weather provider/network failure: the channel reads "Weather unavailable".
            result = .failure(error)
        }

        let channel = BridgeEventFactory.weather(from: result, now: Date())
        let event = BridgeEventFactory.weatherChangedEvent(
            channel: channel,
            id: BridgeEventFactory.newEventID(),
            timestamp: Date()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }
}
#endif
