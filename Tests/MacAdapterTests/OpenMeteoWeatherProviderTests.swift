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

// MARK: - Today's forecast (NIC-228)

@Test("the request asks for today's high, low and chance of rain, in the coordinate's own timezone")
func openMeteoRequestsDailyForecast() throws {
    let url = try #require(OpenMeteoWeatherProvider.requestURL(
        host: "https://api.open-meteo.com", latitude: 42.36, longitude: -71.06
    ))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
    )

    #expect(items["daily"] == "temperature_2m_max,temperature_2m_min,precipitation_probability_max")

    // `timezone=auto` is LOAD-BEARING. Open-Meteo documents its default as GMT and states the
    // parameter is required when daily variables are requested, because a daily aggregate needs a
    // midnight-to-midnight window. Without this the window would be a GMT day, which in New England
    // starts at 20:00 the previous evening — so every brief composed after dark would report the
    // wrong day's high, as a perfectly plausible number.
    #expect(items["timezone"] == "auto")
    // Open-Meteo returns seven days by default and the brief asks about one.
    #expect(items["forecast_days"] == "1")

    // The current-conditions half is untouched: the bottom bar still gets exactly what it had.
    #expect(items["current"] == "temperature_2m,weather_code")
}

@Test("today's forecast is read from the daily block's first entry")
func openMeteoParsesDailyForecast() throws {
    // Daily aggregates arrive as PARALLEL ARRAYS, one element per forecast day, not as an array of
    // objects. With `forecast_days=1` today is the only element.
    let json = Data("""
    { "current": { "temperature_2m": 62.3, "weather_code": 2 },
      "daily": { "time": ["2026-08-26"], "temperature_2m_max": [78.4],
                 "temperature_2m_min": [55.1], "precipitation_probability_max": [70] } }
    """.utf8)

    let reading = try OpenMeteoWeatherProvider.parse(json, now: fixedNow)
    #expect(reading.highF == 78.4)
    #expect(reading.lowF == 55.1)
    #expect(reading.precipitationChance == 70)
}

@Test("a response with no daily block still parses, which is what keeps the bottom bar working")
func openMeteoToleratesAbsentDailyBlock() throws {
    // Every response predating this change looked exactly like this. A required `daily` would have
    // turned a cached body into a failed read and the bar into "Weather unavailable".
    let json = Data("""
    { "current": { "temperature_2m": 62.3, "weather_code": 2 } }
    """.utf8)

    let reading = try OpenMeteoWeatherProvider.parse(json, now: fixedNow)
    #expect(reading.temperatureF == 62.3)
    #expect(reading.highF == nil)
    #expect(reading.precipitationChance == nil)
}

@Test("a station reporting no precipitation data leaves the field absent, never zero")
func openMeteoToleratesNullDailyValues() throws {
    // A null is not a zero. "No chance of rain" is a promise, and a station that simply does not
    // measure it has made none.
    let json = Data("""
    { "current": { "temperature_2m": 62.3, "weather_code": 2 },
      "daily": { "temperature_2m_max": [78.4], "temperature_2m_min": [null],
                 "precipitation_probability_max": [null] } }
    """.utf8)

    let reading = try OpenMeteoWeatherProvider.parse(json, now: fixedNow)
    #expect(reading.highF == 78.4)
    #expect(reading.lowF == nil)
    #expect(reading.precipitationChance == nil)
}

@Test("an empty daily block is absent forecast, not a crash on the read the bar depends on")
func openMeteoToleratesEmptyDailyArrays() throws {
    let json = Data("""
    { "current": { "temperature_2m": 62.3, "weather_code": 2 },
      "daily": { "temperature_2m_max": [], "temperature_2m_min": [],
                 "precipitation_probability_max": [] } }
    """.utf8)

    let reading = try OpenMeteoWeatherProvider.parse(json, now: fixedNow)
    #expect(reading.highF == nil)
}
#endif
