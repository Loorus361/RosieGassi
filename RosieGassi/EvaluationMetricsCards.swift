import SwiftUI
import RosieCore

/// Bereich „Kennzahlen“: auswählbare und anordenbare Karten.
///
/// Schnittstelle zum Verlauf-Screen: genau ein Parameter (`metrics`). Der Bereich
/// rechnet nichts nach, hat keine eigenen Filter und erhält exakt denselben
/// gefilterten Bestand wie das Verlaufsdiagramm. Auswahl und Reihenfolge regelt
/// ausschließlich `EvaluationMetricsPreferences` (lokal gemerkt).
///
/// Fehlende Werte bleiben „nicht angegeben“; reale Nullwerte bleiben von fehlenden
/// Werten unterscheidbar (z. B. Gesamtstrecke 0 m nur bei tatsächlich vorhandener
/// Messung, sonst „nicht angegeben“). Keine medizinischen Aussagen.
struct EvaluationMetricsSection: View {
    let metrics: EvaluationMetrics
    @State private var preferences = EvaluationMetricsPreferences()
    @State private var isEditing = false

    init(metrics: EvaluationMetrics) {
        self.metrics = metrics
    }

    var body: some View {
        RuheCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                if metrics.roundCount == 0 {
                    Text("Keine Runden im gewählten Zeitraum, daher keine Kennzahlen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("metrics.empty")
                } else {
                    grid
                    footnote
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EvaluationMetricsEditor(preferences: $preferences)
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Kennzahlen")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("metrics.title")
            Spacer(minLength: 8)
            Button {
                isEditing = true
            } label: {
                Label("Anpassen", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("metrics.edit")
            .accessibilityHint("Auswahl und Reihenfolge der Kennzahlen ändern.")
        }
    }

    // MARK: - Karten

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(preferences.visibleCards) { card in
                EvaluationMetricTile(card: card, content: content(for: card))
            }
        }
    }

    private var footnote: some View {
        Text("Mittelwerte stammen nur aus vorhandenen Werten; fehlende bleiben leer und werden nicht als 0 dargestellt. Skala 1–7, Motivation \(ScoreMetric.motivation.scaleNote), Lahmheit \(ScoreMetric.lameness.scaleNote). Strecken sind geschätzt. Auswahl und Reihenfolge merkt sich die App auf diesem iPhone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("metrics.footnote")
    }

    private static let missingValueText = "nicht angegeben"

    private func content(for card: EvaluationMetricCard) -> EvaluationMetricTileContent {
        switch card {
        case .roundCount:
            return EvaluationMetricTileContent(
                value: "\(metrics.roundCount)",
                detail: metrics.roundCount == 1 ? "Runde im Zeitraum" : "Runden im Zeitraum",
                isPlaceholder: false
            )

        case .totalDuration:
            return durationContent(
                value: metrics.durationCoverage.scored == 0 ? nil : metrics.totalDuration,
                coverage: metrics.durationCoverage
            )

        case .averageDuration:
            return durationContent(value: metrics.averageDuration.value, coverage: metrics.durationCoverage)

        case .totalEstimatedDistance:
            return distanceContent(
                value: metrics.distanceCoverage.scored == 0 ? nil : metrics.totalEstimatedDistanceMeters,
                coverage: metrics.distanceCoverage
            )

        case .averageEstimatedDistance:
            return distanceContent(
                value: metrics.averageEstimatedDistanceMeters.value,
                coverage: metrics.distanceCoverage
            )

        case .motivation:
            return scoreContent(metrics.motivation, metric: .motivation)

        case .lameness:
            return scoreContent(metrics.lameness, metric: .lameness)

        case .dataCoverage:
            return EvaluationMetricTileContent(
                value: "\(metrics.dataCoverage.scored) von \(metrics.dataCoverage.total)",
                detail: "Runden mit mindestens einer Bewertung",
                isPlaceholder: false
            )
        }
    }

    /// Dauer nur aus abgeschlossenen Runden; offene Runden tragen nichts bei.
    private func durationContent(value: TimeInterval?, coverage: EvaluationCoverage) -> EvaluationMetricTileContent {
        guard let value else {
            return EvaluationMetricTileContent(
                value: Self.missingValueText,
                detail: "0 von \(coverage.total) Runden mit abgeschlossener Dauer",
                isPlaceholder: true
            )
        }
        return EvaluationMetricTileContent(
            value: EvaluationMetricsFormat.duration(value),
            detail: "aus \(coverage.scored) von \(coverage.total) Runden",
            isPlaceholder: false
        )
    }

    private func distanceContent(value: Double?, coverage: EvaluationCoverage) -> EvaluationMetricTileContent {
        guard let value else {
            return EvaluationMetricTileContent(
                value: Self.missingValueText,
                detail: "geschätzt · 0 von \(coverage.total) Runden mit GPS-Strecke",
                isPlaceholder: true
            )
        }
        return EvaluationMetricTileContent(
            value: EvaluationMetricsFormat.distance(value),
            detail: "geschätzt · aus \(coverage.scored) von \(coverage.total) Runden",
            isPlaceholder: false
        )
    }

    /// Mittelwert nur aus bewerteten Runden, getrennte Datenbasis je Messreihe.
    private func scoreContent(_ average: EvaluationAverage, metric: ScoreMetric) -> EvaluationMetricTileContent {
        let detail = "\(average.coverageText) · Skala 1–7, \(metric.scaleNote)"
        guard let value = average.value else {
            return EvaluationMetricTileContent(value: Self.missingValueText, detail: detail, isPlaceholder: true)
        }
        return EvaluationMetricTileContent(
            value: EvaluationMetricsFormat.score(value),
            detail: detail,
            isPlaceholder: false
        )
    }
}

/// Inhalt einer Kennzahlenkarte: Wert, erklärende Datenbasis und Leerzustand.
private struct EvaluationMetricTileContent {
    let value: String
    let detail: String?
    let isPlaceholder: Bool

    /// Gesprochene Fassung der Datenbasis (VoiceOver liest „·“ nicht sinnvoll).
    var spokenDetail: String {
        (detail ?? "").replacingOccurrences(of: " · ", with: ", ")
    }
}

/// Eine einzelne Kennzahlenkarte. Ziffern stehen in einer festen Breite, damit die
/// Werte beim Wechsel des Zeitraums nicht springen.
private struct EvaluationMetricTile: View {
    let card: EvaluationMetricCard
    let content: EvaluationMetricTileContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: card.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(card.symbolColor)
                    .accessibilityHidden(true)
                Text(card.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(content.value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(content.isPlaceholder ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = content.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.spokenTitle): \(content.value)")
        .accessibilityValue(content.spokenDetail)
        .accessibilityIdentifier("metrics.card.\(card.rawValue)")
    }
}

private extension EvaluationMetricCard {
    /// Messreihen nutzen dieselben Farben wie das Verlaufsdiagramm.
    var symbolColor: Color {
        switch self {
        case .motivation: EvaluationStyle.color(for: .motivation)
        case .lameness: EvaluationStyle.color(for: .lameness)
        default: .secondary
        }
    }
}

/// Editor für Auswahl und Reihenfolge. „Hoch“/„Runter“ statt Ziehen, damit die
/// Bedienung mit VoiceOver, großer Schrift und ohne Feingefühl funktioniert.
struct EvaluationMetricsEditor: View {
    @Binding var preferences: EvaluationMetricsPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(preferences.order) { card in
                        row(card)
                    }
                } footer: {
                    Text("Auswahl und Reihenfolge gelten nur für die Anzeige und werden auf diesem iPhone gemerkt. Mindestens eine Kennzahl bleibt sichtbar.")
                }
            }
            .navigationTitle("Kennzahlen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Standard") { preferences.reset() }
                        .disabled(preferences.isDefault)
                        .accessibilityIdentifier("metrics.edit.reset")
                        .accessibilityHint("Auswahl und Reihenfolge zurücksetzen.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("metrics.edit.done")
                }
            }
        }
    }

    private func row(_ card: EvaluationMetricCard) -> some View {
        let isSelected = preferences.isSelected(card)
        let isOnlySelected = isSelected && preferences.selectedCount == 1
        return HStack(spacing: 4) {
            Button {
                preferences.toggle(card)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                        Text(isSelected ? "Sichtbar" : "Ausgeblendet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("metrics.edit.toggle.\(card.rawValue)")
            .accessibilityLabel("\(card.spokenTitle), \(isSelected ? "sichtbar" : "ausgeblendet")")
            .accessibilityHint(isOnlySelected
                               ? "Mindestens eine Kennzahl bleibt sichtbar."
                               : "Aktivieren oder deaktivieren.")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            Button {
                preferences.moveUp(card)
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!preferences.canMoveUp(card))
            .accessibilityIdentifier("metrics.edit.up.\(card.rawValue)")
            .accessibilityLabel("\(card.title) nach oben")

            Button {
                preferences.moveDown(card)
            } label: {
                Image(systemName: "arrow.down")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!preferences.canMoveDown(card))
            .accessibilityIdentifier("metrics.edit.down.\(card.rawValue)")
            .accessibilityLabel("\(card.title) nach unten")
        }
    }
}

/// Zahlenformate der Kennzahlenkarten.
enum EvaluationMetricsFormat {
    static func duration(_ interval: TimeInterval) -> String { durationText(interval) }

    static func distance(_ meters: Double) -> String {
        if meters >= 1_000 {
            return "\(kilometerFormatter.string(from: (meters / 1_000) as NSNumber) ?? "\(meters / 1_000)") km"
        }
        return "\(Int(meters.rounded())) m"
    }

    /// Scores behalten Halbwerte unverändert; kein Runden auf halbe Schritte.
    static func score(_ value: Double) -> String {
        scoreFormatter.string(from: value as NSNumber) ?? "\(value)"
    }

    private static let kilometerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let scoreFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
