import SwiftUI
import RosieCore

struct EvaluationValuePicker: View {
    let descriptors: [EvaluationMetricDescriptor]
    @Binding var selection: [EvaluationMetric]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wähle beliebig viele Werte. Unterschiedliche Einheiten werden bei Bedarf in Diagrammen mit derselben Zeitachse angezeigt.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Ausgewählt · \(selection.count)") {
                    ForEach(selection, id: \.self) { metric in
                        if let descriptor = descriptors.first(where: { $0.metric == metric }) {
                            row(descriptor)
                        }
                    }
                    .onMove { from, to in selection.move(fromOffsets: from, toOffset: to) }
                }
                Section("Weitere Werte") {
                    ForEach(descriptors.filter { !selection.contains($0.metric) && matches($0) }) { descriptor in
                        row(descriptor)
                    }
                }
            }
            .searchable(text: $search, prompt: "Wert oder eigenes Feld suchen")
            .navigationTitle("Werte auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }

    private func matches(_ descriptor: EvaluationMetricDescriptor) -> Bool {
        search.isEmpty || descriptor.name.localizedCaseInsensitiveContains(search)
    }

    private func row(_ descriptor: EvaluationMetricDescriptor) -> some View {
        let selected = selection.contains(descriptor.metric)
        return Button {
            if selected {
                if selection.count > 1 { selection.removeAll { $0 == descriptor.metric } }
            } else {
                selection.append(descriptor.metric)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.name).foregroundStyle(.primary)
                    Text(EvaluationValueFormatting.subtitle(descriptor))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "ausgewählt" : "nicht ausgewählt")
        .accessibilityHint(selected && selection.count == 1 ? "Mindestens ein Wert bleibt ausgewählt." : "Auswahl ändern")
    }
}

enum EvaluationValueFormatting {
    static func color(_ index: Int) -> Color {
        let colors: [Color] = [.teal, .orange, .blue, .purple, .pink, .brown]
        return colors[index % colors.count]
    }

    static func title(_ descriptor: EvaluationMetricDescriptor) -> String {
        let revision = descriptor.definition.map { " · V\($0.revision)" } ?? ""
        return descriptor.name + revision
    }

    static func subtitle(_ descriptor: EvaluationMetricDescriptor) -> String {
        var parts: [String] = []
        switch descriptor.kind {
        case .boolean: parts.append("Ja/Nein · Tagesmittel als Anteil Ja")
        case .category: parts.append("Kategorie · Markierungen")
        case .text: parts.append("Text · Markierungen")
        case .numeric:
            if isDuration(descriptor.metric) { parts.append("Minuten") }
            else if let unit = descriptor.unit { parts.append(unit) }
            if let scale = descriptor.scale {
                parts.append("Skala \(DecimalText.displayText(scale.lowerBound))–\(DecimalText.displayText(scale.upperBound))")
            }
        }
        if descriptor.metric == .lameness { parts.append("höher = stärker") }
        if descriptor.metric == .motivation { parts.append("höher = besser") }
        if descriptor.metric == .estimatedDistanceMeters { parts.append("GPS-Schätzung") }
        if let definition = descriptor.definition { parts.append("Version \(definition.revision)") }
        return parts.joined(separator: " · ")
    }

    static func isDuration(_ metric: EvaluationMetric) -> Bool {
        [.durationWithoutPauses, .totalDuration, .pauseDuration].contains(metric)
    }

    static func value(_ point: FlexibleEvaluationPoint, descriptor: EvaluationMetricDescriptor,
                      aggregation: EvaluationAggregation) -> String {
        if let boolean = point.booleanValue { return boolean ? "Ja" : "Nein" }
        if let text = point.textValue { return text }
        guard let number = point.numericValue else { return "Nicht angegeben" }
        if descriptor.kind == .boolean {
            let yesCount = Int((number * Double(point.sampleCount)).rounded())
            return "\(yesCount) von \(point.sampleCount): Ja (\(formatted(number * 100)) %)"
        }
        if isDuration(descriptor.metric) { return "\(formatted(number / 60)) Min." }
        let unit = descriptor.unit.map { " \($0)" } ?? ""
        return DecimalText.displayText(number) + unit
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...1)))
    }
}
