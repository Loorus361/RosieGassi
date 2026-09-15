import Foundation

/// Messreihe des gemeinsamen Verlaufsdiagramms.
///
/// Die Skalenrichtung ist Teil der Schnittstelle und muss in der UI erklärt werden;
/// eine Zahl ohne Richtung ist nicht interpretierbar. Keine medizinische Kausalaussage.
public enum ScoreMetric: String, CaseIterable, Codable, Sendable {
    case motivation
    case lameness

    public var displayName: String {
        switch self {
        case .motivation: "Motivation"
        case .lameness: "Lahmheit"
        }
    }

    /// Verbindliche Richtungsangabe für die UI.
    public var scaleNote: String {
        switch self {
        case .motivation: "höher = besser"
        case .lameness: "höher = stärker"
        }
    }

    /// Gemeinsame feste Skala 1–7, keine freien Achsen.
    public var scale: ClosedRange<Double> { 1...7 }
}

/// Eine einzelne Runde im gefilterten Datenbestand, chronologisch einsortiert.
///
/// Identität ist die `Walk.id` und bleibt über Neuberechnungen stabil.
/// `nil` bedeutet ausdrücklich „nicht vorhanden“ und wird niemals durch 0 oder
/// einen Normalwert ersetzt.
public struct EvaluationRound: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let timeZoneID: String
    public let bucket: TimeOfDayBucket
    /// Nur bei abgeschlossenen Runden vorhanden; offene Runden haben keine feste Dauer.
    public let duration: TimeInterval?
    public let motivation: Double?
    public let lameness: Double?
    /// Geschätzte GPS-Strecke der Anzeigeableitung (Rohpunkte bleiben unverändert).
    public let estimatedDistanceMeters: Double?

    public var isOpen: Bool { endedAt == nil }

    public func score(for metric: ScoreMetric) -> Double? {
        switch metric {
        case .motivation: motivation
        case .lameness: lameness
        }
    }

    public func hasAnyScore(_ metrics: [ScoreMetric] = ScoreMetric.allCases) -> Bool {
        metrics.contains { score(for: $0) != nil }
    }
}

/// Anzahl bewerteter Runden und Bezugsgröße, z. B. „9 von 13 bewertet“.
public struct EvaluationCoverage: Equatable, Sendable {
    public let scored: Int
    public let total: Int

    public init(scored: Int, total: Int) {
        self.scored = scored
        self.total = total
    }

    /// `nil` ohne Bezugsrunden; kein stiller Nenner von 0.
    public var fraction: Double? { total == 0 ? nil : Double(scored) / Double(total) }

    public var text: String { "\(scored) von \(total) bewertet" }
    public var roundText: String { "\(scored) von \(total) Runden" }
}

/// Mittelwert ausschließlich aus vorhandenen Werten samt sichtbarer Datenbasis.
public struct EvaluationAverage: Equatable, Sendable {
    /// Mittelwert der vorhandenen Werte; `nil`, wenn kein Wert vorliegt.
    public let value: Double?
    /// Summe der vorhandenen Werte (nur sinnvoll für Summen-Metriken).
    public let sum: Double
    /// Anzahl der tatsächlich vorhandenen Werte (Nenner des Mittelwerts).
    public let sampleCount: Int
    /// Bezugsgröße, üblicherweise die Rundenzahl des gefilterten Bestands.
    public let totalCount: Int

    public init(values: [Double], totalCount: Int) {
        let usable = values.filter { $0.isFinite }
        sum = usable.reduce(0, +)
        sampleCount = usable.count
        self.totalCount = totalCount
        value = usable.isEmpty ? nil : sum / Double(usable.count)
    }

    public var hasValue: Bool { value != nil }
    public var coverage: EvaluationCoverage { EvaluationCoverage(scored: sampleCount, total: totalCount) }
    public var coverageText: String { coverage.text }
}

/// Kennzahlen des gefilterten Bestands. Alle Werte reagieren auf denselben Filter;
/// Mittelwerte nutzen nur vorhandene Werte, Halbwerte bleiben unverändert.
public struct EvaluationMetrics: Equatable, Sendable {
    public let roundCount: Int
    public let totalDuration: TimeInterval
    public let averageDuration: EvaluationAverage
    public let totalEstimatedDistanceMeters: Double
    public let averageEstimatedDistanceMeters: EvaluationAverage
    public let motivation: EvaluationAverage
    public let lameness: EvaluationAverage
    /// Runden mit mindestens einem vorhandenen Score (Motivation oder Lahmheit).
    public let scoredRounds: Int

    public var dataCoverage: EvaluationCoverage {
        EvaluationCoverage(scored: scoredRounds, total: roundCount)
    }

    public var durationCoverage: EvaluationCoverage { averageDuration.coverage }
    public var distanceCoverage: EvaluationCoverage { averageEstimatedDistanceMeters.coverage }
}

/// Identität eines Diagrammpunkts: Runde plus Messreihe.
public struct ScorePointID: Hashable, Sendable {
    public let roundID: UUID
    public let metric: ScoreMetric
}

/// Ein Punkt je Runde und vorhandenem Score; keine Tagesmittel.
public struct ScorePoint: Identifiable, Equatable, Sendable {
    public let id: ScorePointID
    public let roundID: UUID
    public let date: Date
    public let value: Double
    public let bucket: TimeOfDayBucket

    public var metric: ScoreMetric { id.metric }
}

/// Diagrammgrundlage je Messreihe.
///
/// Zusammenhängende Abschnitte: eine Runde ohne Wert für diese Messreihe trennt sie,
/// damit Linien fehlende Zwischenwerte nicht als geschlossenen Verlauf vortäuschen.
/// Die Messreihen sind unabhängig; eine Lücke in Motivation trennt nicht Lahmheit.
public struct ScoreSeries: Equatable, Sendable {
    public let metric: ScoreMetric
    public let segments: [[ScorePoint]]
    public let scoredRoundCount: Int
    public let totalRoundCount: Int

    public var points: [ScorePoint] { segments.flatMap { $0 } }
    public var hasGap: Bool { segments.count > 1 }
    public var isEmpty: Bool { points.isEmpty }
    public var coverage: EvaluationCoverage {
        EvaluationCoverage(scored: scoredRoundCount, total: totalRoundCount)
    }
}

/// Vollständiges Ergebnis einer Auswertung: Filter, Bereich, Runden, Kennzahlen, Reihen.
public struct EvaluationResult: Equatable, Sendable {
    public let filter: EvaluationFilter
    public let interval: DateInterval
    /// Chronologisch aufsteigend; bei gleicher Startzeit nach Identität stabil sortiert.
    public let rounds: [EvaluationRound]
    public let metrics: EvaluationMetrics
    public let motivationSeries: ScoreSeries
    public let lamenessSeries: ScoreSeries

    public func series(for metric: ScoreMetric) -> ScoreSeries {
        switch metric {
        case .motivation: motivationSeries
        case .lameness: lamenessSeries
        }
    }

    public func round(_ id: UUID) -> EvaluationRound? {
        rounds.first { $0.id == id }
    }

    public var isEmpty: Bool { rounds.isEmpty }
}

/// Gemeinsame Auswertungsbasis für Kalenderzeitraum, Tageszeit-Mehrfachfilter,
/// chronologische Runden, Kennzahlen und Diagrammreihen.
///
/// Reine Funktion ohne Seiteneffekte: liest weder Persistenz noch Uhrzeit und
/// verändert die übergebenen Runden nicht. Die GPS-Strecke kommt aus derselben
/// abgeleiteten Anzeigegeometrie wie die Karte (`RouteFilterProfile`).
public enum WalkEvaluation {
    public static func evaluate(
        _ walks: [Walk],
        filter: EvaluationFilter,
        calendar: EvaluationCalendar = .rosie,
        routeProfile: RouteFilterProfile = .default
    ) -> EvaluationResult {
        let interval = filter.interval(in: calendar)
        let selected = walks.filter { filter.includes($0, in: calendar) }
        let ordered = selected.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let rounds = ordered.map { walk -> EvaluationRound in
            let zone = TimeZone(identifier: walk.timeZoneID) ?? calendar.timeZone
            return EvaluationRound(
                id: walk.id,
                startedAt: walk.startedAt,
                endedAt: walk.endedAt,
                timeZoneID: walk.timeZoneID,
                bucket: TimeOfDayBucket.containing(walk.startedAt, in: zone) ?? .beforeNoon,
                // Nur abgeschlossene Runden haben eine feste Dauer; offene tragen nichts bei.
                duration: walk.endedAt.map { walk.totalDuration(at: $0) },
                motivation: walk.motivation,
                lameness: walk.lameness,
                estimatedDistanceMeters: walk.route?.estimatedDistanceMeters(profile: routeProfile)
            )
        }

        let count = rounds.count
        let durations = rounds.compactMap(\.duration)
        let distances = rounds.compactMap(\.estimatedDistanceMeters)
        let motivations = rounds.compactMap(\.motivation)
        let lamenesses = rounds.compactMap(\.lameness)

        let metrics = EvaluationMetrics(
            roundCount: count,
            totalDuration: durations.reduce(0, +),
            averageDuration: EvaluationAverage(values: durations, totalCount: count),
            totalEstimatedDistanceMeters: distances.reduce(0, +),
            averageEstimatedDistanceMeters: EvaluationAverage(values: distances, totalCount: count),
            motivation: EvaluationAverage(values: motivations, totalCount: count),
            lameness: EvaluationAverage(values: lamenesses, totalCount: count),
            scoredRounds: rounds.filter { $0.hasAnyScore() }.count
        )

        return EvaluationResult(
            filter: filter,
            interval: interval,
            rounds: rounds,
            metrics: metrics,
            motivationSeries: series(for: .motivation, rounds: rounds),
            lamenessSeries: series(for: .lameness, rounds: rounds)
        )
    }

    private static func series(for metric: ScoreMetric, rounds: [EvaluationRound]) -> ScoreSeries {
        var segments: [[ScorePoint]] = []
        var current: [ScorePoint] = []
        var scored = 0
        for round in rounds {
            guard let value = round.score(for: metric) else {
                // Fehlender Wert einer Runde unterbricht nur diese Messreihe.
                if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                continue
            }
            scored += 1
            current.append(
                ScorePoint(
                    id: ScorePointID(roundID: round.id, metric: metric),
                    roundID: round.id,
                    date: round.startedAt,
                    value: value,
                    bucket: round.bucket
                )
            )
        }
        if !current.isEmpty { segments.append(current) }
        return ScoreSeries(
            metric: metric,
            segments: segments,
            scoredRoundCount: scored,
            totalRoundCount: rounds.count
        )
    }
}
