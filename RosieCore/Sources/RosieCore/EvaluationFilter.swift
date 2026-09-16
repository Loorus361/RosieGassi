import Foundation

/// Gemeinsamer Auswertungszeitraum: Kalenderwoche oder Kalendermonat.
///
/// Ausdrücklich Kalendergrenzen, **keine** rollierenden Sieben- oder Dreißig-Tage-Intervalle.
public enum EvaluationPeriod: String, CaseIterable, Codable, Sendable {
    case day
    case week
    case month

    public var displayName: String {
        switch self {
        case .day: "Tag"
        case .week: "Kalenderwoche"
        case .month: "Kalendermonat"
        }
    }

    /// Kalenderkomponente für Bereichsbildung und Navigation.
    public var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// Explizite Kalender- und Zeitzonenregeln der Auswertung.
///
/// Gregorianischer Kalender, Montag als Wochenbeginn und mindestens vier Tage in der
/// ersten Woche (ISO 8601) in der im Projekt üblichen Zeitzone Europe/Berlin.
/// Wochen- und Monatsgrenzen sind dadurch echte Kalendergrenzen.
///
/// Hinweis: `DateInterval.contains` schließt in Foundation das Ende mit ein. Für die
/// Auswertung gilt konsequent das halboffene Intervall `start <= date < end`; dafür
/// `contains(_:in:)` dieses Typs verwenden, nicht `DateInterval.contains`.
public struct EvaluationCalendar: Equatable, Sendable {
    public var calendar: Calendar
    public var timeZone: TimeZone

    public static let rosieTimeZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    public init(
        timeZone: TimeZone = EvaluationCalendar.rosieTimeZone,
        firstWeekday: Int = 2,
        minimumDaysInFirstWeek: Int = 4
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek
        self.calendar = calendar
        self.timeZone = timeZone
    }

    /// Projektstandard: Europe/Berlin, Woche beginnt montags.
    public static let rosie = EvaluationCalendar()

    /// Kalenderbereich `[Start, Ende)`, der `date` enthält.
    public func interval(for period: EvaluationPeriod, containing date: Date) -> DateInterval {
        if let interval = calendar.dateInterval(of: period.component, for: date) { return interval }
        // Defensiver Rückfall; für den gregorianischen Kalender praktisch unerreichbar.
        let start = calendar.startOfDay(for: date)
        let fallbackDays: Int = switch period {
        case .day: 1
        case .week: 7
        case .month: 31
        }
        let end = calendar.date(byAdding: .day, value: fallbackDays, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// Verschiebt um ganze Kalenderwochen bzw. -monate.
    public func adding(_ period: EvaluationPeriod, value: Int, to date: Date) -> Date {
        calendar.date(byAdding: period.component, value: value, to: date) ?? date
    }

    /// Halboffene Zugehörigkeit: `start <= date < end`.
    public func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}

/// Tageszeit-Bereich der gemeinsamen Mehrfachauswahl, zugeordnet ausschließlich
/// nach lokaler Startzeit der Runde.
///
/// Grenzen: `vor 12` = `[00:00, 12:00)`, `12–18` = `[12:00, 18:00)`,
/// `ab 18` = `[18:00, 24:00)`. 12:00 gehört damit zu `12–18`, 18:00 zu `ab 18`.
public enum TimeOfDayBucket: String, CaseIterable, Codable, Hashable, Sendable {
    case beforeNoon = "vor12"
    case noonToEvening = "12bis18"
    case evening = "ab18"

    public var displayName: String {
        switch self {
        case .beforeNoon: "Vor 12"
        case .noonToEvening: "12–18"
        case .evening: "Ab 18"
        }
    }

    /// Enthält `date` in der angegebenen Zeitzone diesen Bereich?
    public func contains(_ date: Date, in timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let seconds = Double(parts.hour ?? 0) * 3_600
            + Double(parts.minute ?? 0) * 60
            + Double(parts.second ?? 0)
            + Double(parts.nanosecond ?? 0) / 1_000_000_000
        switch self {
        case .beforeNoon: return seconds < 12 * 3_600
        case .noonToEvening: return seconds >= 12 * 3_600 && seconds < 18 * 3_600
        case .evening: return seconds >= 18 * 3_600
        }
    }

    /// Bereich der lokalen Startzeit; `nil` nur bei ungültigen Komponenten.
    public static func containing(_ date: Date, in timeZone: TimeZone) -> TimeOfDayBucket? {
        allCases.first { $0.contains(date, in: timeZone) }
    }
}

/// Gemeinsamer Zustand aus Zeitraum und Tageszeit-Mehrfachauswahl.
///
/// Standard ist „alle“ Tageszeit-Bereiche. Die Auswahl kann nie leer werden:
/// der zuletzt verbleibende Bereich lässt sich nicht abwählen, und ein leerer
/// Ausgangssatz wird auf „alle“ normalisiert.
public struct EvaluationFilter: Equatable, Sendable {
    public private(set) var period: EvaluationPeriod
    public private(set) var anchor: Date
    public private(set) var buckets: Set<TimeOfDayBucket>

    public static let allBuckets = Set(TimeOfDayBucket.allCases)

    public init(
        period: EvaluationPeriod = .week,
        anchor: Date,
        buckets: Set<TimeOfDayBucket> = EvaluationFilter.allBuckets
    ) {
        self.period = period
        self.anchor = anchor
        self.buckets = buckets.isEmpty ? EvaluationFilter.allBuckets : buckets
    }

    /// Ausgewählte Bereiche in stabiler Anzeigeordnung.
    public var selectedBuckets: [TimeOfDayBucket] { TimeOfDayBucket.allCases.filter(buckets.contains) }

    public var isAllBucketsSelected: Bool { buckets.count == TimeOfDayBucket.allCases.count }

    /// Aktueller Kalenderbereich `[Start, Ende)`.
    public func interval(in calendar: EvaluationCalendar = .rosie) -> DateInterval {
        calendar.interval(for: period, containing: anchor)
    }

    /// Enthält „jetzt“ den aktuellen Zeitraum? Nützlich für die „Heute“-Aktion.
    public func isCurrentPeriod(now: Date = Date(), in calendar: EvaluationCalendar = .rosie) -> Bool {
        calendar.contains(now, in: interval(in: calendar))
    }

    public mutating func setPeriod(_ period: EvaluationPeriod) {
        self.period = period
    }

    public mutating func goPrevious(in calendar: EvaluationCalendar = .rosie) {
        anchor = calendar.adding(period, value: -1, to: anchor)
    }

    public mutating func goNext(in calendar: EvaluationCalendar = .rosie) {
        anchor = calendar.adding(period, value: 1, to: anchor)
    }

    public mutating func goToday(now: Date = Date()) {
        anchor = now
    }

    /// Nimmt einen Bereich auf oder entfernt ihn.
    ///
    /// Gibt `false` zurück, wenn das Entfernen den letzten Bereich entfernen würde;
    /// die Auswahl bleibt dann unverändert.
    @discardableResult
    public mutating func toggle(_ bucket: TimeOfDayBucket) -> Bool {
        if buckets.contains(bucket) {
            guard buckets.count > 1 else { return false }
            buckets.remove(bucket)
            return true
        }
        buckets.insert(bucket)
        return true
    }

    public mutating func selectAllBuckets() {
        buckets = EvaluationFilter.allBuckets
    }

    /// Zeitraum **und** Tageszeit-Zuordnung; Zuordnung nach lokaler Startzeit der Runde.
    public func includes(_ walk: Walk, in calendar: EvaluationCalendar = .rosie) -> Bool {
        let range = interval(in: calendar)
        guard calendar.contains(walk.startedAt, in: range) else { return false }
        let zone = TimeZone(identifier: walk.timeZoneID) ?? calendar.timeZone
        guard let bucket = TimeOfDayBucket.containing(walk.startedAt, in: zone) else { return false }
        return buckets.contains(bucket)
    }
}
