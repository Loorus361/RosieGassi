import SwiftUI
import RosieCore

/// Einstellungsabschnitt für den Live-Activity-Schnellvermerk.
///
/// Genau ein aktives, selbst angelegtes, nicht archiviertes Ja/Nein-Feld ist wählbar;
/// Standard ist „Keine“. Die Auswahl wird lokal als Feld-ID gespeichert und gilt erst
/// ab der nächsten Runde – die laufende Runde behält die bei ihrem Start eingefrorene
/// Definition. Dieser Abschnitt schreibt nie eine aktive Bindung.
struct QuickNoteSettingsSection: View {
    let store: WalkStore

    private let defaults = QuickNotePreferences.preferenceStore()

    /// Wirksame Auswahl: `nil` = Keine. Wird aus Ablage + Katalog abgeleitet.
    @State private var selection: UUID?
    /// Eine gespeicherte, aber nicht mehr gültige Auswahl ist vorhanden.
    @State private var hasUnavailableSelection = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var selectable: [CustomFieldDefinition] {
        QuickNotePreferences.selectableFields(in: store.fieldCatalog)
    }

    var body: some View {
        Section {
            optionRow(name: "Keine", selected: selection == nil, isNone: true) { choose(nil) }

            ForEach(selectable) { field in
                optionRow(name: field.name, selected: selection == field.id, isNone: false) {
                    choose(field.id)
                }
            }

            if selectable.isEmpty {
                Text("Noch kein eigenes Ja/Nein-Feld. Lege unter „Eigene Felder“ eines an, um einen Schnellvermerk anzubieten.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("quickNote.empty")
            }

            if hasUnavailableSelection {
                Text("Die zuvor gewählte Auswahl ist nicht mehr verfügbar und gilt als „Keine“. Bitte ein gültiges Ja/Nein-Feld wählen.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("quickNote.unavailable")
            }
        } header: {
            Text("Schnellvermerk")
        } footer: {
            Text("Änderungen gelten ab der nächsten Runde. Feldname und Zustand können auf dem Sperrbildschirm und auf verbundenen Geräten sichtbar sein.")
        }
        .onAppear(perform: reload)
        .onChange(of: store.fieldCatalog) { reload() }
    }

    /// Eine wählbare Zeile: Symbol UND Farbe zeigen den Zustand, die volle Zeile ist Ziel.
    /// Bei sehr großer Schrift bleiben Name und Zustand untereinander lesbar.
    @ViewBuilder
    private func optionRow(name: String, selected: Bool, isNone: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        optionSymbol(selected: selected)
                        Text(name).foregroundStyle(.primary)
                        if selected { selectedLabel }
                    }
                } else {
                    HStack(spacing: 12) {
                        optionSymbol(selected: selected)
                        Text(name).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if selected { selectedLabel }
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(selected ? "Ausgewählt" : "Nicht ausgewählt")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(isNone ? "quickNote.option.none" : "quickNote.option.\(name)")
    }

    @ViewBuilder
    private func optionSymbol(selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
    }

    private var selectedLabel: some View {
        Text("Ausgewählt").font(.footnote).foregroundStyle(.secondary)
    }

    /// Speichert die Auswahl rein lokal; eine laufende Runde wird nicht berührt.
    private func choose(_ id: UUID?) {
        QuickNotePreferences.setSelection(id, in: defaults)
        reload()
    }

    /// Leitet den sichtbaren Zustand aus Ablage und aktuellem Katalog ab. Eine archivierte
    /// oder ungültige gespeicherte Auswahl führt so sichtbar auf „Keine“ zurück.
    private func reload() {
        let catalog = store.fieldCatalog
        selection = QuickNotePreferences.resolvedDefinition(in: defaults, catalog: catalog)?.id
        hasUnavailableSelection = QuickNotePreferences.hasUnavailableSelection(in: defaults, catalog: catalog)
    }
}