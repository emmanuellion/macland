import CoreLocation
import Foundation

/// Ville choisie pour la météo.
struct WeatherPlace: Equatable, Identifiable {
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }
}

struct WeatherReport: Equatable {
    var temperature: Double
    var code: Int
    var isDay: Bool
    var high: Double?
    var low: Double?
    var date: Date
}

/// Accès à Open-Meteo (gratuit, sans clé) : recherche de villes et prévisions.
enum WeatherService {
    private struct GeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Result]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
        }
        let current: Current
        let daily: Daily?
    }

    static func search(_ query: String, french: Bool) async throws -> [WeatherPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: french ? "fr" : "en"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map { result in
            WeatherPlace(name: result.name,
                         detail: [result.admin1, result.country].compactMap { $0 }.joined(separator: ", "),
                         latitude: result.latitude, longitude: result.longitude)
        }
    }

    static func forecast(for place: WeatherPlace, fahrenheit: Bool) async throws -> WeatherReport {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if fahrenheit {
            components.queryItems?.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit"))
        }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return WeatherReport(temperature: response.current.temperature_2m,
                             code: response.current.weather_code,
                             isDay: response.current.is_day == 1,
                             high: response.daily?.temperature_2m_max.first ?? nil,
                             low: response.daily?.temperature_2m_min.first ?? nil,
                             date: .now)
    }

    // MARK: Codes météo WMO

    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: "cloud.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func condition(for code: Int) -> String {
        switch code {
        case 0: tr("Dégagé", "Clear")
        case 1: tr("Plutôt dégagé", "Mostly clear")
        case 2: tr("Partiellement nuageux", "Partly cloudy")
        case 3: tr("Couvert", "Overcast")
        case 45, 48: tr("Brouillard", "Fog")
        case 51, 53, 55: tr("Bruine", "Drizzle")
        case 56, 57: tr("Bruine verglaçante", "Freezing drizzle")
        case 61, 63, 80, 81: tr("Pluie", "Rain")
        case 65, 82: tr("Forte pluie", "Heavy rain")
        case 66, 67: tr("Pluie verglaçante", "Freezing rain")
        case 71, 73, 77, 85: tr("Neige", "Snow")
        case 75, 86: tr("Forte neige", "Heavy snow")
        case 95: tr("Orage", "Thunderstorm")
        case 96, 99: tr("Orage et grêle", "Thunderstorm with hail")
        default: tr("Inconnu", "Unknown")
        }
    }
}

/// Position actuelle (une seule fois) et nom de la ville correspondante.
@MainActor
final class CurrentLocationFetcher: NSObject, CLLocationManagerDelegate {
    enum Failure: Error { case denied, unavailable }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<WeatherPlace, Error>?

    func fetch() async throws -> WeatherPlace {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(Failure.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<WeatherPlace, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        manager.delegate = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            switch status {
            case .notDetermined: break
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let name = placemark?.locality ?? placemark?.name ?? tr("Ma position", "My location")
            let detail = [placemark?.administrativeArea, placemark?.country].compactMap { $0 }.joined(separator: ", ")
            finish(.success(WeatherPlace(name: name, detail: detail,
                                         latitude: coordinate.latitude, longitude: coordinate.longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(Failure.unavailable)) }
    }
}
