import AppKit
import SwiftUI

/// Open-Meteo: free, no key, no account. Only the city name is sent.
@MainActor
final class WeatherService: ObservableObject {
    struct Snapshot: Equatable {
        var city: String
        var temperature: Double
        var high: Double
        var low: Double
        var code: Int
        var updated: Date
        var isDay: Bool = true
    }

    enum Status: Equatable {
        case idle
        case loading
        case ok
        case unknownCity
        case offline
    }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var status: Status = .idle

    private var city = ""
    private var refreshTimer: Timer?
    private var geocode: (lat: Double, lon: Double)?

    func start(city: String) {
        self.city = city
        if geocode == nil { geocode = Self.loadGeocode(city) }
        refresh()
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func setCity(_ newCity: String) {
        guard newCity != city else { return }
        city = newCity
        geocode = nil
        snapshot = nil
        start(city: newCity)
    }

    func refresh() {
        guard !city.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = .idle
            return
        }
        status = snapshot == nil ? .loading : status
        Task { [weak self] in
            guard let self else { return }
            guard let point = await self.resolveGeocode() else {
                self.status = .unknownCity
                return
            }
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(point.lat)),
                URLQueryItem(name: "longitude", value: String(point.lon)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
                URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "forecast_days", value: "1")
            ]
            guard let url = components.url,
                  let (data, _) = try? await Self.session.data(from: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.status = .offline
                return
            }
            let current = root["current"] as? [String: Any] ?? [:]
            let daily = root["daily"] as? [String: Any] ?? [:]
            let high = (daily["temperature_2m_max"] as? [Double])?.first ?? 0
            let low = (daily["temperature_2m_min"] as? [Double])?.first ?? 0
            let temperature = current["temperature_2m"] as? Double ?? 0
            let code = current["weather_code"] as? Int ?? 0
            let isDay = (current["is_day"] as? Int ?? 1) == 1
            self.snapshot = Snapshot(city: self.city, temperature: temperature,
                                     high: high, low: low, code: code,
                                     updated: Date(), isDay: isDay)
            self.status = .ok
        }
    }

    private func resolveGeocode() async -> (lat: Double, lon: Double)? {
        if let geocode { return geocode }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url,
              let (data, _) = try? await Self.session.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first,
              let lat = first["latitude"] as? Double,
              let lon = first["longitude"] as? Double else { return nil }
        let resolved = (lat: lat, lon: lon)
        geocode = resolved
        Self.saveGeocode(city, resolved)
        return resolved
    }

    // Geocoding results are cached in UserDefaults, so a city is resolved once.
    private static func loadGeocode(_ city: String) -> (lat: Double, lon: Double)? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "geocode." + city.lowercased()),
              let lat = dict["lat"] as? Double, let lon = dict["lon"] as? Double else { return nil }
        return (lat, lon)
    }

    private static func saveGeocode(_ city: String, _ value: (lat: Double, lon: Double)) {
        UserDefaults.standard.set(["lat": value.lat, "lon": value.lon], forKey: "geocode." + city.lowercased())
    }

    private static var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = ["User-Agent": "Notch/1.0 (macOS)"]
        return URLSession(configuration: config)
    }()

    // MARK: Presentation

    /// Still SF Symbol — no animated weather.
    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
