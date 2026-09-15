import SwiftUI
import RosieCore

struct CustomFieldsCard: View {
    let fields: [CustomFieldObservation]
    let canEdit: Bool
    let update: (UUID, CustomFieldValue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Eigene Felder").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            RuheCard {
                VStack(spacing: 20) {
                    ForEach(Array(fields.enumerated()), id: \.element.definition.id) { index, observation in
                        if index > 0 { Divider() }
                        CustomFieldControl(observation: observation, update: update)
                    }
                }
            }.disabled(!canEdit)
            Text("Ohne Eingabe bleibt der Wert offen. Kein Feld wird automatisch gesetzt.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct CustomFieldControl: View {
    let observation: CustomFieldObservation
    let update: (UUID, CustomFieldValue) -> Void

    var body: some View {
        switch observation.definition.kind {
        case .boolean:
            BooleanFieldControl(observation: observation, update: update)
        case .scale:
            ScaleFieldControl(observation: observation, update: update)
        case .number:
            NumberFieldControl(observation: observation, update: update)
        case .graded:
            GradedFieldControl(observation: observation, update: update)
        }
    }
}

/// Geordnete Auswahl genau einer frei beschrifteten Option einer Abstufung.
///
/// Keine Vorbelegung: eine Runde bindet das Feld mit `.missing` („Nicht erfasst“),
/// bis jemand bewusst eine Option tippt. Zurücksetzen ist ein eigener Schritt und
/// setzt wieder `.missing`. Der Text kommt immer aus der Definition *dieser*
/// Beobachtung, damit historische Antworten nach einer Feldrevision oder
/// Archivierung ihre damalige Beschriftung behalten. Es gibt keine numerische
/// Auswertung und keine Gesundheitsbewertung.
struct GradedFieldControl: View {
    let observation: CustomFieldObservation
    let update: (UUID, CustomFieldValue) -> Void

    private var title: String { observation.definition.name }
    private var options: [CustomFieldOption] { observation.definition.orderedOptions }
    private var selectedID: UUID? {
        if case .choice(let id) = observation.value { return id }
        return nil
    }
    /// Text der damaligen Revision dieser Beobachtung; `nil`, solange nichts gewählt ist.
    private var selectedLabel: String? { observation.definition.label(for: observation.value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if selectedID != nil {
                    Button { update(observation.definition.id, .missing) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title + " offen lassen")
                    .accessibilityHint("Setzt die Auswahl auf nicht erfasst zurück.")
                    .accessibilityIdentifier("custom.\(title).clear")
                }
            }
            if let selectedLabel {
                Text(selectedLabel).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("custom.\(title).value")
            } else {
                Text("Nicht erfasst").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("custom.\(title).unanswered")
            }
            // Freie, möglicherweise lange und unterschiedlich viele Beschriftungen bleiben
            // untereinander lesbar; jede Zeile ist ein eigenes, mindestens 44 pt hohes Ziel.
            VStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    optionButton(option, index: index)
                }
            }
            .padding(4)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
        }
    }

    private func optionButton(_ option: CustomFieldOption, index: Int) -> some View {
        let isSelected = selectedID == option.id
        return Button {
            // Erneutes Tippen hält die Auswahl; das Zurücksetzen ist bewusst ein eigener Schritt.
            update(observation.definition.id, .choice(option.id))
        } label: {
            Text(option.label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .background(isSelected ? Color(uiColor: .secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ", " + option.label)
        .accessibilityValue(isSelected ? "Ausgewählt" : "Nicht ausgewählt")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("custom.\(title).option.\(index)")
    }
}

struct BooleanFieldControl: View {
    let observation: CustomFieldObservation
    let update: (UUID, CustomFieldValue) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String { observation.definition.name }
    private var selected: Bool? {
        if case .boolean(let value) = observation.value { return value }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if selected != nil {
                    Button { update(observation.definition.id, .missing) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title + " offen lassen")
                    .accessibilityIdentifier("custom.\(title).clear")
                }
            }
            if selected == nil {
                Text("Nicht erfasst").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("custom.\(title).unanswered")
            }
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 4) { options(horizontal: true) }
                }
                VStack(spacing: 4) { options(horizontal: false) }
            }
            .padding(4)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func options(horizontal: Bool) -> some View {
        ForEach([(true, "Ja"), (false, "Nein")], id: \.1) { value, label in
            let isSelected = selected == value
            Button { update(observation.definition.id, .boolean(value)) } label: {
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .fixedSize(horizontal: horizontal, vertical: true)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .background(isSelected ? Color(uiColor: .secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + ", " + label)
            .accessibilityValue(isSelected ? "Ausgewählt" : "Nicht ausgewählt")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("custom.\(title).\(value ? "true" : "false")")
        }
    }
}

struct ScaleFieldControl: View {
    let observation: CustomFieldObservation
    let update: (UUID, CustomFieldValue) -> Void

    private var title: String { observation.definition.name }
    private var current: Double? {
        if case .scale(let value) = observation.value { return value }
        return nil
    }
    private var minValue: Double { observation.definition.scaleMin ?? 1 }
    private var maxValue: Double { observation.definition.scaleMax ?? 7 }
    private var step: Double { observation.definition.scaleStep ?? 0.5 }

    private var display: String {
        guard let current else { return "Nicht erfasst" }
        return DecimalText.displayText(current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(display).foregroundStyle(current == nil ? Color.secondary : Color.accentColor)
                    .font(.subheadline).monospacedDigit()
                    .accessibilityIdentifier("custom.\(title).value")
            }
            if let current {
                Slider(
                    value: Binding(get: { current }, set: { update(observation.definition.id, .scale(observation.definition.snapped($0))) }),
                    in: minValue...maxValue,
                    step: step
                )
                .accessibilityLabel(title)
                .accessibilityValue(display)
                HStack {
                    Button { update(observation.definition.id, .scale(observation.definition.advanced(from: current, steps: -1))) } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(title + " verringern").accessibilityIdentifier("custom.\(title).minus")
                    Spacer()
                    Button("Zurücksetzen") { update(observation.definition.id, .missing) }
                        .font(.subheadline).frame(minHeight: 44)
                        .accessibilityLabel(title + " zurücksetzen").accessibilityIdentifier("custom.\(title).reset")
                    Spacer()
                    Button { update(observation.definition.id, .scale(observation.definition.advanced(from: current, steps: 1))) } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(title + " erhöhen").accessibilityIdentifier("custom.\(title).plus")
                }.buttonStyle(.borderless)
            } else {
                Button("Erfassen") { update(observation.definition.id, .scale(minValue)) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityLabel(title + " erfassen")
                    .accessibilityIdentifier("custom.\(title).set")
            }
            HStack {
                Text(scaleCaption(minValue, observation.definition.scaleLowLabel))
                Spacer()
                Text(scaleCaption(maxValue, observation.definition.scaleHighLabel))
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scaleCaption(_ value: Double, _ label: String?) -> String {
        let number = DecimalText.displayText(value)
        if let label, !label.isEmpty { return number + " · " + label }
        return number
    }
}

struct NumberFieldControl: View {
    let observation: CustomFieldObservation
    let update: (UUID, CustomFieldValue) -> Void
    @State private var draft = ""
    @State private var parseError: String?

    private var title: String { observation.definition.name }
    private var current: Double? {
        if case .number(let value) = observation.value { return value }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(current.map { DecimalText.displayText($0) } ?? "Nicht erfasst")
                .foregroundStyle(current == nil ? Color.secondary : Color.accentColor)
                .font(.subheadline).monospacedDigit()
                .accessibilityIdentifier("custom.\(title).value")
            }
            HStack {
                TextField(observation.definition.unit ?? "Zahl", text: $draft)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("custom.\(title).number")
                    .onSubmit(commit)
                Button("Übernehmen") { commit() }.frame(minHeight: 44)
                    .accessibilityIdentifier("custom.\(title).commit")
            }
            HStack {
                if current != nil || !draft.isEmpty {
                    Button("Zurücksetzen") {
                        draft = ""
                        parseError = nil
                        update(observation.definition.id, .missing)
                    }
                    .font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("custom.\(title).reset")
                }
                if let unit = observation.definition.unit {
                    Text(unit).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let parseError { Text(parseError).font(.footnote).foregroundStyle(.red) }
        }
        .onAppear { draft = editing(current) }
        .onChange(of: observation.value) { _, _ in draft = editing(current) }
    }

    private func editing(_ value: Double?) -> String {
        guard let value else { return "" }
        return DecimalText.editingText(value)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            parseError = nil
            update(observation.definition.id, .missing)
            return
        }
        do {
            let value = try DecimalText.parse(trimmed)
            parseError = nil
            update(observation.definition.id, .number(value))
        } catch {
            parseError = error.localizedDescription
        }
    }
}
