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

    /// Builds the Open-Meteo request for a coordinate, in °F: current conditions plus today's
    /// high, low and chance of rain.
    ///
    /// **`timezone=auto` is load-bearing, not tidiness.** Open-Meteo defaults to GMT and its own
    /// documentation states the parameter is *required* when daily variables are requested: a daily
    /// aggregate needs a midnight-to-midnight window, and without this one it would be computed over
    /// a GMT day. In New England that window runs from 20:00 the previous evening, so every brief
    /// composed after dark would report the wrong day's high — a plausible number, quietly for
    /// yesterday.
    ///
    /// `forecast_days=1` because the brief asks about today and Open-Meteo otherwise returns seven.
    static func requestURL(host: String, latitude: Double, longitude: Double) -> URL? {
        guard var components = URLComponents(string: "\(host)/v1/forecast") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
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
        /// Daily aggregates arrive as PARALLEL ARRAYS, one element per forecast day, rather than as
        /// an array of objects. Every field is optional: a station without precipitation data still
        /// returns the block, with nulls in it.
        struct Daily: Decodable {
            let highF: [Double?]?
            let lowF: [Double?]?
            let precipitationChance: [Int?]?
            enum CodingKeys: String, CodingKey {
                case highF = "temperature_2m_max"
                case lowF = "temperature_2m_min"
                case precipitationChance = "precipitation_probability_max"
            }
        }
        let current: Current
        /// Absent when the request asked for no daily variables, which every response predating
        /// this change did — so an old cached body still decodes rather than failing the read.
        let daily: Daily?
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
                observedAt: now,
                // `forecast_days=1`, so today is the only element. Read positionally with a bounds
                // check rather than assumed: a forecast block that came back empty must leave the
                // fields absent, not crash the one read the bottom bar depends on.
                highF: decoded.daily?.highF?.first ?? nil,
                lowF: decoded.daily?.lowF?.first ?? nil,
                precipitationChance: decoded.daily?.precipitationChance?.first ?? nil
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
