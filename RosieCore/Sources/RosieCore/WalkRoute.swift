import Foundation

public struct RoutePoint: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public internal(set) var segmentID: UUID

    public init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double, segmentID: UUID = UUID()) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.segmentID = segmentID
    }
}

public enum RouteError: LocalizedError {
    case invalidRoute, pointBudgetExceeded, captureDisabled
    public var errorDescription: String? {
        switch self {
        case .invalidRoute: "Die GPS-Punkte passen nicht zur Runde oder sind ungültig. Zeitkorrektur nicht übernommen."
        case .pointBudgetExceeded: "Die GPS-Grenze von 10.000 Punkten ist erreicht. Keine weiteren Punkte gespeichert."
        case .captureDisabled: "Für diese Runde ist keine GPS-Aufzeichnung aktiv."
        }
    }
}

public struct EstimatedRouteGeometry: Equatable, Sendable {
    public var segments: [[RoutePoint]]
    public var distanceMeters: Double?
}

public struct WalkRoute: Codable, Equatable, Sendable {
    public static let maximumPoints = 10_000
    public static let estimateMaxSpeedMetersPerSecond = 3.0
    public static let estimateMaxAccuracyMeters = 25.0
    public static let simplifyToleranceMeters = 10.0
    /// Historical capture intent, NOT system authorization or permission to restart a sensor.
    public internal(set) var captureRequested = true
    /// Persisted safety barrier: importing a route never authorizes new capture.
    public internal(set) var requiresCaptureConfirmation: Bool?
    public internal(set) var points: [RoutePoint] = []
    public internal(set) var currentSegmentID = UUID()
    /// Parameterlose Ableitung mit dem heutigen Verhalten (Profil „Standard“).
    public var estimatedGeometry: EstimatedRouteGeometry { estimatedGeometry(profile: .standard) }

    /// Reine Ableitung aus den gespeicherten Rohpunkten. Das Profil ändert nur die
    /// RDP-Toleranz; Genauigkeits-/Tempo-Schutzfilter bleiben fest.
    public func estimatedGeometry(profile: RouteFilterProfile) -> EstimatedRouteGeometry {
        let segments = storedSegments.flatMap { Self.derivedSegments($0, toleranceMeters: profile.simplificationToleranceMeters) }
        let hops = segments.flatMap { zip($0, $0.dropFirst()) }
        let distance = hops.isEmpty ? nil : hops.reduce(0) { $0 + Self.distance($1.0, $1.1) }
        return EstimatedRouteGeometry(segments: segments, distanceMeters: distance)
    }
    public var simplifiedSegments: [[RoutePoint]] { estimatedGeometry.segments }
    public func simplifiedSegments(profile: RouteFilterProfile) -> [[RoutePoint]] { estimatedGeometry(profile: profile).segments }
    public var estimatedDistanceMeters: Double? { estimatedGeometry.distanceMeters }
    public func estimatedDistanceMeters(profile: RouteFilterProfile) -> Double? { estimatedGeometry(profile: profile).distanceMeters }

    public mutating func beginSegment() { currentSegmentID = UUID() }

    /// Pure filter; timestamps are never shifted. Incoming segment IDs are ignored.
    @discardableResult
    public mutating func append(_ samples: [RoutePoint], startedAt: Date, receivedAt: Date) throws -> Int {
        guard captureRequested, requiresCaptureConfirmation != true else { throw RouteError.captureDisabled }
        guard receivedAt.timeIntervalSince1970.isFinite else { return 0 }
        var candidate = self
        let accepted = try candidate.appendValidated(samples, startedAt: startedAt, receivedAt: receivedAt)
        self = candidate
        return accepted
    }

    private mutating func appendValidated(_ samples: [RoutePoint], startedAt: Date, receivedAt: Date) throws -> Int {
        let originalCount = points.count
        for var point in samples {
            guard Self.valid(point), point.timestamp >= startedAt,
                  point.timestamp <= receivedAt,
                  receivedAt.timeIntervalSince(point.timestamp) <= 30 else { continue }
            if let last = points.last {
                let elapsed = point.timestamp.timeIntervalSince(last.timestamp)
                guard elapsed > 0 else { continue }
                if elapsed > 60 { beginSegment() }
                if last.segmentID == currentSegmentID && Self.distance(last, point) / elapsed > 12 { continue }
            }
            guard points.count < Self.maximumPoints else { throw RouteError.pointBudgetExceeded }
            point.segmentID = currentSegmentID
            points.append(point)
        }
        return points.count - originalCount
    }

    static func valid(_ point: RoutePoint) -> Bool {
        point.timestamp.timeIntervalSince1970.isFinite && point.timestamp >= .distantPast && point.timestamp <= .distantFuture
        && point.latitude.isFinite && (-90...90).contains(point.latitude)
        && point.longitude.isFinite && (-180...180).contains(point.longitude)
        && point.horizontalAccuracy.isFinite && (0...100).contains(point.horizontalAccuracy)
    }

    static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let radians = Double.pi / 180
        let dlat = (b.latitude - a.latitude) * radians
        let dlon = (b.longitude - a.longitude) * radians
        let h = pow(sin(dlat / 2), 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * pow(sin(dlon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }

    private var storedSegments: [[RoutePoint]] {
        var segments: [[RoutePoint]] = []
        for point in points {
            if segments.last?.last?.segmentID == point.segmentID {
                segments[segments.count - 1].append(point)
            } else {
                segments.append([point])
            }
        }
        return segments
    }

    private static func derivedSegments(_ segment: [RoutePoint], toleranceMeters: Double) -> [[RoutePoint]] {
        let usable = segment.filter { $0.horizontalAccuracy <= estimateMaxAccuracyMeters }
        var runs: [[RoutePoint]] = []
        var current: [RoutePoint] = []
        var pending: RoutePoint?
        func closeRun() {
            if !current.isEmpty { runs.append(current) }
            current = []
            pending = nil
        }
        for point in usable {
            if current.isEmpty && pending == nil {
                pending = point
                continue
            }
            let previous = current.last ?? pending!
            let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
            guard elapsed > 0 else { continue }
            if elapsed > 60 {
                closeRun()
                pending = point
                continue
            }
            if distance(previous, point) / elapsed > estimateMaxSpeedMetersPerSecond {
                if current.isEmpty {
                    pending = point
                }
                continue
            }
            if let start = pending {
                current.append(start)
                pending = nil
            }
            current.append(point)
        }
        if !current.isEmpty { runs.append(current) }
        else if let leftover = pending { runs.append([leftover]) }
        return runs.map { simplify($0, toleranceMeters: toleranceMeters) }.filter { !$0.isEmpty }
    }

    private static func simplify(_ points: [RoutePoint], toleranceMeters: Double) -> [RoutePoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            var maxDistance = -1.0
            var index = first
            for i in (first + 1)..<last {
                let d = perpendicularDistanceMeters(points[i], start: points[first], end: points[last])
                if d > maxDistance {
                    maxDistance = d
                    index = i
                }
            }
            if maxDistance > toleranceMeters {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func perpendicularDistanceMeters(_ point: RoutePoint, start: RoutePoint, end: RoutePoint) -> Double {
        let lat0 = start.latitude * .pi / 180
        func enu(_ p: RoutePoint) -> (Double, Double) {
            ((p.longitude - start.longitude) * cos(lat0) * 111_320,
             (p.latitude - start.latitude) * 110_540)
        }
        let (px, py) = enu(point)
        let (bx, by) = enu(end)
        let length = bx * bx + by * by
        if length == 0 { return hypot(px, py) }
        let t = max(0, min(1, (px * bx + py * by) / length))
        return hypot(px - t * bx, py - t * by)
    }
    /// Entfernt gespeicherte Punkte außerhalb des inklusiven Intervalls `[startedAt, endedAt]`.
    /// Zeitstempel werden nie verschoben oder geklemmt: Übrig bleiben ausschließlich echte
    /// Messpunkte. Ein leerer Rest ist eine gültige Route ohne erfundene Distanz.
    public mutating func removePointsOutside(startedAt: Date, endedAt: Date?) {
        points.removeAll { point in
            if point.timestamp < startedAt { return true }
            if let endedAt, point.timestamp > endedAt { return true }
            return false
        }
    }

    public func validate(startedAt: Date, endedAt: Date?) throws {
        guard points.count <= Self.maximumPoints else { throw RouteError.pointBudgetExceeded }
        var seen = Set<UUID>()
        var previous: RoutePoint?
        for point in points {
            guard Self.valid(point), point.timestamp >= startedAt,
                  endedAt.map({ point.timestamp <= $0 }) ?? true else { throw RouteError.invalidRoute }
            if let last = previous {
                let elapsed = point.timestamp.timeIntervalSince(last.timestamp)
                guard elapsed > 0 else { throw RouteError.invalidRoute }
                if point.segmentID == last.segmentID {
                    guard elapsed <= 60, Self.distance(last, point) / elapsed <= 12 else { throw RouteError.invalidRoute }
                } else if seen.contains(point.segmentID) { throw RouteError.invalidRoute }
            }
            seen.insert(point.segmentID)
            previous = point
        }
    }
    public init() {}
}
