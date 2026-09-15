import SwiftUI
import RosieCore

struct SettingsScreen: View {
    let store: WalkStore
    @Environment(GPSCoordinator.self) private var gps
    @State private var editor: FieldEditorState?
    @State private var pendingArchive: CustomFieldCatalogEntry?
    @State private var error: String?

    private var active: [CustomFieldCatalogEntry] {
        store.fieldCatalog.entries.filter { !$0.archived }.sorted { $0.sortIndex < $1.sortIndex }
    }
    private var archived: [CustomFieldCatalogEntry] {
        store.fieldCatalog.entries.filter(\.archived).sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if gps.consent {
                        Button("GPS-Einwilligung für kommende Runden widerrufen", role: .destructive) {
                            gps.revokeConsent()
                        }
                        .accessibilityIdentifier("gps.revoke")
                    } else {
                        Text("Keine GPS-Einwilligung gespeichert. Du kannst GPS vor dem Start einer Runde aktivieren.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Widerruf gilt für kommende Runden. Eine bereits gestartete GPS-Runde wird beendet, gespeicherte Punkte bleiben.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Datenschutz / GPS") }

                Section {
                    Picker("GPS-Detail", selection: Binding(
                        get: { gps.routeFilter },
                        set: { gps.setRouteFilter($0) }
                    )) {
                        ForEach(RouteFilterProfile.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("gps.filter")
                    Button("Auf Standard zurücksetzen") { gps.resetRouteFilter() }
                        .disabled(gps.routeFilter == .standard)
                        .accessibilityIdentifier("gps.filter.reset")
                } header: { Text("GPS-Route") } footer: {
                    Text("Bestimmt, wie stark die gespeicherte Route für die Anzeige vereinfacht wird. „Detaillierter“ zeigt mehr Punkte, „stärker geglättet“ eine ruhigere Linie. Die gespeicherten GPS-Punkte bleiben unverändert; die Einstellung gilt daher auch für bereits vorhandene Runden.")
                }

                Section {
                    if active.isEmpty {
                        Text("Noch keine eigenen Felder. Neue Runden bleiben ohne zusätzlichen Block.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("fields.empty")
                    }
                    ForEach(active) { entry in
                        Button {
                            editor = FieldEditorState(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.current.name)
                                Text(entry.current.kind.displayName + " · Revision \(entry.current.revision)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("fields.row.\(entry.current.name)")
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in
                        if let index = offsets.first { pendingArchive = active[index] }
                    }
                    Button {
                        editor = FieldEditorState(entry: nil)
                    } label: {
                        Label("Feld hinzufügen", systemImage: "plus")
                    }
                    .accessibilityIdentifier("fields.add")
                } header: { Text("Eigene Felder") } footer: {
                    Text("Felder erscheinen in neuen Runden unter den Beobachtungen. Archivieren entfernt sie nur für künftige Runden; alte Werte bleiben.")
                }

                if !archived.isEmpty {
                    Section("Archiviert") {
                        ForEach(archived) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.current.name)
                                Text(entry.current.kind.displayName + " · Revision \(entry.current.revision)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("fields.archived.\(entry.current.name)")
                        }
                    }
                }

                QuickNoteSettingsSection(store: store)
            }
            .navigationTitle("Einstellungen")
            .toolbar { EditButton() }
            .alert("Feld archivieren?", isPresented: Binding(
                get: { pendingArchive != nil },
                set: { if !$0 { pendingArchive = nil } }
            ), presenting: pendingArchive) { entry in
                Button("Archivieren", role: .destructive) {
                    do { try store.archiveField(entry.id); error = nil }
                    catch { self.error = error.localizedDescription }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { entry in
                Text("„\(entry.current.name)“ entfällt in neuen Runden. Bereits gestartete und alte Runden behalten ihre Werte.")
            }
            .alert("Änderung nicht gespeichert", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
            .sheet(item: $editor) { state in
                FieldEditorSheet(store: store, entry: state.entry)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = active.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do { try store.reorderFields(ids); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct FieldEditorState: Identifiable {
    let id = UUID()
    let entry: CustomFieldCatalogEntry?
}

private struct FieldEditorSheet: View {
    let store: WalkStore
    let entry: CustomFieldCatalogEntry?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var name: String
    @State private var kind: CustomFieldKind
    @State private var unit: String
    @State private var minText: String
    @State private var maxText: String
    @State private var stepText: String
    @State private var lowLabel: String
    @State private var highLabel: String
    @State private var options: CustomFieldOptionsDraft
    @State private var error: String?

    init(store: WalkStore, entry: CustomFieldCatalogEntry?) {
        self.store = store
        self.entry = entry
        let current = entry?.current
        _name = State(initialValue: current?.name ?? "")
        _kind = State(initialValue: current?.kind ?? .boolean)
        _unit = State(initialValue: current?.unit ?? "")
        _minText = State(initialValue: formatted(current?.scaleMin) ?? "1")
        _maxText = State(initialValue: formatted(current?.scaleMax) ?? "7")
        _stepText = State(initialValue: formatted(current?.scaleStep) ?? "0,5")
        _lowLabel = State(initialValue: current?.scaleLowLabel ?? "")
        _highLabel = State(initialValue: current?.scaleHighLabel ?? "")
        _options = State(initialValue: CustomFieldOptionsDraft(current?.orderedOptions ?? []))
        _error = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("fields.name")
                    Picker("Typ", selection: $kind) {
                        ForEach(CustomFieldKind.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fields.kind")
                }
                if kind == .number {
                    Section("Zahl") {
                        TextField("Einheit, optional", text: $unit)
                            .accessibilityIdentifier("fields.unit")
                    }
                }
                if kind == .scale {
                    Section("Skala") {
                        TextField("Minimum", text: $minText).keyboardType(.decimalPad)
                            .accessibilityIdentifier("fields.min")
                        TextField("Maximum", text: $maxText).keyboardType(.decimalPad)
                            .accessibilityIdentifier("fields.max")
                        TextField("Schrittweite", text: $stepText).keyboardType(.decimalPad)
                            .accessibilityIdentifier("fields.step")
                        TextField("Beschriftung unten, optional", text: $lowLabel)
                            .accessibilityIdentifier("fields.low")
                        TextField("Beschriftung oben, optional", text: $highLabel)
                            .accessibilityIdentifier("fields.high")
                    }
                }
                if kind == .graded {
                    Section {
                        if options.isEmpty {
                            Text("Noch keine Option. Mindestens eine eigene Beschriftung ist nötig.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("fields.options.empty")
                        }
                        ForEach($options.rows) { $row in
                            optionRow($row)
                        }
                        .onDelete { options.remove(at: $0) }
                        Button {
                            options.addRow()
                        } label: {
                            Label("Option hinzufügen", systemImage: "plus")
                        }
                        .accessibilityIdentifier("fields.option.add")
                    } header: {
                        Text("Abstufungen")
                    } footer: {
                        Text("Die Reihenfolge ist die Anzeige-Reihenfolge. Pro Runde wird höchstens eine Option gewählt; ohne Auswahl bleibt das Feld offen. Geänderte Beschriftungen oder Reihenfolgen erzeugen bei vorhandenen alten Werten eine neue Revision, alte Werte bleiben unverändert lesbar.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(entry == nil ? "Neues Feld" : "Feld ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save).accessibilityIdentifier("fields.save")
                }
            }
        }
    }

    /// Eine bearbeitbare Optionszeile. Umsortieren läuft über die stabile Zeilen-ID,
    /// damit die Identität beim Verschieben und Umbenennen erhalten bleibt.
    @ViewBuilder
    private func optionRow(_ row: Binding<CustomFieldOptionsDraft.Row>) -> some View {
        let id = row.wrappedValue.id
        let index = options.rows.firstIndex { $0.id == id } ?? 0
        let position = index + 1
        if dynamicTypeSize.isAccessibilitySize {
            // Bei sehr großer Schrift bleiben Feld und Umsortierknöpfe untereinander lesbar.
            VStack(alignment: .leading, spacing: 8) {
                optionLabelField(row, index: index, position: position)
                optionMoveButtons(id: id, position: position)
            }
        } else {
            HStack(spacing: 8) {
                optionLabelField(row, index: index, position: position)
                optionMoveButtons(id: id, position: position)
            }
        }
    }

    @ViewBuilder
    private func optionLabelField(_ row: Binding<CustomFieldOptionsDraft.Row>, index: Int, position: Int) -> some View {
        TextField("Beschriftung", text: row.label)
            .accessibilityLabel("Option \(position) Beschriftung")
            .accessibilityIdentifier("fields.option.\(index)")
    }

    @ViewBuilder
    private func optionMoveButtons(id: UUID, position: Int) -> some View {
        Button {
            options.moveUp(id: id)
        } label: {
            Image(systemName: "arrow.up")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!options.canMoveUp(id: id))
        .accessibilityLabel("Option \(position) nach oben")
        .accessibilityIdentifier("fields.option.up.\(position - 1)")
        Button {
            options.moveDown(id: id)
        } label: {
            Image(systemName: "arrow.down")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!options.canMoveDown(id: id))
        .accessibilityLabel("Option \(position) nach unten")
        .accessibilityIdentifier("fields.option.down.\(position - 1)")
    }

    private func save() {
        do {
            let unitValue = kind == .number ? unit : nil
            let min = kind == .scale ? try DecimalText.parse(minText) : nil
            let max = kind == .scale ? try DecimalText.parse(maxText) : nil
            let step = kind == .scale ? try DecimalText.parse(stepText) : nil
            let low = kind == .scale ? lowLabel : nil
            let high = kind == .scale ? highLabel : nil
            let optionsValue = kind == .graded ? try options.makeOptions() : nil
            if let entry {
                try store.reviseField(
                    entry.id, name: name, kind: kind, unit: unitValue,
                    scaleMin: min, scaleMax: max, scaleStep: step,
                    scaleLowLabel: low, scaleHighLabel: high,
                    options: optionsValue
                )
            } else {
                _ = try store.createField(
                    name: name, kind: kind, unit: unitValue,
                    scaleMin: min, scaleMax: max, scaleStep: step,
                    scaleLowLabel: low, scaleHighLabel: high,
                    options: optionsValue
                )
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private func formatted(_ value: Double?) -> String? {
    guard let value else { return nil }
    return DecimalText.editingText(value)
}
