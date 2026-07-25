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
