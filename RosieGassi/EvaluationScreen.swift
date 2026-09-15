import SwiftUI
import RosieCore

/// Tab „Auswertung“: gemeinsame Filter (Kalenderzeitraum und Tageszeit) sowie das
/// Verlaufsdiagramm. Diagramm und Kennzahlen erhalten exakt denselben gefilterten Bestand.
struct EvaluationScreen: View {
    let store: WalkStore
    @Environment(GPSCoordinator.self) private var gps
    @State private var filter = EvaluationFilter(anchor: Date())
    @State private var selectedRoundID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filterCard
                    if result.isEmpty {
                        emptyCard
                    } else {
                        chartCard
                        detailCard
                        valuesCard
                        EvaluationMetricsSection(metrics: result.metrics)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Auswertung")
            .navigationDestination(for: UUID.self) { id in
                WalkScreen(store: store, walkID: id)
            }
        }
        // Ein Filterwechsel darf keine Runde aus einem anderen Zeitraum ausgewählt lassen.
        .onChange(of: filter) { _, _ in selectedRoundID = nil }
    }

    /// Gemeinsamer gefilterter Datenbestand für Diagramm und Kennzahlen.
    private var result: EvaluationResult {
        WalkEvaluation.evaluate(store.walks, filter: filter, routeProfile: gps.routeFilter)
    }

    private var selectedRound: EvaluationRound? {
        selectedRoundID.flatMap { result.round($0) }
    }

    // MARK: - Filter

    private var filterCard: some View {
        RuheCard {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Zeitraum", selection: periodBinding) {
                    ForEach(EvaluationPeriod.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("evaluation.period")

                HStack(spacing: 12) {
                    Button {
                        filter.goPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityIdentifier("evaluation.previous")
                    .accessibilityLabel("Vorheriger Zeitraum")

                    Spacer(minLength: 0)

                    Button("Heute") { filter.goToday() }
                        .disabled(filter.isCurrentPeriod())
                        .accessibilityIdentifier("evaluation.today")

                    Spacer(minLength: 0)

                    Button {
                        filter.goNext()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityIdentifier("evaluation.next")
                    .accessibilityLabel("Nächster Zeitraum")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(periodTitle)
                        .font(.headline)
                        .accessibilityIdentifier("evaluation.periodTitle")
                    Text(periodRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("evaluation.periodRange")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tageszeit")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(TimeOfDayBucket.allCases, id: \.self) { bucket in
                            bucketChip(bucket)
                        }
                    }
                    Text(bucketHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("evaluation.bucketHint")
                }
            }
        }
    }

    private var periodBinding: Binding<EvaluationPeriod> {
        Binding(
            get: { filter.period },
            set: { filter.setPeriod($0) }
        )
    }

    private func bucketChip(_ bucket: TimeOfDayBucket) -> some View {
        let isSelected = filter.buckets.contains(bucket)
        let isLastSelected = isSelected && filter.buckets.count == 1
        return Button {
            filter.toggle(bucket)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(bucket.displayName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Color.accentColor : Color.secondary)
        .accessibilityIdentifier("evaluation.bucket.\(bucket.rawValue)")
        .accessibilityLabel("Tageszeit \(bucket.displayName)")
        .accessibilityValue(isSelected ? "ausgewählt" : "nicht ausgewählt")
        .accessibilityHint(isLastSelected
                           ? "Mindestens ein Bereich bleibt ausgewählt."
                           : "Doppelt aktivieren oder deaktivieren.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var bucketHint: String {
        if filter.isAllBucketsSelected { return "Alle Tageszeiten werden ausgewertet." }
        if filter.buckets.count == 1 { return "Mindestens ein Bereich bleibt ausgewählt." }
        return "Die ausgewählten Bereiche werden gemeinsam ausgewertet."
    }

    // MARK: - Karten

    private var emptyCard: some View {
        RuheCard {
            ContentUnavailableView {
                Label("Keine Runden im Zeitraum", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Für \(periodTitle) liegen keine Runden vor. Nutze die Pfeile oder wechsle den Zeitraum.")
            }
            .accessibilityIdentifier("evaluation.empty")
        }
    }

    private var chartCard: some View {
        RuheCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Verlauf: Motivation und Lahmheit")
                    .font(.headline)
                if hasScores {
                    EvaluationChart(result: result, selection: chartSelection, selectedRoundID: selectedRound?.id)
                        .frame(height: 240)
                    EvaluationLegend()
                    Text("Tippe auf einen Punkt für Details.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView {
                        Label("Keine Bewertungen", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Für \(periodTitle) liegen keine Motivation- oder Lahmheit-Werte vor. Fehlende Werte bleiben leer und werden nicht als 0 dargestellt.")
                    }
                    .accessibilityIdentifier("evaluation.chart.empty")
                }
            }
        }
    }

    @ViewBuilder
    private var detailCard: some View {
        if let round = selectedRound {
            RuheCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ausgewählte Runde")
                        .font(.headline)
                    EvaluationPointDetail(round: round)
                }
            }
        }
    }

    private var valuesCard: some View {
        let scored = result.rounds.filter { $0.hasAnyScore() }
        return RuheCard {
            DisclosureGroup {
                VStack(spacing: 0) {
                    ForEach(scored) { round in
                        Button {
                            selectedRoundID = round.id
                        } label: {
                            HStack(spacing: 10) {
                                HStack(spacing: 2) {
                                    if round.motivation != nil {
                                        Image(systemName: EvaluationStyle.symbolName(for: .motivation))
                                            .foregroundStyle(EvaluationStyle.color(for: .motivation))
                                    }
                                    if round.lameness != nil {
                                        Image(systemName: EvaluationStyle.symbolName(for: .lameness))
                                            .foregroundStyle(EvaluationStyle.color(for: .lameness))
                                    }
                                }
                                .font(.footnote)
                                .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rowTitle(for: round))
                                        .font(.subheadline)
                                    Text(rowSubtitle(for: round))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if round.id == selectedRound?.id {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("evaluation.round.\(round.id.uuidString)")
                        .accessibilityLabel(rowAccessibilityLabel(for: round))
                        .accessibilityAddTraits(round.id == selectedRound?.id ? [.isSelected] : [])
                        if round.id != scored.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                // Identifier nur am Label: sonst erben die Zeilenknöpfe ihn und verlieren ihre eigene ID.
                Text("Werte je Runde (\(scored.count))")
                    .font(.headline)
                    .accessibilityIdentifier("evaluation.values")
            }
            .tint(.primary)
        }
    }

    // MARK: - Hilfen

    private var hasScores: Bool {
        !result.motivationSeries.isEmpty || !result.lamenessSeries.isEmpty
    }

    /// Diagramm-Auswahl wird als stabile Runden-ID gehalten; `nil` bedeutet keine Auswahl.
    private var chartSelection: Binding<Date?> {
        Binding(
            get: { selectedRound?.startedAt },
            set: { date in
                guard let date else { selectedRoundID = nil; return }
                selectedRoundID = result.nearestScoredRound(to: date)?.id
            }
        )
    }

    private var periodTitle: String {
        switch filter.period {
        case .week:
            let week = EvaluationCalendar.rosie.calendar.component(.weekOfYear, from: filter.interval().start)
            return "Kalenderwoche \(week)"
        case .month:
            return Self.monthFormatter.string(from: filter.interval().start)
        }
    }

    private var periodRange: String {
        let interval = filter.interval()
        // Halboffener Bereich: der letzte Tag gehört noch dazu.
        let lastDay = interval.end.addingTimeInterval(-1)
        return "\(Self.shortDateFormatter.string(from: interval.start)) – \(Self.shortDateFormatter.string(from: lastDay))"
    }

    private func rowTitle(for round: EvaluationRound) -> String {
        Self.rowDateFormatter.string(from: round.startedAt)
    }

    private func rowSubtitle(for round: EvaluationRound) -> String {
        var parts: [String] = []
        for metric in ScoreMetric.allCases {
            guard let value = round.score(for: metric) else { continue }
            parts.append("\(metric.displayName) \(Self.scoreFormatter.string(from: value as NSNumber) ?? "\(value)")")
        }
        parts.append(round.bucket.displayName)
        return parts.joined(separator: " · ")
    }

    private func rowAccessibilityLabel(for round: EvaluationRound) -> String {
        var parts = [rowTitle(for: round), rowSubtitle(for: round)]
        parts.append("Runde öffnen über die Detailkarte")
        return parts.joined(separator: ", ")
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = EvaluationCalendar.rosieTimeZone
        formatter.dateFormat = "d. MMM yyyy"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = EvaluationCalendar.rosieTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = EvaluationCalendar.rosieTimeZone
        formatter.dateFormat = "EEEE, d. MMM, HH:mm"
        return formatter
    }()

    private static let scoreFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}
