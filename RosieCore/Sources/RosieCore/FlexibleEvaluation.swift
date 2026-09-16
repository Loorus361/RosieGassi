import Foundation

/// A value that can be selected for an evaluation axis. Custom fields include
/// their revision so historical changes of labels, units, and scales remain visible.
public enum EvaluationMetric: Hashable, Codable, Sendable {
    case durationWithoutPauses
    case totalDuration
    case pauseDuration
    case estimatedDistanceMeters
    case motivation
    case lameness
    case elevator
    case hallway
    case courtyard
    case notes
    case temperatureCelsius
    case precipitationMm
    case windSpeedKmh
    case weatherCode
    case customField(id: UUID, revision: Int)

    public var displayName: String {
        switch self {
        case .durationWithoutPauses: "Dauer ohne Pausen"
        case .totalDuration: "Gesamtdauer"
        case .pauseDuration: "Pausenzeit"
        case .estimatedDistanceMeters: "Strecke"
        case .motivation: "Motivation"
        case .lameness: "Lahmheit"
        case .elevator: "Fahrstuhl"
        case .hallway: "Flur"
        case .courtyard: "Hof"
        case .notes: "Notizen"
        case .temperatureCelsius: "Temperatur"
        case .precipitationMm: "Niederschlag"
        case .windSpeedKmh: "Windgeschwindigkeit"
        case .weatherCode: "Wetterlage"
        case .customField: "Eigenes Feld"
        }
    }
}

public enum EvaluationMetricKind: String, Codable, Sendable {
    case numeric, boolean, category, text
}

/// Metadata shown by the picker. `definition` is retained for custom fields
/// because its revision-specific contract is part of the chart's meaning.
public struct EvaluationMetricDescriptor: Identifiable, Equatable, Sendable {
    public let metric: EvaluationMetric
    public let name: String
    public let kind: EvaluationMetricKind
    public let unit: String?
    public let scale: ClosedRange<Double>?
    public let definition: CustomFieldDefinition?

    public var id: EvaluationMetric { metric }

    public init(metric: EvaluationMetric, name: String, kind: EvaluationMetricKind,
                unit: String? = nil, scale: ClosedRange<Double>? = nil,
                definition: CustomFieldDefinition? = nil) {
        self.metric = metric; self.name = name; self.kind = kind; self.unit = unit
        self.scale = scale; self.definition = definition
    }
}

public enum EvaluationAggregation: String, CaseIterable, Codable, Sendable {
    case round
    case day

    public var displayName: String { self == .round ? "Einzelne Runden" : "Tagesmittel" }
}

/// One plotted or annotated observation. For `.day`, `sampleCount` and
/// `totalCount` make the denominator visible; missing values never become zero.
public struct FlexibleEvaluationPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let roundID: UUID?
    public let bucket: TimeOfDayBucket?
    public let numericValue: Double?
    public let booleanValue: Bool?
    public let textValue: String?
    public let sampleCount: Int
    public let totalCount: Int
    /// Increments over missing observations and allows a renderer to break a line.
    public let segmentIndex: Int

    public init(id: String, date: Date, roundID: UUID? = nil, bucket: TimeOfDayBucket? = nil,
                numericValue: Double? = nil, booleanValue: Bool? = nil, textValue: String? = nil,
                sampleCount: Int = 1, totalCount: Int = 1, segmentIndex: Int = 0) {
        self.id = id; self.date = date; self.roundID = roundID; self.bucket = bucket
        self.numericValue = numericValue; self.booleanValue = booleanValue; self.textValue = textValue
        self.sampleCount = sampleCount; self.totalCount = totalCount
        self.segmentIndex = segmentIndex
    }
}

public struct FlexibleEvaluationSeries: Identifiable, Equatable, Sendable {
    public let id: EvaluationMetric
    public let descriptor: EvaluationMetricDescriptor
    public let points: [FlexibleEvaluationPoint]
    public let totalRoundCount: Int
    public let sampleCount: Int

    public var isEmpty: Bool { sampleCount == 0 }

    public init(descriptor: EvaluationMetricDescriptor, points: [FlexibleEvaluationPoint],
                totalRoundCount: Int, sampleCount: Int) {
        id = descriptor.metric; self.descriptor = descriptor; self.points = points
        self.totalRoundCount = totalRoundCount; self.sampleCount = sampleCount
    }
}

public struct FlexibleEvaluationResult: Equatable, Sendable {
    public let filter: EvaluationFilter
    public let interval: DateInterval
    public let rounds: [EvaluationRound]
    public let descriptors: [EvaluationMetricDescriptor]
    public let series: [FlexibleEvaluationSeries]

    public func series(for metric: EvaluationMetric) -> FlexibleEvaluationSeries? {
        series.first { $0.id == metric }
    }
}

public enum FlexibleWalkEvaluation {
    public static func availableMetrics(in walks: [Walk], customFieldCatalog: CustomFieldCatalog? = nil,
                                        routeProfile: RouteFilterProfile = .default) -> [EvaluationMetricDescriptor] {
        _ = routeProfile
        var result = builtInDescriptors
        var definitions: [EvaluationMetric: CustomFieldDefinition] = [:]
        for entry in customFieldCatalog?.entries ?? [] {
            for definition in entry.revisions { definitions[.customField(id: definition.id, revision: definition.revision)] = definition }
        }
        for walk in walks { for observation in walk.customFields { definitions[.customField(id: observation.definition.id, revision: observation.definition.revision)] = observation.definition } }
        result += definitions.values.sorted { ($0.name, $0.revision) < ($1.name, $1.revision) }.map { definition in
            let metric = EvaluationMetric.customField(id: definition.id, revision: definition.revision)
            let scale: ClosedRange<Double>? = if let min = definition.scaleMin, let max = definition.scaleMax { min...max } else { nil }
            let kind: EvaluationMetricKind = switch definition.kind { case .number, .scale: .numeric; case .boolean: .boolean; case .graded: .category }
            return EvaluationMetricDescriptor(metric: metric, name: definition.name, kind: kind, unit: definition.unit, scale: scale, definition: definition)
        }
        return result
    }

    public static func evaluate(_ walks: [Walk], filter: EvaluationFilter,
                                metrics selectedMetrics: [EvaluationMetric],
                                aggregation: EvaluationAggregation = .round,
                                calendar: EvaluationCalendar = .rosie,
                                customFieldCatalog: CustomFieldCatalog? = nil,
                                routeProfile: RouteFilterProfile = .default) -> FlexibleEvaluationResult {
        let base = WalkEvaluation.evaluate(walks, filter: filter, calendar: calendar, routeProfile: routeProfile)
        let descriptors = availableMetrics(in: baseRoundsWalks(walks, filter: filter, calendar: calendar), customFieldCatalog: customFieldCatalog, routeProfile: routeProfile)
        let lookup = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.metric, $0) })
        let series = selectedMetrics.compactMap { metric -> FlexibleEvaluationSeries? in
            guard let descriptor = lookup[metric] else { return nil }
            let points = makePoints(metric: metric, descriptor: descriptor, walks: walks.filter { filter.includes($0, in: calendar) }.sorted { $0.startedAt < $1.startedAt }, aggregation: aggregation, calendar: calendar, routeProfile: routeProfile)
            let samples = points.reduce(0) { $0 + $1.sampleCount }
            return FlexibleEvaluationSeries(descriptor: descriptor, points: points, totalRoundCount: base.rounds.count, sampleCount: samples)
        }
        return FlexibleEvaluationResult(filter: filter, interval: base.interval, rounds: base.rounds, descriptors: descriptors, series: series)
    }

    private static let builtInDescriptors: [EvaluationMetricDescriptor] = [
        .init(metric: .durationWithoutPauses, name: "Dauer ohne Pausen", kind: .numeric, unit: "s"),
        .init(metric: .totalDuration, name: "Gesamtdauer", kind: .numeric, unit: "s"),
        .init(metric: .pauseDuration, name: "Pausenzeit", kind: .numeric, unit: "s"),
        .init(metric: .estimatedDistanceMeters, name: "Strecke", kind: .numeric, unit: "m"),
        .init(metric: .motivation, name: "Motivation", kind: .numeric, scale: 1...7),
        .init(metric: .lameness, name: "Lahmheit", kind: .numeric, scale: 1...7),
        .init(metric: .elevator, name: "Fahrstuhl", kind: .category),
        .init(metric: .hallway, name: "Flur", kind: .category),
        .init(metric: .courtyard, name: "Hof", kind: .category),
        .init(metric: .notes, name: "Notizen", kind: .text),
        .init(metric: .temperatureCelsius, name: "Temperatur", kind: .numeric, unit: "°C"),
        .init(metric: .precipitationMm, name: "Niederschlag", kind: .numeric, unit: "mm"),
        .init(metric: .windSpeedKmh, name: "Windgeschwindigkeit", kind: .numeric, unit: "km/h"),
        .init(metric: .weatherCode, name: "Wetterlage", kind: .category)
    ]

    private static func baseRoundsWalks(_ walks: [Walk], filter: EvaluationFilter, calendar: EvaluationCalendar) -> [Walk] { walks.filter { filter.includes($0, in: calendar) } }

    private static func makePoints(metric: EvaluationMetric, descriptor: EvaluationMetricDescriptor, walks: [Walk], aggregation: EvaluationAggregation, calendar: EvaluationCalendar, routeProfile: RouteFilterProfile) -> [FlexibleEvaluationPoint] {
        var segment = 0
        let raw = walks.map { walk -> FlexibleEvaluationPoint in
            let value = value(for: metric, walk: walk, routeProfile: routeProfile)
            let point = FlexibleEvaluationPoint(id: walk.id.uuidString, date: walk.startedAt, roundID: walk.id, bucket: TimeOfDayBucket.containing(walk.startedAt, in: TimeZone(identifier: walk.timeZoneID) ?? calendar.timeZone), numericValue: value.numeric, booleanValue: value.boolean, textValue: value.text, sampleCount: (value.numeric != nil || value.boolean != nil || value.text != nil) ? 1 : 0, segmentIndex: segment)
            if value.numeric == nil && value.boolean == nil && value.text == nil { segment += 1 }
            return point
        }
        guard aggregation == .day else { return raw }
        let grouped = Dictionary(grouping: raw) { calendar.calendar.startOfDay(for: $0.date) }
        var previousDay: Date?
        var daySegment = 0
        return grouped.keys.sorted().map { day in
            if let previousDay,
               let nextCalendarDay = calendar.calendar.date(byAdding: .day, value: 1, to: previousDay),
               day > nextCalendarDay {
                daySegment += 1
            }
            let values = grouped[day] ?? []
            let total = values.count
            if descriptor.kind == .numeric {
                let nums = values.compactMap(\.numericValue)
                let point = FlexibleEvaluationPoint(id: day.description, date: day, numericValue: nums.isEmpty ? nil : nums.reduce(0,+) / Double(nums.count), sampleCount: nums.count, totalCount: total, segmentIndex: daySegment)
                if nums.isEmpty { daySegment += 1 }
                previousDay = day
                return point
            }
            if descriptor.kind == .boolean {
                let bools = values.compactMap(\.booleanValue)
                let point = FlexibleEvaluationPoint(id: day.description, date: day, numericValue: bools.isEmpty ? nil : Double(bools.filter { $0 }.count) / Double(bools.count), sampleCount: bools.count, totalCount: total, segmentIndex: daySegment)
                if bools.isEmpty { daySegment += 1 }
                previousDay = day
                return point
            }
            let texts = values.compactMap(\.textValue)
            let point = FlexibleEvaluationPoint(id: day.description, date: day, textValue: texts.isEmpty ? nil : texts.joined(separator: " · "), sampleCount: texts.count, totalCount: total, segmentIndex: daySegment)
            if texts.isEmpty { daySegment += 1 }
            previousDay = day
            return point
        }
    }

    private static func value(for metric: EvaluationMetric, walk: Walk, routeProfile: RouteFilterProfile) -> (numeric: Double?, boolean: Bool?, text: String?) {
        switch metric {
        case .durationWithoutPauses: guard let end = walk.endedAt else { return (nil,nil,nil) }; return (max(0, walk.totalDuration(at: end) - walk.pauseDuration(at: end)),nil,nil)
        case .totalDuration: guard let end = walk.endedAt else { return (nil,nil,nil) }; return (walk.totalDuration(at: end),nil,nil)
        case .pauseDuration: guard let end = walk.endedAt else { return (nil,nil,nil) }; return (walk.pauseDuration(at: end),nil,nil)
        case .estimatedDistanceMeters: return (walk.route?.estimatedDistanceMeters(profile: routeProfile),nil,nil)
        case .motivation: return (walk.motivation,nil,nil)
        case .lameness: return (walk.lameness,nil,nil)
        case .elevator: return (nil,nil,walk.elevator?.displayName)
        case .hallway: return (nil,nil,walk.hallway?.displayName)
        case .courtyard: return (nil,nil,walk.courtyard?.displayName)
        case .notes: return (nil,nil,walk.notes.isEmpty ? nil : walk.notes)
        case .temperatureCelsius: return (walk.weather?.temperatureCelsius,nil,nil)
        case .precipitationMm: return (walk.weather?.precipitationMm,nil,nil)
        case .windSpeedKmh: return (walk.weather?.windSpeedKmh,nil,nil)
        case .weatherCode: return (nil,nil,walk.weather?.weatherCode.map { WeatherCode.germanLabel($0) })
        case .customField(let id, let revision):
            guard let observation = walk.customFields.first(where: { $0.definition.id == id && $0.definition.revision == revision }) else { return (nil,nil,nil) }
            switch observation.value { case .missing: return (nil,nil,nil); case .scale(let v), .number(let v): return (v,nil,nil); case .boolean(let v): return (nil,v,nil); case .choice(let id): return (nil,nil,observation.definition.option(id)?.label) }
        }
    }
}
