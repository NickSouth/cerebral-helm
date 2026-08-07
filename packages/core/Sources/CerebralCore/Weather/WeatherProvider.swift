import Foundation

/// A single current-conditions sample for the bottom-bar weather slot (NIC-169). Produced by
/// a ``WeatherProvider`` and mapped to the `DashboardWeatherChannel` by the live producer
/// (Increment 5). `condition` is an already-human phrase (e.g. "Partly Cloudy") — the mapping
/// from a provider-specific code (Open-Meteo's WMO `weather_code`, Increment 4) happens inside
/// the concrete provider, so this model stays provider-neutral.
public struct WeatherReading: Equatable, Sendable {
    /// Temperature in °F. Raw (unrounded); the event mapping rounds it for display.
    public let temperatureF: Double
    /// Short, human-readable condition phrase, e.g. "Partly Cloudy". Never a raw code.
    public let condition: String
    /// When the sample was observed (the provider's reported observation time, or fetch time).
    public let observedAt: Date

    public init(temperatureF: Double, condition: String, observedAt: Date) {
        self.temperatureF = temperatureF
        self.condition = condition
        self.observedAt = observedAt
    }
}

/// Why a weather sample could not be produced. Kept coarse and provider-neutral: the event
/// mapping degrades any failure to an honest `unavailable` channel, distinguishing only a
/// missing/denied location (so the bottom bar can say "Location unavailable") from a provider
/// or network failure ("Weather unavailable"). FR-SAF-07: a denied platform permission becomes
/// a capability error with guidance, never a fabricated reading.
public enum WeatherError: Error, Equatable, Sendable {
    /// No usable coordinates — location is denied, undetermined, or unresolved (Increment 3/5).
    case locationUnavailable
    /// The weather provider or network failed, or returned an unparseable response.
    case providerFailed(String)
}

/// Port that fetches current conditions for a coordinate (NIC-169). Provider-neutral and
/// coordinate-driven: the caller (the ``WeatherPublisher``, Increment 5) resolves the location
/// — via CoreLocation — and passes it in, so this contract never touches location permissions.
/// Async because a real provider performs a network fetch (Open-Meteo, Increment 4); the mock
/// resolves synchronously. Throws ``WeatherError`` on failure — the mapping treats it as
/// `unavailable`, never a made-up value.
public protocol WeatherProvider: Sendable {
    func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherReading
}

/// A fixed-outcome ``WeatherProvider`` for pre-Mac builds and tests: it ignores the coordinates
/// and always yields the reading (or throws the error) it was constructed with.
public struct MockWeatherProvider: WeatherProvider {
    private let outcome: Result<WeatherReading, WeatherError>

    public init(reading: WeatherReading) {
        self.outcome = .success(reading)
    }

    public init(error: WeatherError) {
        self.outcome = .failure(error)
    }

    public func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherReading {
        try outcome.get()
    }
}
