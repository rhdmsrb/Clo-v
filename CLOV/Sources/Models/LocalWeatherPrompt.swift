import Combine
import CoreLocation
import Foundation

struct LocalWeatherConditions: Equatable {
    let temperatureC: Double
    let feelsLikeC: Double
    let precipitationMM: Double
    let rainMM: Double
    let showersMM: Double
    let snowfallCM: Double
    let weatherCode: Int
    let windKPH: Double
    let todayLowC: Double
    let todayHighC: Double
    let rainChancePercent: Int
    let todayMaxWindKPH: Double
    let todayWeatherCode: Int

    var temperatureText: String {
        if Locale.current.measurementSystem == .us {
            return "\(Int((temperatureC * 9 / 5 + 32).rounded()))°F"
        }
        return "\(Int(temperatureC.rounded()))°C"
    }

    var feelsLikeTemperatureC: Double { feelsLikeC }
    var todayHighText: String {
        let high = Locale.current.measurementSystem == .us ? todayHighC * 9 / 5 + 32 : todayHighC
        return "H \(Int(high.rounded()))°"
    }
    var summary: String { "\(temperatureText) · \(condition) · \(todayHighText)" }
    var icon: String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1...3: "cloud.sun.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    var condition: String {
        switch weatherCode {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...55: "Drizzle"
        case 56, 57, 66, 67: "Freezing rain"
        case 61...65: "Rain"
        case 71...77, 85, 86: "Snow"
        case 80...82: "Showers"
        case 95...99: "Thunderstorms"
        default: "Current conditions"
        }
    }

    var isWet: Bool {
        precipitationMM > 0 || rainMM > 0 || showersMM > 0 || rainChancePercent >= 40 || (51...67).contains(weatherCode) || (80...82).contains(weatherCode)
    }
    var isSnowy: Bool { snowfallCM > 0 || (71...77).contains(weatherCode) || (85...86).contains(weatherCode) }
}

@MainActor
final class LocalWeatherPromptModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var conditions: LocalWeatherConditions?
    @Published private(set) var isLoading = false
    @Published private(set) var locationDenied = false
    @Published private(set) var errorMessage: String?

    private let locationManager = CLLocationManager()
    private var shouldFetchWeather = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestWeather() {
        errorMessage = nil
        locationDenied = false
        shouldFetchWeather = true
        isLoading = true

        guard CLLocationManager.locationServicesEnabled() else {
            shouldFetchWeather = false
            isLoading = false
            errorMessage = "Turn on Location Services to get a weather-based prompt."
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            shouldFetchWeather = false
            isLoading = false
            locationDenied = true
        @unknown default:
            shouldFetchWeather = false
            isLoading = false
            errorMessage = "Location is unavailable right now."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shouldFetchWeather else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            shouldFetchWeather = false
            isLoading = false
            locationDenied = true
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard shouldFetchWeather, let location = locations.last else { return }
        shouldFetchWeather = false
        Task { await fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard shouldFetchWeather else { return }
        shouldFetchWeather = false
        isLoading = false
        errorMessage = "Couldn't get your location. Try again or use the regular prompt."
    }

    /// Coordinates are rounded to ~11 km before leaving the device; that is
    /// plenty for a forecast and matches the "coarse location" privacy label.
    private func fetchWeather(latitude: Double, longitude: Double) async {
        defer { isLoading = false }
        do {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(format: "%.1f", latitude)),
                URLQueryItem(name: "longitude", value: String(format: "%.1f", longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,precipitation,rain,showers,snowfall,weather_code,wind_speed_10m"),
                URLQueryItem(name: "daily", value: "temperature_2m_min,temperature_2m_max,precipitation_probability_max,wind_speed_10m_max,weather_code"),
                URLQueryItem(name: "timezone", value: "auto")
            ]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 15
            request.setValue("CLO-V iOS", forHTTPHeaderField: "User-Agent")
            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            guard (httpResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let decoded = response.current
            let daily = response.daily
            conditions = LocalWeatherConditions(
                temperatureC: decoded.temperature,
                feelsLikeC: decoded.apparentTemperature,
                precipitationMM: decoded.precipitation,
                rainMM: decoded.rain,
                showersMM: decoded.showers,
                snowfallCM: decoded.snowfall,
                weatherCode: decoded.weatherCode,
                windKPH: decoded.windSpeed,
                todayLowC: daily.temperature2mMin.first ?? decoded.apparentTemperature,
                todayHighC: daily.temperature2mMax.first ?? decoded.temperature,
                rainChancePercent: (daily.precipitationProbabilityMax.first ?? nil) ?? 0,
                todayMaxWindKPH: daily.windSpeed10mMax.first ?? decoded.windSpeed,
                todayWeatherCode: daily.weatherCode.first ?? decoded.weatherCode
            )
            errorMessage = nil
        } catch {
            errorMessage = "Weather couldn't load. Your regular daily prompt is still here."
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let temperature: Double
        let apparentTemperature: Double
        let precipitation: Double
        let rain: Double
        let showers: Double
        let snowfall: Double
        let weatherCode: Int
        let windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitation, rain, showers, snowfall
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct Daily: Decodable {
        let temperature2mMin: [Double]
        let temperature2mMax: [Double]
        let precipitationProbabilityMax: [Int?]
        let windSpeed10mMax: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case temperature2mMin = "temperature_2m_min"
            case temperature2mMax = "temperature_2m_max"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeed10mMax = "wind_speed_10m_max"
            case weatherCode = "weather_code"
        }
    }
}
