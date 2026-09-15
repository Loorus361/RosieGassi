import Foundation

/// Auswählbare Kennzahlenkarte des Bereichs „Kennzahlen“.
///
/// Die Reihenfolge in `allCases` ist die Standardreihenfolge der Anzeige. `rawValue`
/// ist der stabile Schlüssel der lokalen Persistenz und darf sich nicht ändern.
enum EvaluationMetricCard: String, CaseIterable, Identifiable, Sendable {
    case roundCount
    case totalDuration
    case averageDuration
    case totalEstimatedDistance
    case averageEstimatedDistance
    case motivation
    case lameness
    case dataCoverage

    var id: String { rawValue }

    /// Titel in Karte und Editor.
    var title: String {
        switch self {
        case .roundCount: "Rundenzahl"
        case .totalDuration: "Gesamtdauer"
        case .averageDuration: "Ø Dauer"
        case .totalEstimatedDistance: "Gesamtstrecke"
        case .averageEstimatedDistance: "Ø Strecke"
        case .motivation: "Ø Motivation"
        case .lameness: "Ø Lahmheit"
        case .dataCoverage: "Datenabdeckung"
        }
    }

    /// Sprechender Titel für VoiceOver („Ø“ wird sonst unverständlich vorgelesen).
    var spokenTitle: String {
        switch self {
        case .roundCount: "Rundenzahl"
        case .totalDuration: "Gesamtdauer"
        case .averageDuration: "Durchschnittsdauer"
        case .totalEstimatedDistance: "Gesamtstrecke, geschätzt"
        case .averageEstimatedDistance: "Durchschnittsstrecke, geschätzt"
        case .motivation: "Durchschnitt Motivation"
        case .lameness: "Durchschnitt Lahmheit"
        case .dataCoverage: "Datenabdeckung"
        }
    }

    /// Strecken stammen aus der abgeleiteten GPS-Geometrie und sind geschätzt.
    var isEstimated: Bool {
        switch self {
        case .totalEstimatedDistance, .averageEstimatedDistance: true
        default: false
        }
    }

    var symbolName: String {
        switch self {
        case .roundCount: "figure.walk"
        case .totalDuration: "timer"
        case .averageDuration: "clock"
        case .totalEstimatedDistance: "ruler"
        case .averageEstimatedDistance: "map"
        case .motivation: "circle.fill"
        case .lameness: "square.fill"
        case .dataCoverage: "checklist"
        }
    }
}

/// Lokale Ablage für Auswahl und Reihenfolge der Kennzahlenkarten.
///
/// Standard ist die App-Ablage. Ein UI-Testlauf mit `--uitest-store <UUID>` erhält
/// eine eigene Suite, damit weder echte Rosie-Daten noch echte Einstellungen
/// berührt werden. Es werden ausschließlich Darstellungspräferenzen gespeichert.
enum EvaluationMetricsPreferencesStore {
    /// Eigener Schlüssel; kollidiert nicht mit anderen Einstellungen der App.
    static let defaultKey = "evaluation.metrics.cards"

    static func defaults() -> UserDefaults {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--uitest-store"),
           arguments.indices.contains(index + 1),
           let id = UUID(uuidString: arguments[index + 1]),
           let suite = UserDefaults(suiteName: "RosieMetrics.UITest." + id.uuidString) {
            return suite
        }
        #endif
        return .standard
    }
}

/// Auswahl und Reihenfolge der Kennzahlenkarten als reiner Darstellungszustand.
///
/// Diese Präferenz hält **keine** Messwerte und **keine** Filter: der Bereich
/// „Kennzahlen“ bekommt seinen Datenbestand ausschließlich als `EvaluationMetrics`
/// übergeben. `order` enthält immer alle Karten (auch ausgeblendete, damit deren
/// Position beim Wiederauswählen stabil bleibt); `visibleCards` ist die daraus
/// gefilterte Anzeige.
///
/// Die Auswahl kann nie leer werden: die letzte sichtbare Karte lässt sich nicht
/// ausblenden (`toggle` liefert dann `false`), und ein leerer oder unbrauchbarer
/// gespeicherter Zustand fällt auf „alle Karten“ zurück.
struct EvaluationMetricsPreferences {
    /// Gespeicherte Rohform; bewusst tolerant gegenüber unbekannten Einträgen.
    private struct Stored: Codable, Equatable {
        var order: [String]
        var selection: [String]
    }

    let defaults: UserDefaults
    let key: String

    /// Alle Karten in Anzeigereihenfolge.
    private(set) var order: [EvaluationMetricCard]
    /// Die tatsächlich angezeigten Karten.
    private(set) var selected: Set<EvaluationMetricCard>

    init(
        defaults: UserDefaults = EvaluationMetricsPreferencesStore.defaults(),
        key: String = EvaluationMetricsPreferencesStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key

        let stored = Self.load(from: defaults, key: key)
        let storedOrder = (stored?.order ?? []).compactMap(EvaluationMetricCard.init(rawValue:))
        let storedSelection = Set((stored?.selection ?? []).compactMap(EvaluationMetricCard.init(rawValue:)))
        let known = Set(storedOrder)

        var order: [EvaluationMetricCard] = []
        for card in storedOrder where !order.contains(card) { order.append(card) }
        for card in EvaluationMetricCard.allCases where !order.contains(card) { order.append(card) }
        self.order = order

        if stored == nil {
            // Kein gespeicherter Zustand: Standard sind alle Karten.
            self.selected = Set(EvaluationMetricCard.allCases)
        } else {
            // Karten, die es beim Speichern noch nicht gab, gelten als neu und sind sichtbar.
            var selection = storedSelection.union(EvaluationMetricCard.allCases.filter { !known.contains($0) })
            if selection.isEmpty { selection = Set(EvaluationMetricCard.allCases) }
            self.selected = selection
        }
    }

    // MARK: - Anzeige

    /// Sichtbare Karten in der gemerkten Reihenfolge.
    var visibleCards: [EvaluationMetricCard] { order.filter(selected.contains) }

    var selectedCount: Int { selected.count }

    var isDefault: Bool {
        order == EvaluationMetricCard.allCases && selected.count == EvaluationMetricCard.allCases.count
    }

    func isSelected(_ card: EvaluationMetricCard) -> Bool { selected.contains(card) }

    // MARK: - Änderungen (werden sofort lokal gemerkt)

    /// Blendet eine Karte ein oder aus.
    ///
    /// Gibt `false` zurück, wenn das Ausblenden die letzte sichtbare Karte entfernen
    /// würde; die Auswahl bleibt dann unverändert.
    @discardableResult
    mutating func toggle(_ card: EvaluationMetricCard) -> Bool {
        if selected.contains(card) {
            guard selected.count > 1 else { return false }
            selected.remove(card)
        } else {
            selected.insert(card)
        }
        save()
        return true
    }

    func canMoveUp(_ card: EvaluationMetricCard) -> Bool {
        (order.firstIndex(of: card)).map { $0 > 0 } ?? false
    }

    func canMoveDown(_ card: EvaluationMetricCard) -> Bool {
        (order.firstIndex(of: card)).map { $0 < order.count - 1 } ?? false
    }

    @discardableResult
    mutating func moveUp(_ card: EvaluationMetricCard) -> Bool {
        guard let index = order.firstIndex(of: card), index > 0 else { return false }
        order.swapAt(index, index - 1)
        save()
        return true
    }

    @discardableResult
    mutating func moveDown(_ card: EvaluationMetricCard) -> Bool {
        guard let index = order.firstIndex(of: card), index < order.count - 1 else { return false }
        order.swapAt(index, index + 1)
        save()
        return true
    }

    /// Setzt Standardauswahl und Standardreihenfolge zurück.
    mutating func reset() {
        order = EvaluationMetricCard.allCases
        selected = Set(EvaluationMetricCard.allCases)
        save()
    }

    // MARK: - Persistenz

    private func save() {
        let stored = Stored(
            order: order.map(\.rawValue),
            // Stabile Reihenfolge in der Ablage, unabhängig von der Set-Reihenfolge.
            selection: EvaluationMetricCard.allCases.filter(selected.contains).map(\.rawValue)
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> Stored? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }
}
