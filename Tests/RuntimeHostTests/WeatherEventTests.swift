import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-169 Increment 2: mapping a weather-provider result into the bottom bar's
/// `DashboardWeatherChannel`, and emitting it as a `weather.changed` bridge event.

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("a reading maps to a ready channel with a rounded NN°F · Condition label")
func weatherReadyMapping() {
    let channel = BridgeEventFactory.weather(
        from: .success(WeatherReading(temperatureF: 68.4, condition: "Sunny", observedAt: fixedNow)),
        now: fixedNow
    )
    #expect(channel.state == .ready)
    #expect(channel.temperatureF == 68) // rounded from 68.4
    #expect(channel.condition == "Sunny")
    #expect(channel.label == "68°F · Sunny")
}

@Test("a value rounds to nearest, not truncated")
func weatherRoundsToNearest() {
    let channel = BridgeEventFactory.weather(
        from: .success(WeatherReading(temperatureF: 71.6, condition: "Cloudy", observedAt: fixedNow)),
        now: fixedNow
    )
    #expect(channel.temperatureF == 72)
    #expect(channel.label == "72°F · Cloudy")
}

@Test("a generic provider failure maps to an honest unavailable channel, nothing fabricated")
func weatherProviderFailureMapping() {
    let channel = BridgeEventFactory.weather(
        from: .failure(WeatherError.providerFailed("network down")), now: fixedNow
    )
    #expect(channel.state == .unavailable)
    #expect(channel.temperatureF == nil)
    #expect(channel.condition == nil)
    #expect(channel.label == "Weather unavailable")
}

@Test("a missing/denied location reads 'Location unavailable' (FR-SAF-07)")
func weatherLocationUnavailableMapping() {
    let channel = BridgeEventFactory.weather(
        from: .failure(WeatherError.locationUnavailable), now: fixedNow
    )
    #expect(channel.state == .unavailable)
    #expect(channel.label == "Location unavailable")
}

@Test("the channel emits as a weather.changed event; nil fields are omitted, not null")
func weatherEmitsChangedEvent() throws {
    let channel = BridgeEventFactory.weather(
        from: .success(WeatherReading(temperatureF: 68.0, condition: "Sunny", observedAt: fixedNow)),
        now: fixedNow
    )
    let event = BridgeEventFactory.weatherChangedEvent(
        channel: channel, id: "brevt_test00000169", timestamp: fixedNow
    )

    #expect(event.type == .weatherChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"weather.changed\""))
    #expect(json.contains("\"condition\":\"Sunny\""))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .weatherChanged)
    #expect(decoded.eventID == "brevt_test00000169")
}

@Test("an unavailable channel omits nil temperature and condition rather than writing null")
func weatherUnavailableOmitsNilFields() throws {
    let channel = BridgeEventFactory.weather(
        from: .failure(WeatherError.locationUnavailable), now: fixedNow
    )
    let event = BridgeEventFactory.weatherChangedEvent(
        channel: channel, id: "brevt_test00000170", timestamp: fixedNow
    )
    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(!json.contains("\"temperatureF\":null"))
    #expect(!json.contains("\"condition\":null"))
}
