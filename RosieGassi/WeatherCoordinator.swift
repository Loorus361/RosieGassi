import Foundation
import CoreLocation
import RosieCore

protocol WeatherFetching: Sendable {
    @MainActor func fetch(coordinate: WeatherCoordinate, locationSource: WeatherLocationSource, at date: Date) async throws -> WeatherSnapshot
}

struct OpenMeteoClient: WeatherFetching {
    var session: URLSession = .shared
    @MainActor func fetch(coordinate: WeatherCoordinate, locationSource: WeatherLocationSource, at date: Date) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,precipitation,wind_speed_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "precipitation_unit", value: "mm"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "GMT")
        ]
        guard let url = components.url else { throw WeatherError.invalidResponse }
        try Task.checkCancellation()
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WeatherError.invalidResponse }
        return try OpenMeteoWeatherParser.parse(data, coordinate: coordinate, locationSource: locationSource, fetchedAt: date)
    }
}

struct FixtureWeatherClient: WeatherFetching {
    @MainActor func fetch(coordinate: WeatherCoordinate, locationSource: WeatherLocationSource, at date: Date) async throws -> WeatherSnapshot {
        WeatherSnapshot(fetchedAt: date, source: "open-meteo", locationSource: locationSource, location: coordinate,
                        temperatureCelsius: 18.4, weatherCode: 3, precipitationMm: 0.2, windSpeedKmh: 12.3,
                        observedAt: date, observationIntervalSeconds: 900)
    }
}
struct FailingWeatherClient: WeatherFetching {
    @MainActor func fetch(coordinate: WeatherCoordinate, locationSource: WeatherLocationSource, at date: Date) async throws -> WeatherSnapshot { throw WeatherError.invalidResponse }
}

@MainActor @Observable
final class WeatherCoordinator {
    private let preferences: UserDefaults
    let engine: WeatherCaptureEngine
    let preview: WeatherHomePreview
    private let homeLocation: WeatherLocationProvider
    private var homeTask: Task<Void, Never>?
    private var homeToken = UUID()
    private(set) var home: WeatherCoordinate?
    private(set) var homeMessage = ""
    let isSynthetic: Bool
    var consent: Bool { engine.consent }
    var coversHomePreview: Bool { preview.coversHomePreview }

    init(store: WalkStore) {
        var defaults = UserDefaults.standard
        var client: any WeatherFetching = OpenMeteoClient()
        var synthetic = false
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--uitest-store"), args.indices.contains(i + 1), let id = UUID(uuidString: args[i + 1]) {
            defaults = UserDefaults(suiteName: "RosieWeather.UITest." + id.uuidString)!
            synthetic = true
            client = args.contains("fail") ? FailingWeatherClient() : FixtureWeatherClient()
            if let j = args.firstIndex(of: "--uitest-home"), args.indices.contains(j + 1) {
                let parts = args[j + 1].split(separator: ",")
                if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
                    defaults.set(lat, forKey: "weather.home.lat")
                    defaults.set(lon, forKey: "weather.home.lon")
                }
            }
            if args.contains("--uitest-weather-consent-v1") {
                defaults.set(true, forKey: "weather.consent")
                defaults.removeObject(forKey: "weather.consent.version")
            }
        }
        #endif
        isSynthetic = synthetic
        preferences = defaults
        if defaults.object(forKey: "weather.home.lat") != nil, defaults.object(forKey: "weather.home.lon") != nil {
            home = WeatherCoordinate(latitude: defaults.double(forKey: "weather.home.lat"), longitude: defaults.double(forKey: "weather.home.lon"))
        }
        let location = WeatherLocationProvider(synthetic: synthetic)
        homeLocation = WeatherLocationProvider(synthetic: synthetic)
        let weatherClient = client
        let fetchWeather: @MainActor (WeatherCoordinate, WeatherLocationSource) async throws -> WeatherSnapshot = { coordinate, source in
            try await weatherClient.fetch(coordinate: coordinate, locationSource: source, at: Date())
        }
        engine = WeatherCaptureEngine(store: store, locate: { await location.coordinate() }, fetch: fetchWeather)
        preview = WeatherHomePreview(fetch: fetchWeather)
        // Existing GPS consent and home coordinates never imply Open-Meteo consent.
        // Version 1 covered walk-start only; home preview needs an explicit expanded confirmation.
        let consented = defaults.bool(forKey: "weather.consent")
        engine.consent = consented
        preview.consent = consented
        preview.coversHomePreview = consented && defaults.integer(forKey: "weather.consent.version") >= 2
    }

    func setConsent(_ value: Bool) {
        preferences.set(value, forKey: "weather.consent")
        if value {
            preferences.set(2, forKey: "weather.consent.version")
        } else {
            preferences.removeObject(forKey: "weather.consent.version")
        }
        engine.consent = value
        preview.consent = value
        preview.coversHomePreview = value
        if value {
            preview.refresh(home: home)
        }
        if !value { cancelHome() }
    }
    func setHomePreviewVisible(_ visible: Bool) {
        if visible {
            preview.refresh(home: home)
        }
        preview.setCardVisible(visible)
    }
    func status(for walk: Walk) -> String {
        engine.walkID == walk.id ? engine.message : "Kein Wetter beim Start gespeichert"
    }
    func capture(for id: UUID, recordRoute: Bool) { engine.capture(id, recordRoute: recordRoute, home: home) }
    func refreshHomePreview(force: Bool = false) { preview.refresh(home: home, force: force) }

    func clearHome() {
        cancelHome()
        engine.cancel()
        preferences.removeObject(forKey: "weather.home.lat")
        preferences.removeObject(forKey: "weather.home.lon")
        home = nil
        homeMessage = "Zuhause entfernt. Gespeicherte Runden bleiben unverändert."
        preview.refresh(home: nil)
    }
    private func cancelHome() {
        homeToken = UUID(); homeTask?.cancel(); homeLocation.cancel(); homeMessage = ""
    }
    func captureHomeFromCurrentLocation() {
        cancelHome()
        let token = homeToken
        homeMessage = "Standort für Zuhause wird ermittelt …"
        homeTask = Task {
            let coordinate = await homeLocation.coordinate()
            guard !Task.isCancelled, homeToken == token else { return }
            guard let coordinate else { homeMessage = "Standort für Zuhause nicht ermittelt. Bitte Standortfreigabe prüfen und erneut versuchen."; return }
            preferences.set(coordinate.latitude, forKey: "weather.home.lat")
            preferences.set(coordinate.longitude, forKey: "weather.home.lon")
            home = coordinate
            homeMessage = WeatherConsentCopy.homeSaved
            preview.refresh(home: coordinate, force: true)
        }
    }
}

/// Home and walk requests use separate providers. Every completion is request-scoped.
@MainActor
final class WeatherLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let synthetic: Bool
    private var manager: CLLocationManager?
    private let request = WeatherLocationRequest()
    private var requestID: UUID? { request.currentID }
    private var requestedAt: Date { request.requestedAt }
    init(synthetic: Bool = false) { self.synthetic = synthetic; super.init() }

    func coordinate() async -> WeatherCoordinate? {
        await request.coordinate(start: { id in
            if synthetic {
                finish(WeatherCoordinate(latitude: 52, longitude: 13), id: id)
                return
            }
            let provider = CLLocationManager()
            manager = provider; provider.delegate = self
            provider.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManagerDidChangeAuthorization(provider)
        }, stop: { [weak self] in
            self?.manager?.stopUpdatingLocation()
            self?.manager?.delegate = nil
            self?.manager = nil
        })
    }
    func cancel() { if let requestID { finish(nil, id: requestID) } }
    private func finish(_ coordinate: WeatherCoordinate?, id: UUID) {
        request.complete(coordinate, id: id)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager, let requestID else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: finish(nil, id: requestID)
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, let requestID else { return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            finish(nil, id: requestID); return
        }
        let now = Date()
        for fix in locations.reversed() {
            let coordinate = WeatherCoordinate(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
            if WeatherFixPolicy.accepts(coordinate: coordinate, timestamp: fix.timestamp, accuracy: fix.horizontalAccuracy,
                                        requestedAt: requestedAt, now: now) {
                finish(coordinate, id: requestID); return
            }
        }
        if !locations.isEmpty { finish(nil, id: requestID) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager, let requestID else { return }
        finish(nil, id: requestID)
    }
}
