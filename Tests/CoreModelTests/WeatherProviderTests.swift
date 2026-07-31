import Foundation
import Testing

import CerebralCore

/// NIC-169 Increment 2: the portable weather-provider contract — a provider-neutral
/// ``WeatherReading`` + ``WeatherProvider`` port with a fixed-outcome mock. The real
/// coordinate-driven Open-Meteo fetch lands in the Mac adapter (Increment 4).

@Test("the mock provider yields its constructed reading, ignoring coordinates")
func mockYieldsReading() async throws {
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let provider = MockWeatherProvider(
        reading: WeatherReading(temperatureF: 68.4, condition: "Sunny", observedAt: observedAt)
    )

    let reading = try await provider.currentWeather(latitude: 37.77, longitude: -122.42)
    #expect(reading.temperatureF == 68.4)
    #expect(reading.condition == "Sunny")
    #expect(reading.observedAt == observedAt)
}

@Test("the mock provider throws its constructed error")
func mockThrowsError() async {
    let provider = MockWeatherProvider(error: .locationUnavailable)
    await #expect(throws: WeatherError.locationUnavailable) {
        try await provider.currentWeather(latitude: 0, longitude: 0)
    }
}

@Test("WeatherError distinguishes a missing location from a provider failure")
func errorCasesAreDistinct() {
    #expect(WeatherError.locationUnavailable != WeatherError.providerFailed("boom"))
    #expect(WeatherError.providerFailed("a") == WeatherError.providerFailed("a"))
}
