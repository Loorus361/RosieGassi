import SwiftUI
import RosieCore

struct RatingControl: View {
    let title: String
    let identifier: String
    let low: String
    let high: String
    @Binding var value: Double?

    private var display: String {
        guard let value else { return "Nicht bewertet" }
        return value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...8))) + " / 7"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(display).foregroundStyle(value == nil ? Color.secondary : Color.accentColor)
                    .font(.subheadline).monospacedDigit()
                    .accessibilityIdentifier("rating.\(identifier).value")
            }
            if let current = value {
                Slider(value: Binding(get: { current }, set: { value = $0 }), in: 1...7, step: 0.5)
                    .accessibilityLabel(title)
                    .accessibilityValue(display)
                HStack {
                    Button { value = max(1, current - 0.5) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                        .accessibilityLabel(title + " verringern").accessibilityIdentifier("rating.\(identifier).minus")
                    Spacer()
                    Button("Zurücksetzen") { value = nil }
                        .font(.subheadline).frame(minHeight: 44)
                        .accessibilityLabel(title + " zurücksetzen").accessibilityIdentifier("rating.\(identifier).reset")
                    Spacer()
                    Button { value = min(7, current + 0.5) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .accessibilityLabel(title + " erhöhen").accessibilityIdentifier("rating.\(identifier).plus")
                }.buttonStyle(.borderless)
            } else {
                Button("Bewerten") { value = 4 }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityLabel(title + " bewerten")
                    .accessibilityHint("Öffnet die Skala mit dem Wert 4. Du kannst ihn ändern oder zurücksetzen.")
                    .accessibilityIdentifier("rating.\(identifier).set")
            }
            HStack {
                Text("1 · " + low)
                Spacer()
                Text("7 · " + high)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CheckpointControl: View {
    let title: String
    @Binding var value: Checkpoint?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if value != nil {
                    Button { value = nil } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title + " offen lassen")
                    .accessibilityHint("Setzt nur diese Station auf nicht erfasst zurück.")
                    .accessibilityIdentifier("checkpoint.\(title).clear")
                }
            }
            if value == nil {
                Text("Nicht erfasst").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("checkpoint.\(title).unanswered")
            }
            // Large text gets full-width rows rather than truncated tiny segments.
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 4) { options(horizontal: true) }
                }
                VStack(spacing: 4) { options(horizontal: false) }
            }
            .padding(4)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityElement(children: .contain)
    }

    private func options(horizontal: Bool) -> some View {
        ForEach(Checkpoint.allCases, id: \.self) { option in
            let selected = value == option
            Button { value = option } label: {
                Text(option.displayName)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .fixedSize(horizontal: horizontal, vertical: true)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .background(selected ? Color(uiColor: .secondarySystemGroupedBackground) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + ", " + option.displayName)
            .accessibilityValue(selected ? "Ausgewählt" : "Nicht ausgewählt")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("checkpoint.\(title).\(option.rawValue)")
        }
    }
}
