import SwiftUI
import Charts
import RosieCore

/// Darstellung der beiden Messreihen: Unterscheidung durch **Symbol und Farbe**,
/// nicht nur durch Farbe. Die Richtung der Skala ist Teil der Legende.
enum EvaluationStyle {
    static func color(for metric: ScoreMetric) -> Color {
        switch metric {
        case .motivation: .teal
        case .lameness: .orange
        }
    }

    /// SF-Symbol der Legende und der Punkt-Details.
    static func symbolName(for metric: ScoreMetric) -> String {
        switch metric {
        case .motivation: "circle.fill"
        case .lameness: "square.fill"
        }
    }

    /// Passende Diagrammform zum SF-Symbol.
    static func chartSymbol(for metric: ScoreMetric) -> BasicChartSymbolShape {
        switch metric {
        case .motivation: .circle
        case .lameness: .square
        }
    }
}

/// Verlaufsdiagramm mit fester gemeinsamer Skala 1–7 und einem Punkt je Runde.
///
/// Fehlende Werte erzeugen keinen Punkt. Die Linien folgen den bereits
/// segmentierten Reihen aus `ScoreSeries.segments`, damit eine Lücke nur die
/// eigene Messreihe unterbricht und nicht als geschlossener Verlauf erscheint.
struct EvaluationChart: View {
    let result: EvaluationResult
    @Binding var selection: Date?
    let selectedRoundID: UUID?

    var body: some View {
        Chart {
            ForEach(ScoreMetric.allCases, id: \.self) { metric in
                marks(for: metric)
            }
            if let selectedRoundID, let round = result.round(selectedRoundID) {
                RuleMark(x: .value("Ausgewählte Runde", round.startedAt))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: ScoreMetric.motivation.scale)
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5, 6, 7]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartXSelection(value: $selection)
        .accessibilityLabel("Verlaufsdiagramm Motivation und Lahmheit")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Tippe auf einen Punkt, um Datum, Werte, Dauer und geschätzte Strecke zu sehen.")
    }

    @ChartContentBuilder
    private func marks(for metric: ScoreMetric) -> some ChartContent {
        let series = result.series(for: metric)
        ForEach(Array(series.segments.enumerated()), id: \.offset) { index, segment in
            ForEach(segment) { point in
                LineMark(
                    x: .value("Zeitpunkt", point.date),
                    y: .value(metric.displayName, point.value),
                    // Je Abschnitt eine eigene Linie: fehlende Zwischenwerte reißen die Linie auf.
                    series: .value("Abschnitt", "\(metric.rawValue)-\(index)")
                )
                .foregroundStyle(EvaluationStyle.color(for: metric))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Zeitpunkt", point.date),
                    y: .value(metric.displayName, point.value)
                )
                .foregroundStyle(EvaluationStyle.color(for: metric))
                .symbol(EvaluationStyle.chartSymbol(for: metric))
                .symbolSize(point.roundID == selectedRoundID ? 160 : 70)
            }
        }
    }

    private var accessibilityValue: String {
        let motivation = result.motivationSeries.coverage
        let lameness = result.lamenessSeries.coverage
        return "Feste Skala 1 bis 7. Motivation: \(motivation.text). Lahmheit: \(lameness.text)."
    }
}

/// Legende mit Symbol, Farbe und ausdrücklicher Skalenrichtung.
struct EvaluationLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(for: .motivation)
            legendRow(for: .lameness)
            Text("Gemeinsame Skala 1 (niedrig) bis 7 (hoch). Ein Punkt je Runde, keine Tagesmittel.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func legendRow(for metric: ScoreMetric) -> some View {
        HStack(spacing: 8) {
            Image(systemName: EvaluationStyle.symbolName(for: metric))
                .foregroundStyle(EvaluationStyle.color(for: metric))
                .accessibilityHidden(true)
            Text("\(metric.displayName): \(metric.scaleNote)")
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.displayName): \(metric.scaleNote)")
        .accessibilityIdentifier("evaluation.legend.\(metric.rawValue)")
    }
}

/// Details einer im Diagramm oder in der Liste ausgewählten Runde.
///
/// Fehlende Angaben werden ausdrücklich neutral als „nicht angegeben“ ausgewiesen.
struct EvaluationPointDetail: View {
    let round: EvaluationRound

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(dateLabel, systemImage: "calendar")
                .font(.subheadline)
                .accessibilityIdentifier("evaluation.detail.date")

            ForEach(ScoreMetric.allCases, id: \.self) { metric in
                HStack(spacing: 8) {
                    Image(systemName: EvaluationStyle.symbolName(for: metric))
                        .foregroundStyle(EvaluationStyle.color(for: metric))
                        .accessibilityHidden(true)
                    Text("\(metric.displayName):")
                    Text(scoreLabel(for: metric))
                        .fontWeight(.semibold)
                    Text("von 7 · \(metric.scaleNote)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(metric.displayName): \(scoreLabel(for: metric)) von 7, \(metric.scaleNote)")
                .accessibilityIdentifier("evaluation.detail.\(metric.rawValue)")
            }

            Label(durationLabel, systemImage: "timer")
                .font(.subheadline)
                .accessibilityIdentifier("evaluation.detail.duration")
            Label(distanceLabel, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.subheadline)
                .accessibilityIdentifier("evaluation.detail.distance")
            Label("Tageszeit: \(round.bucket.displayName)", systemImage: "clock")
                .font(.subheadline)
                .accessibilityIdentifier("evaluation.detail.bucket")

            NavigationLink(value: round.id) {
                Label("Runde öffnen", systemImage: "arrow.forward.circle")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("evaluation.openRound")
        }
    }

    private var dateLabel: String {
        Self.dateFormatter(timeZoneID: round.timeZoneID).string(from: round.startedAt)
    }

    private func scoreLabel(for metric: ScoreMetric) -> String {
        guard let value = round.score(for: metric) else { return "nicht angegeben" }
        return Self.numberFormatter.string(from: value as NSNumber) ?? "\(value)"
    }

    private var durationLabel: String {
        if round.isOpen { return "Dauer: Runde läuft noch" }
        guard let duration = round.duration else { return "Dauer: nicht angegeben" }
        return "Dauer: \(durationText(duration))"
    }

    private var distanceLabel: String {
        guard let meters = round.estimatedDistanceMeters else {
            return "Geschätzte Strecke: nicht angegeben"
        }
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            let text = Self.decimalFormatter.string(from: kilometers as NSNumber) ?? "\(kilometers)"
            return "Geschätzte Strecke: \(text) km"
        }
        return "Geschätzte Strecke: \(Int(meters.rounded())) m"
    }

    private static func dateFormatter(timeZoneID: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? EvaluationCalendar.rosieTimeZone
        formatter.dateFormat = "EEEE, d. MMMM yyyy 'um' HH:mm"
        return formatter
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

extension EvaluationResult {
    /// Nächstgelegene Runde mit mindestens einem Score zu einem Diagramm-Tipp.
    ///
    /// Nur bewertete Runden sind auswählbar, weil nur sie einen Diagrammpunkt besitzen.
    func nearestScoredRound(to date: Date) -> EvaluationRound? {
        rounds
            .filter { $0.hasAnyScore() }
            .min { abs($0.startedAt.timeIntervalSince(date)) < abs($1.startedAt.timeIntervalSince(date)) }
    }
}
