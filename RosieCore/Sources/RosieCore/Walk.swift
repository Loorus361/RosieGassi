import Foundation

public enum Checkpoint: String, Codable, CaseIterable, Sendable {
    case ok
    case hesitant = "zögerlich"
    case no = "nein"

    // Storage tokens remain stable for existing diaries and backup files.
    public var displayName: String {
        switch self {
        case .ok: "OK"
        case .hesitant: "Zögerlich"
        case .no: "Schlecht"
        }
    }
}

public enum WalkError: LocalizedError {
    case completed, invalidTime, invalidScore

    public var errorDescription: String? {
        switch self {
        case .completed: "Diese Runde ist bereits beendet."
        case .invalidTime: "Die Zeitangaben passen nicht zusammen. Bitte Start, Ende und Pausen prüfen."
        case .invalidScore: "Bewertungen müssen zwischen 1 und 7 liegen oder offen bleiben."
        }
    }
}

public struct ManualPause: Codable, Equatable, Sendable {
    public let startedAt: Date
    public fileprivate(set) var endedAt: Date?
}

public struct Walk: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public private(set) var startedAt: Date
    public private(set) var endedAt: Date?
    public let timeZoneID: String
    public internal(set) var route: WalkRoute?
    public internal(set) var weather: WeatherSnapshot?
    public var lameness: Double?
    public var motivation: Double?
    public var elevator: Checkpoint? = .ok
    public var hallway: Checkpoint? = .ok
    public var courtyard: Checkpoint? = .ok
    public var notes = ""
    public internal(set) var customFields: [CustomFieldObservation] = []
    public private(set) var pauses: [ManualPause] = []

    public var isPaused: Bool { endedAt == nil && pauses.last?.endedAt == nil && !pauses.isEmpty }

    public func requiresEditConfirmation(at now: Date) -> Bool {
        guard let endedAt else { return false }
        return now.timeIntervalSince(endedAt) >= 5 * 60
    }

    public init(
        startedAt: Date,
        timeZoneID: String = TimeZone.current.identifier,
        recordRoute: Bool = false,
        customFields: [CustomFieldObservation] = []
    ) {
        route = recordRoute ? WalkRoute() : nil
        self.id = UUID()
        self.startedAt = startedAt
        self.timeZoneID = timeZoneID
        self.customFields = customFields
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, timeZoneID, route, weather, lameness, motivation
        case elevator, hallway, courtyard, notes, pauses, customFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        timeZoneID = try container.decode(String.self, forKey: .timeZoneID)
        route = try container.decodeIfPresent(WalkRoute.self, forKey: .route)
        weather = try container.decodeIfPresent(WeatherSnapshot.self, forKey: .weather)
        lameness = try container.decodeIfPresent(Double.self, forKey: .lameness)
        motivation = try container.decodeIfPresent(Double.self, forKey: .motivation)
        elevator = try container.decodeIfPresent(Checkpoint.self, forKey: .elevator)
        hallway = try container.decodeIfPresent(Checkpoint.self, forKey: .hallway)
        courtyard = try container.decodeIfPresent(Checkpoint.self, forKey: .courtyard)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        pauses = try container.decodeIfPresent([ManualPause].self, forKey: .pauses) ?? []
        customFields = try container.decodeIfPresent([CustomFieldObservation].self, forKey: .customFields) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(timeZoneID, forKey: .timeZoneID)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encodeIfPresent(lameness, forKey: .lameness)
        try container.encodeIfPresent(motivation, forKey: .motivation)
        try container.encodeIfPresent(elevator, forKey: .elevator)
        try container.encodeIfPresent(hallway, forKey: .hallway)
        try container.encodeIfPresent(courtyard, forKey: .courtyard)
        try container.encode(notes, forKey: .notes)
        try container.encode(pauses, forKey: .pauses)
        try container.encode(customFields, forKey: .customFields)
    }

    public mutating func setCustomField(_ id: UUID, value: CustomFieldValue) throws {
        guard let index = customFields.firstIndex(where: { $0.definition.id == id }) else {
            throw CustomFieldError.unknownField
        }
        var observation = customFields[index]
        observation.value = value
        try observation.validate()
        customFields[index] = observation
    }

    public func totalDuration(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    public func pauseDuration(at now: Date) -> TimeInterval {
        let end = endedAt ?? now
        return pauses.reduce(0) { total, pause in
            total + max(0, min(pause.endedAt ?? end, end).timeIntervalSince(pause.startedAt))
        }
    }

    public mutating func pause(at date: Date) throws {
        guard endedAt == nil else { throw WalkError.completed }
        if isPaused { return }
        guard date >= (pauses.last?.endedAt ?? startedAt) else { throw WalkError.invalidTime }
        pauses.append(ManualPause(startedAt: date))
    }

    public mutating func resume(at date: Date) throws {
        guard endedAt == nil else { throw WalkError.completed }
        guard isPaused else { return }
        guard date >= pauses[pauses.count - 1].startedAt else { throw WalkError.invalidTime }
        pauses[pauses.count - 1].endedAt = date
    }

    public mutating func finish(at date: Date) throws {
        if endedAt != nil { return }
        let lastEvent = pauses.last.map { $0.endedAt ?? $0.startedAt } ?? startedAt
        guard date >= lastEvent else { throw WalkError.invalidTime }
        if isPaused { pauses[pauses.count - 1].endedAt = date }
        route?.points.removeAll { $0.timestamp > date }
        endedAt = date
    }

    public func validate() throws {
        try route?.validate(startedAt: startedAt, endedAt: endedAt)
        try weather?.validate()
        guard Set(customFields.map(\.definition.id)).count == customFields.count else { throw CustomFieldError.invalidValue }
        for observation in customFields { try observation.validate() }
        guard startedAt.timeIntervalSince1970.isFinite,
              endedAt?.timeIntervalSince1970.isFinite != false,
              endedAt.map({ $0 >= startedAt }) ?? true else { throw WalkError.invalidTime }
        for score in [lameness, motivation].compactMap({ $0 }) {
            guard score.isFinite, (1...7).contains(score) else { throw WalkError.invalidScore }
        }
        var previous = startedAt
        for (index, pause) in pauses.enumerated() {
            guard pause.startedAt.timeIntervalSince1970.isFinite,
                  pause.startedAt >= previous else { throw WalkError.invalidTime }
            if let end = pause.endedAt {
                guard end.timeIntervalSince1970.isFinite, end >= pause.startedAt,
                      endedAt.map({ end <= $0 }) ?? true else { throw WalkError.invalidTime }
                previous = end
            } else {
                guard endedAt == nil, index == pauses.count - 1 else { throw WalkError.invalidTime }
            }
        }
    }

    /// UI-Pfad: `WalkStore.update(id, confirmingEdit:) { try $0.correctTimes(start:end:) }`.
    /// Laufende Runde: `end == nil` (keine Endzeit, Runde bleibt offen). Abgeschlossen: `end != nil`.
    /// Dauer und Pausenzeit kommen danach aus den neuen Zeitstempeln; GPS-Zeiten werden nicht verschoben.
    /// Beim Verengen des Intervalls werden GPS-Punkte außerhalb der neuen Grenzen entfernt
    /// (zeitgleiches Trimmen, nicht künstliches Klemmen). Erweiterungen lassen alle Punkte stehen.
    /// Änderung und Trimmen sind atomar: Scheitert die Prüfung, bleibt `self` vollständig unverändert.
    public mutating func correctTimes(start: Date, end: Date?) throws {
        var candidate = self
        // Corrections don't silently reopen or finish a round.
        guard (end == nil) == (endedAt == nil) else { throw WalkError.invalidTime }
        candidate.startedAt = start
        candidate.endedAt = end
        candidate.route?.removePointsOutside(startedAt: start, endedAt: end)
        try candidate.validate()
        self = candidate
    }
}
