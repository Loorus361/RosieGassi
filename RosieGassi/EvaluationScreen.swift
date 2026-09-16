import SwiftUI
import RosieCore

struct EvaluationScreen: View {
    let store: WalkStore
    @Environment(GPSCoordinator.self) private var gps
    @State private var filter = EvaluationFilter(anchor: Date())
    @State private var selectedMetrics = EvaluationChartPreferences().selection
    @State private var aggregation: EvaluationAggregation = EvaluationChartPreferences().daily ? .day : .round
    @State private var selection: Date?
    @State private var editor: MetricEditorDestination?

    private struct MetricEditorDestination: Identifiable {
        let id = UUID()
    }

    var body: some View {
        let result = evaluation
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterCard
                    chartCard(result)
                    if let selection { detailCard(result, at: selection) }
                    if !result.rounds.isEmpty {
                        valuesCard(result)
                        EvaluationMetricsSection(metrics: WalkEvaluation.evaluate(
                            store.walks, filter: filter, routeProfile: gps.routeFilter
                        ).metrics)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Auswertung")
            .navigationDestination(for: UUID.self) { id in
                WalkScreen(store: store, walkID: id)
            }
            .sheet(item: $editor) { _ in
                EvaluationValuePicker(descriptors: available, selection: $selectedMetrics)
            }
        }
        .onChange(of: filter) { _, _ in selection = nil }
        .onChange(of: aggregation) { _, new in
            selection = nil
            EvaluationChartPreferences().save(daily: new == .day)
        }
        .onChange(of: selectedMetrics) { _, new in
            selection = nil
            EvaluationChartPreferences().save(selection: new)
        }
    }

    private var available: [EvaluationMetricDescriptor] {
        FlexibleWalkEvaluation.availableMetrics(in: store.walks, customFieldCatalog: store.fieldCatalog)
    }

    private var evaluation: FlexibleEvaluationResult {
        FlexibleWalkEvaluation.evaluate(store.walks, filter: filter, metrics: selectedMetrics,
            aggregation: aggregation, customFieldCatalog: store.fieldCatalog, routeProfile: gps.routeFilter)
    }

    private var filterCard: some View {
        RuheCard {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Zeitraum", selection: Binding(get: { filter.period }, set: { filter.setPeriod($0) })) {
                    ForEach(EvaluationPeriod.allCases, id: \.self) { period in
                        Text(period == .day ? "Tag" : period == .week ? "Woche" : "Monat").tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("evaluation.period")

                HStack(spacing: 8) {
                    Button { filter.goPrevious() } label: { Image(systemName: "chevron.left").frame(minWidth: 28, minHeight: 32) }
                        .accessibilityLabel("Vorheriger Zeitraum")
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text(periodTitle).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                        if !filter.isCurrentPeriod() {
                            Button("Heute") { filter.goToday() }.font(.footnote).frame(minHeight: 30)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { filter.goNext() } label: { Image(systemName: "chevron.right").frame(minWidth: 28, minHeight: 32) }
                        .accessibilityLabel("Nächster Zeitraum")
                }
                .buttonStyle(.bordered)

                Text("Tageszeit").font(.subheadline.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { bucketButtons }
                    VStack(alignment: .leading, spacing: 6) { bucketButtons }
                }
                Divider()
                Picker("Zusammenfassung", selection: $aggregation) {
                    Text("Einzelne Runden").tag(EvaluationAggregation.round)
                    Text("Tagesdurchschnitt").tag(EvaluationAggregation.day)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("evaluation.aggregation")
            }
        }
    }

    @ViewBuilder private var bucketButtons: some View {
        ForEach(TimeOfDayBucket.allCases, id: \.self) { bucket in
            let selected = filter.buckets.contains(bucket)
            Button { filter.toggle(bucket) } label: {
                Label(bucket.displayName, systemImage: selected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .fixedSize()
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .tint(selected ? .accentColor : .secondary)
            .accessibilityValue(selected ? "ausgewählt" : "nicht ausgewählt")
            .accessibilityIdentifier("evaluation.bucket.\(bucket.rawValue)")
        }
    }

    private func chartCard(_ result: FlexibleEvaluationResult) -> some View {
        RuheCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Verlauf").font(.headline)
                    Spacer()
                    Button { editor = MetricEditorDestination() } label: {
                        Label("Werte", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("evaluation.chooseMetrics")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], alignment: .leading, spacing: 8) {
                    ForEach(Array(result.series.enumerated()), id: \.element.id) { index, series in
                        Button { editor = MetricEditorDestination() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: index % 2 == 0 ? "circle.fill" : "diamond.fill").font(.caption)
                                Text(EvaluationValueFormatting.title(series.descriptor)).font(.subheadline)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(EvaluationValueFormatting.color(index).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(EvaluationValueFormatting.color(index))
                    }
                }
                if result.rounds.isEmpty {
                    ContentUnavailableView("Keine Runden im Zeitraum", systemImage: "calendar.badge.exclamationmark",
                        description: Text("Wechsle den Zeitraum oder die Tageszeitfilter."))
                } else {
                    FlexibleEvaluationChart(result: result, aggregation: aggregation, selection: $selection)
                    Text(aggregation == .day
                         ? "Je Punkt: Tagesmittel der ausgewählten Tageszeiten. Ja/Nein: Anteil Ja unter beantworteten Runden."
                         : "Ein Punkt je Runde. Tippe auf das Diagramm für Werte und Notizen.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Fehlende Angaben bleiben leer. Dauer ohne Pausen zieht nur manuelle Pausen ab.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detailCard(_ result: FlexibleEvaluationResult, at date: Date) -> some View {
        let points = result.series.flatMap(\.points)
        let nearest = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        return RuheCard {
            VStack(alignment: .leading, spacing: 12) {
                if let nearest {
                    Text(Self.dateText(nearest.date, time: aggregation == .round)).font(.headline)
                    ForEach(result.series) { series in
                        let point = series.points.first { $0.date == nearest.date && (aggregation == .day || $0.roundID == nearest.roundID) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(EvaluationValueFormatting.title(series.descriptor)).font(.subheadline.weight(.semibold))
                            if let point {
                                Text(EvaluationValueFormatting.value(point, descriptor: series.descriptor, aggregation: aggregation))
                                if aggregation == .day {
                                    Text("\(point.sampleCount) von \(point.totalCount) Runden mit Angabe")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Nicht angegeben").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let id = nearest.roundID, aggregation == .round {
                        NavigationLink(value: id) { Label("Runde öffnen", systemImage: "arrow.forward.circle").frame(minHeight: 44) }
                    } else {
                        ForEach(result.rounds.filter { EvaluationCalendar.rosie.calendar.isDate($0.startedAt, inSameDayAs: nearest.date) }) { round in
                            NavigationLink(value: round.id) {
                                Text("Runde um \(Self.timeFormatter.string(from: round.startedAt)) öffnen").frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
        }
    }

    private func valuesCard(_ result: FlexibleEvaluationResult) -> some View {
        RuheCard {
            DisclosureGroup("Runden im Zeitraum (\(result.rounds.count))") {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(result.rounds) { round in
                        NavigationLink(value: round.id) {
                            HStack {
                                Text(Self.dateText(round.startedAt, time: true))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.frame(minHeight: 44)
                        }
                    }
                }.padding(.top, 8)
            }
            .font(.subheadline)
        }
    }

    private var periodTitle: String {
        let interval = filter.interval()
        switch filter.period {
        case .day: return Self.dateText(interval.start, time: false)
        case .week: return "\(Self.shortFormatter.string(from: interval.start)) – \(Self.shortFormatter.string(from: interval.end.addingTimeInterval(-1)))"
        case .month: return Self.monthFormatter.string(from: interval.start)
        }
    }

    private static func dateText(_ date: Date, time: Bool) -> String {
        (time ? dateTimeFormatter : dateFormatter).string(from: date)
    }
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE")
        f.timeZone = EvaluationCalendar.rosieTimeZone; f.dateFormat = format
        return f
    }
    private static let dateTimeFormatter = formatter("EEE, d. MMM · HH:mm")
    private static let dateFormatter = formatter("EEEE, d. MMMM")
    private static let shortFormatter = formatter("d. MMM")
    private static let monthFormatter = formatter("MMMM yyyy")
    private static let timeFormatter = formatter("HH:mm")
}
