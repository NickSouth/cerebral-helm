// NIC-169 Increment 5: streaming ambient weather as weather.changed events.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}

private func waitUntil(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test("the publisher emits ready weather.changed events on cadence from location + provider")
func weatherPublisherEmitsOnCadence() async throws {
    let collector = EventCollector()
    let publisher = WeatherPublisher(
        location: MockLocationProvider(reading: LocationReading(latitude: 37.77, longitude: -122.42)),
        weather: MockWeatherProvider(reading: WeatherReading(temperatureF: 68.4, condition: "Sunny", observedAt: Date())),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 2 }
    await publisher.stop()

    #expect(collector.count >= 2)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .weatherChanged)
    #expect(event.eventID.hasPrefix("brevt_"))
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("\"condition\":\"Sunny\""))
    #expect(collector.all[0].contains("68°F · Sunny"))
}

@Test("a denied location grant emits an honest 'Location unavailable' channel, never fabricated")
func weatherPublisherLocationDenied() async throws {
    let collector = EventCollector()
    let publisher = WeatherPublisher(
        location: MockLocationProvider(error: .permissionDenied),
        weather: MockWeatherProvider(reading: WeatherReading(temperatureF: 70, condition: "Clear", observedAt: Date())),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("Location unavailable"))
}

@Test("a weather provider failure emits an honest 'Weather unavailable' channel")
func weatherPublisherProviderFailure() async throws {
    let collector = EventCollector()
    let publisher = WeatherPublisher(
        location: MockLocationProvider(reading: LocationReading(latitude: 1, longitude: 2)),
        weather: MockWeatherProvider(error: .providerFailed("network down")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("Weather unavailable"))
}

// MARK: - Replay for surfaces that appear mid-session (NIC-172)

/// Counts fetches so a replay can be proven to serve from the last sample rather than hitting the
/// provider again — a companion backdrop appearing must not cost a network round trip.
private final class CountingWeatherProvider: WeatherProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0
    private let reading: WeatherReading

    init(reading: WeatherReading) { self.reading = reading }

    var fetchCount: Int { lock.lock(); defer { lock.unlock() }; return fetches }

    /// Synchronous on purpose: `NSLock` may not be taken directly inside an async function, so the
    /// async provider call stamps through this helper (the same shape as `BridgeSession`).
    private func recordFetch() {
        lock.lock(); fetches += 1; lock.unlock()
    }

    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherReading {
        recordFetch()
        return reading
    }
}

@Test("resend replays the last sample verbatim, without fetching again (NIC-172)")
func weatherPublisherResendReplaysWithoutFetching() async throws {
    let collector = EventCollector()
    let provider = CountingWeatherProvider(
        reading: WeatherReading(temperatureF: 68.4, condition: "Sunny", observedAt: Date())
    )
    let publisher = WeatherPublisher(
        location: MockLocationProvider(reading: LocationReading(latitude: 37.77, longitude: -122.42)),
        weather: provider,
        intervalMs: 5_000, // long, so nothing emits from the cadence during the test
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(2000) { collector.count >= 1 }
    let afterFirstTick = collector.count
    let fetchesAfterFirstTick = provider.fetchCount

    // The companion backdrop's handshake lands: replay the state it missed.
    await publisher.resend()
    await publisher.stop()

    #expect(collector.count == afterFirstTick + 1)
    // Byte-identical to the sample it missed — the surface sees exactly what the others saw.
    #expect(collector.all.last == collector.all[afterFirstTick - 1])
    // And it cost nothing: no second call to the weather provider.
    #expect(provider.fetchCount == fetchesAfterFirstTick)
}

@Test("resend before the first tick emits nothing rather than flashing a wrong state")
func weatherPublisherResendBeforeFirstSample() async throws {
    let collector = EventCollector()
    let publisher = WeatherPublisher(
        location: MockLocationProvider(reading: LocationReading(latitude: 1, longitude: 2)),
        weather: MockWeatherProvider(reading: WeatherReading(temperatureF: 60, condition: "Cloudy", observedAt: Date())),
        intervalMs: 5_000,
        emit: { collector.collect($0) }
    )

    // Never started: there is no sample to replay. Synthesizing an "unavailable" here would show a
    // wrong state ahead of the real reading (FR-SAF-07).
    await publisher.resend()
    #expect(collector.count == 0)
}

@Test("resend replays the honest unavailable state too, not only a good reading")
func weatherPublisherResendReplaysUnavailable() async throws {
    let collector = EventCollector()
    let publisher = WeatherPublisher(
        location: MockLocationProvider(error: .permissionDenied),
        weather: MockWeatherProvider(reading: WeatherReading(temperatureF: 70, condition: "Clear", observedAt: Date())),
        intervalMs: 5_000,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(2000) { collector.count >= 1 }

    await publisher.resend()
    await publisher.stop()

    // A companion must learn that location is denied as reliably as it learns the temperature —
    // otherwise it sits on the empty bootstrap value looking like a load that never finished.
    #expect(collector.all.last?.contains("Location unavailable") == true)
}

@Test("a paused publisher emits nothing; resuming emits immediately")
func weatherPublisherPauseResume() async throws {
    let collector = EventCollector()
    let publisher = WeatherPublisher(
        location: MockLocationProvider(reading: LocationReading(latitude: 1, longitude: 2)),
        weather: MockWeatherProvider(reading: WeatherReading(temperatureF: 60, condition: "Cloudy", observedAt: Date())),
        intervalMs: 5_000, // long, so any emission is from an explicit tick, not the cadence
        emit: { collector.collect($0) }
    )
    await publisher.setActive(false)
    await publisher.start()
    // Paused: the immediate first tick is suppressed.
    try? await Task.sleep(nanoseconds: 120_000_000)
    #expect(collector.count == 0)

    // Resuming emits a fresh sample right away.
    await publisher.setActive(true)
    await waitUntil(2000) { collector.count >= 1 }
    await publisher.stop()
    #expect(collector.count >= 1)
}
#endif
