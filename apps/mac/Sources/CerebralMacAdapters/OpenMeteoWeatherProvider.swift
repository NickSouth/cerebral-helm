// Current-conditions weather from Open-Meteo (NIC-169).
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Fetches current conditions from Open-Meteo (`api.open-meteo.com`) with `URLSession` — a
/// free, keyless, no-account HTTP weather source (owner decision). Only the coordinate leaves
/// the device, over HTTPS; nothing is stored and no secret is needed. Mirrors the read-only
/// `URLSession` pattern the network speed test uses.
///
/// The WMO `weather_code` is mapped to a short human phrase the bottom bar's `WeatherGlyph`
/// buckets (rain / cloud / partly / sun). Any transport, non-2xx, or decode failure throws
/// ``WeatherError/providerFailed(_:)`` so the widget degrades to an honest "unavailable" —
/// never a fabricated reading.
public struct OpenMeteoWeatherProvider: WeatherProvider {
    private let session: URLSession
    private let host: String

    public init(
        session: URLSession? = nil,
        host: String = "https://api.open-meteo.com",
        resourceTimeout: TimeInterval = 15
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.host = host
    }

    public func currentWeather(latitude: Double, longitude: Double) async throws -> WeatherReading {
        guard let url = Self.requestURL(host: host, latitude: latitude, longitude: longitude) else {
            throw WeatherError.providerFailed("Could not build the weather request URL.")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw WeatherError.providerFailed("Weather service returned an unsuccessful response.")
            }
            return try Self.parse(data, now: Date())
        } catch let error as WeatherError {
            throw error
        } catch {
            throw WeatherError.providerFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the Open-Meteo current-conditions request for a coordinate, in °F.
    static func requestURL(host: String, latitude: Double, longitude: Double) -> URL? {
        guard var components = URLComponents(string: "\(host)/v1/forecast") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit")
        ]
        return components.url
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperatureF: Double
            let weatherCode: Int
            enum CodingKeys: String, CodingKey {
                case temperatureF = "temperature_2m"
                case weatherCode = "weather_code"
            }
        }
        let current: Current
    }

    /// Decodes an Open-Meteo current-conditions payload into a ``WeatherReading``, mapping the
    /// WMO code to a phrase. Throws ``WeatherError/providerFailed(_:)`` on malformed JSON.
    /// `now` is the observation time (the caller passes the fetch time) — a parameter so this
    /// stays pure and deterministically testable.
    static func parse(_ data: Data, now: Date) throws -> WeatherReading {
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return WeatherReading(
                temperatureF: decoded.current.temperatureF,
                condition: conditionForWMO(decoded.current.weatherCode),
                observedAt: now
            )
        } catch {
            throw WeatherError.providerFailed("Could not parse the weather response.")
        }
    }

    /// Maps a WMO weather-interpretation code to a short human phrase. Phrases are chosen so
    /// the bottom bar's `WeatherGlyph` buckets them (its `kindFor` keys on "rain"/"shower"/
    /// "drizzle"/"storm" → rain, "partly" → partly, "cloud"/"overcast"/"fog" → cloud, else
    /// sun). An unrecognized code degrades to a neutral phrase, never a fabricated condition.
    static func conditionForWMO(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
}
#endif
