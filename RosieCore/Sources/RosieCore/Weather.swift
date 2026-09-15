import Foundation

public enum WeatherError: LocalizedError {
    case invalidResponse, invalidSnapshot

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Wetterantwort unlesbar. Die Runde läuft ohne Wetter weiter."
        case .invalidSnapshot: "Wetterwerte sind unbrauchbar und wurden nicht gespeichert."
        }
    }
}

public enum WeatherLocationSource: String, Codable, Sendable {
    case gps, home
}

public struct WeatherCoordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public func distanceMeters(to other: WeatherCoordinate) -> Double? {
        guard isValid, other.isValid else { return nil }
        let radians = Double.pi / 180
        let dlat = (other.latitude - latitude) * radians
        let dlon = (other.longitude - longitude) * radians
        let h = pow(sin(dlat / 2), 2) + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin(dlon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}

public struct WeatherLocationChoice: Equatable, Sendable {
    public let coordinate: WeatherCoordinate
    public let source: WeatherLocationSource
}

public struct WeatherLocationSample: Equatable, Sendable {
    public var coordinate: WeatherCoordinate
    public var accuracy: Double
    public var timestamp: Date

    public init(coordinate: WeatherCoordinate, accuracy: Double, timestamp: Date = Date()) {
        self.coordinate = coordinate
        self.accuracy = accuracy
        self.timestamp = timestamp
    }
}

public enum WeatherLocalityRelation: Equatable, Sendable {
    case near, far, unclear
}

/// Time/round validity for weather locality — not GPS route quality (0...100 m).
public enum WeatherLocalityPolicy {
    public static let maximumAge: TimeInterval = 30

    public static func accepts(_ sample: WeatherLocationSample, capturedFrom startedAt: Date, receivedAt: Date) -> Bool {
        guard sample.coordinate.isValid,
              sample.accuracy.isFinite, sample.accuracy >= 0,
              sample.timestamp.timeIntervalSince1970.isFinite,
              sample.timestamp >= .distantPast, sample.timestamp <= .distantFuture,
              sample.timestamp >= startedAt,
              sample.timestamp <= receivedAt,
              receivedAt.timeIntervalSince(sample.timestamp) <= maximumAge else { return false }
        return true
    }

    public static func uniqueObservations(_ samples: [WeatherLocationSample]) -> [WeatherLocationSample] {
        var seen = Set<ObservationIdentity>()
        return samples.filter { seen.insert(ObservationIdentity($0)).inserted }
    }

    private struct ObservationIdentity: Hashable {
        let timestamp: TimeInterval
        let latitude: Double
        let longitude: Double

        init(_ sample: WeatherLocationSample) {
            timestamp = sample.timestamp.timeIntervalSince1970
            latitude = sample.coordinate.latitude
            longitude = sample.coordinate.longitude
        }
    }
}

public enum WeatherNearArea {
    /// Weather locality around stored home, not a city boundary and not GPS-route quality.
    public static let maximumDistanceMeters = 10_000.0
    public static let minimumRouteSamples = 5

    public static func contains(_ coordinate: WeatherCoordinate, home: WeatherCoordinate) -> Bool {
        relation(of: WeatherLocationSample(coordinate: coordinate, accuracy: 0), to: home) == .near
    }

    public static func relation(of sample: WeatherLocationSample, to home: WeatherCoordinate) -> WeatherLocalityRelation {
        guard sample.coordinate.isValid, home.isValid, sample.accuracy.isFinite, sample.accuracy >= 0,
              let distance = sample.coordinate.distanceMeters(to: home) else { return .unclear }
        if distance + sample.accuracy <= maximumDistanceMeters { return .near }
        if distance - sample.accuracy > maximumDistanceMeters { return .far }
        return .unclear
    }
}

public enum WeatherLocationResolver {
    public static func resolve(recordRoute: Bool, gps: WeatherCoordinate?, home: WeatherCoordinate?,
                               routeSamples: [WeatherCoordinate] = [],
                               localitySamples: [WeatherLocationSample] = []) -> WeatherLocationChoice? {
        if recordRoute {
            if let gps, gps.isValid {
                return WeatherLocationChoice(coordinate: gps, source: .gps)
            }
            let samples = localitySamples + routeSamples.map { WeatherLocationSample(coordinate: $0, accuracy: 0) }
            let valid = samples.filter { $0.coordinate.isValid }
            let usableHome = home.flatMap { $0.isValid ? $0 : nil }
            let near: [WeatherLocationSample]
            let far: [WeatherLocationSample]
            if let usableHome {
                near = valid.filter { WeatherNearArea.relation(of: $0, to: usableHome) == .near }
                far = valid.filter { WeatherNearArea.relation(of: $0, to: usableHome) == .far }
            } else {
                near = []
                far = valid
            }
            if let usableHome, far.isEmpty, near.count >= WeatherNearArea.minimumRouteSamples {
                return WeatherLocationChoice(coordinate: usableHome, source: .home)
            }
            if !far.isEmpty, near.isEmpty {
                return WeatherLocationChoice(coordinate: far[0].coordinate, source: .gps)
            }
            if usableHome == nil, valid.count >= WeatherNearArea.minimumRouteSamples {
                return WeatherLocationChoice(coordinate: valid[0].coordinate, source: .gps)
            }
            return nil
        }
        guard let home, home.isValid else { return nil }
        return WeatherLocationChoice(coordinate: home, source: .home)
    }
}

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    /// Provider validity instant, not a sensor measurement time (Open-Meteo uses model data).
    public var observedAt: Date?
    /// Backward-looking accumulation/averaging window ending at observedAt, in seconds.
    public var observationIntervalSeconds: Double?
    public var source: String
    public var locationSource: WeatherLocationSource
    public var location: WeatherCoordinate?
    public var temperatureCelsius: Double?
    public var weatherCode: Int?
    public var precipitationMm: Double?
    public var windSpeedKmh: Double?

    public init(fetchedAt: Date, source: String, locationSource: WeatherLocationSource, location: WeatherCoordinate?,
                temperatureCelsius: Double?, weatherCode: Int?, precipitationMm: Double?, windSpeedKmh: Double?,
                observedAt: Date? = nil, observationIntervalSeconds: Double? = nil) {
        self.fetchedAt = fetchedAt
        self.observedAt = observedAt
        self.observationIntervalSeconds = observationIntervalSeconds
        self.source = source
        self.locationSource = locationSource
        self.location = location
        self.temperatureCelsius = temperatureCelsius
        self.weatherCode = weatherCode
        self.precipitationMm = precipitationMm
        self.windSpeedKmh = windSpeedKmh
    }

    public var conditionLabel: String { WeatherCode.germanLabel(weatherCode) }
    public var systemImage: String { WeatherCode.systemImage(weatherCode) }

    public var compactSummary: String {
        var parts: [String] = []
        if let temperatureCelsius {
            parts.append("\(Self.number(temperatureCelsius)) °C")
        }
        if weatherCode != nil { parts.append(conditionLabel) }
        return parts.joined(separator: " · ")
    }

    public var summary: String {
        var parts: [String] = []
        if let temperatureCelsius {
            parts.append("\(Self.number(temperatureCelsius)) °C")
        }
        if weatherCode != nil { parts.append(conditionLabel) }
        if let precipitationMm, precipitationMm > 0 {
            parts.append("\(Self.number(precipitationMm)) mm")
        }
        if let windSpeedKmh {
            parts.append("Wind \(Self.number(windSpeedKmh)) km/h")
        }
        return parts.isEmpty ? "Wetter ohne Messwerte" : parts.joined(separator: " · ")
    }

    public func validate() throws {
        guard fetchedAt.timeIntervalSince1970.isFinite, !source.isEmpty else { throw WeatherError.invalidSnapshot }
        if let observedAt, !observedAt.timeIntervalSince1970.isFinite { throw WeatherError.invalidSnapshot }
        if let observationIntervalSeconds, !observationIntervalSeconds.isFinite || observationIntervalSeconds <= 0 {
            throw WeatherError.invalidSnapshot
        }
        if let location {
            guard location.isValid else {
                throw WeatherError.invalidSnapshot
            }
        }
        for value in [temperatureCelsius, precipitationMm, windSpeedKmh] {
            if let value { guard value.isFinite else { throw WeatherError.invalidSnapshot } }
        }
        // Broad terrestrial near-surface bounds, not a forecast plausibility filter.
        if let temperatureCelsius, !(-100...70).contains(temperatureCelsius) { throw WeatherError.invalidSnapshot }
        if let precipitationMm, precipitationMm < 0 { throw WeatherError.invalidSnapshot }
        if let windSpeedKmh, windSpeedKmh < 0 { throw WeatherError.invalidSnapshot }
        if let weatherCode, !WeatherCode.supported.contains(weatherCode) { throw WeatherError.invalidSnapshot }
    }

    private static func number(_ value: Double) -> String {
        let string = String(value)
        return string.hasSuffix(".0") ? String(string.dropLast(2)) : string
    }
}

public enum WeatherCode {
    static let supported: Set<Int> = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67,
                                      71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
    public static func germanLabel(_ code: Int?) -> String {
        switch code {
        case 0: "Klar"
        case 1: "Überwiegend klar"
        case 2: "Teilweise bewölkt"
        case 3: "Bewölkt"
        case 45, 48: "Nebel"
        case 51, 53, 55: "Niesel"
        case 56, 57: "Gefrierender Niesel"
        case 61, 63, 65: "Regen"
        case 66, 67: "Gefrierender Regen"
        case 71, 73, 75: "Schnee"
        case 77: "Schneegriesel"
        case 80, 81, 82: "Regenschauer"
        case 85, 86: "Schneeschauer"
        case 95: "Gewitter"
        case 96, 99: "Gewitter mit Hagel"
        case nil: "Unbekannt"
        default: "Wettercode \(code!)"
        }
    }

    public static func systemImage(_ code: Int?) -> String {
        switch code {
        case 0: "sun.max"
        case 1: "sun.min"
        case 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55, 56, 57: "cloud.drizzle"
        case 61, 63, 65, 66, 67: "cloud.rain"
        case 71, 73, 75, 77, 85, 86: "cloud.snow"
        case 80, 81, 82: "cloud.heavyrain"
        case 95, 96, 99: "cloud.bolt.rain"
        default: "cloud.sun"
        }
    }
}

public enum OpenMeteoWeatherParser {
    private enum ResponseTime: Decodable {
        case unix(Double), iso(String)

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self) { self = .unix(seconds) }
            else { self = .iso(try value.decode(String.self)) }
        }

        func date(utcOffset: Int?) throws -> Date? {
            switch self {
            case .unix(let seconds):
                return Date(timeIntervalSince1970: seconds)
            case .iso(let text):
                let iso = ISO8601DateFormatter()
                if let date = iso.date(from: text) { return date }
                iso.formatOptions.insert(.withFractionalSeconds)
                if let date = iso.date(from: text) { return date }
                // timezone=auto returns a local wall clock; never infer the device timezone.
                guard let zone = TimeZone(secondsFromGMT: utcOffset ?? 0) else { throw WeatherError.invalidResponse }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = zone
                formatter.isLenient = false
                for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: text), formatter.string(from: date) == text {
                        return utcOffset == nil ? nil : date
                    }
                }
                throw WeatherError.invalidResponse
            }
        }
    }

    private struct Envelope: Decodable {
        struct Current: Decodable {
            var time: ResponseTime?
            var interval: Double?
            var temperature_2m: Double?
            var weather_code: Int?
            var precipitation: Double?
            var wind_speed_10m: Double?
        }
        var current: Current?
        var utc_offset_seconds: Int?
        var current_units: [String: String?]?
    }

    public static func parse(_ data: Data, coordinate: WeatherCoordinate, locationSource: WeatherLocationSource,
                             fetchedAt: Date) throws -> WeatherSnapshot {
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw WeatherError.invalidResponse }
        guard let current = envelope.current,
              current.temperature_2m != nil || current.weather_code != nil ||
              current.precipitation != nil || current.wind_speed_10m != nil else { throw WeatherError.invalidResponse }
        // Missing units retain compatibility with old fixtures/default C, mm, km/h requests.
        // Supplied incompatible units must never be silently relabeled.
        var expectedUnits = ["temperature_2m": "°C", "precipitation": "mm", "wind_speed_10m": "km/h",
                             "weather_code": "wmo code", "interval": "seconds"]
        if let time = current.time {
            switch time {
            case .unix: expectedUnits["time"] = "unixtime"
            case .iso: expectedUnits["time"] = "iso8601"
            }
        }
        for (key, expected) in expectedUnits {
            if let supplied = envelope.current_units?[key], supplied != expected { throw WeatherError.invalidResponse }
        }
        let snapshot = WeatherSnapshot(fetchedAt: fetchedAt, source: "open-meteo", locationSource: locationSource,
                                       location: coordinate, temperatureCelsius: current.temperature_2m,
                                       weatherCode: current.weather_code, precipitationMm: current.precipitation,
                                       windSpeedKmh: current.wind_speed_10m,
                                       observedAt: try current.time?.date(utcOffset: envelope.utc_offset_seconds),
                                       observationIntervalSeconds: current.interval)
        do { try snapshot.validate() }
        catch { throw WeatherError.invalidResponse }
        return snapshot
    }
}
