// NIC-169 Increment 4: Open-Meteo request building, response parsing, and WMO code mapping.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("the request URL targets Open-Meteo's current forecast in Fahrenheit for the coordinate")
func openMeteoRequestURL() throws {
    let url = try #require(OpenMeteoWeatherProvider.requestURL(
        host: "https://api.open-meteo.com", latitude: 37.7749, longitude: -122.4194
    ))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "api.open-meteo.com")
    #expect(components.path == "/v1/forecast")

    let items = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
    )
    #expect(items["latitude"] == "37.7749")
    #expect(items["longitude"] == "-122.4194")
    #expect(items["temperature_unit"] == "fahrenheit")
    #expect(items["current"] == "temperature_2m,weather_code")
}

@Test("a well-formed current-conditions payload parses into a reading")
func openMeteoParsesReading() throws {
    let json = Data("""
    { "latitude": 37.75, "longitude": -122.4,
      "current": { "time": "2026-07-24T18:00", "temperature_2m": 62.3, "weather_code": 2 } }
    """.utf8)

    let reading = try OpenMeteoWeatherProvider.parse(json, now: fixedNow)
    #expect(reading.temperatureF == 62.3)
    #expect(reading.condition == "Partly Cloudy")
    #expect(reading.observedAt == fixedNow)
}

@Test("malformed JSON throws providerFailed, never a fabricated reading")
func openMeteoParseFailure() {
    let garbage = Data("not json".utf8)
    #expect(throws: WeatherError.self) {
        _ = try OpenMeteoWeatherProvider.parse(garbage, now: fixedNow)
    }
    // A structurally-valid payload missing `current` is also a parse failure.
    let missing = Data(#"{ "latitude": 1, "longitude": 2 }"#.utf8)
    #expect(throws: WeatherError.self) {
        _ = try OpenMeteoWeatherProvider.parse(missing, now: fixedNow)
    }
}

@Test("WMO codes map to phrases the bottom-bar glyph buckets (rain/cloud/partly/sun)")
func openMeteoWMOMapping() {
    #expect(OpenMeteoWeatherProvider.conditionForWMO(0) == "Clear")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(2) == "Partly Cloudy")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(3) == "Overcast")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(45) == "Fog")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(51) == "Drizzle")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(61) == "Rain")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(80) == "Rain Showers")
    #expect(OpenMeteoWeatherProvider.conditionForWMO(95) == "Thunderstorm")
    // An unrecognized code stays honest rather than inventing a condition.
    #expect(OpenMeteoWeatherProvider.conditionForWMO(1234) == "Unknown")
}
#endif
