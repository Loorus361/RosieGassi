import SwiftUI
import RosieCore

private struct FinishProposal: Identifiable {
    let id = UUID()
    let date: Date
}

struct WalkScreen: View {
    let store: WalkStore
    let walkID: UUID
    /// Live-Activity-„Stopp“: genau diese Runde direkt mit der vorhandenen Abschlussmaske
    /// öffnen. Betrifft nur eine `finish`-Anfrage an exakt `walkID`.
    var finishRequest: RosieActiveWalkLink.PendingRequest?
    var onConsumedFinish: (RosieActiveWalkLink.PendingRequest) -> Void = { _ in }
    @Environment(GPSCoordinator.self) private var gps
    @Environment(WeatherCoordinator.self) private var weather
    @State private var proposal: FinishProposal?
    @State private var editingTimes = false
    @State private var draftNotes = ""
    @State private var error: String?
    @State private var showingSaveError = false
    @State private var failedChange: ((inout Walk) throws -> Void)?
    @State private var editConfirmed = false
    @State private var showingEditConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var notesFocused: Bool

    private var walk: Walk? { store.walks.first { $0.id == walkID } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
    }

    private func content(at now: Date) -> some View {
        Group {
            if let walk {
                let canEdit = editConfirmed || !walk.requiresEditConfirmation(at: now)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        clockCard(walk, at: proposal?.date ?? now, canEdit: canEdit)
                        weatherCard(walk)
                        if walk.endedAt != nil {
                            Label("Runde abgeschlossen", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor).font(.headline)
                                .accessibilityIdentifier("walk.completed")
                            RuheCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    if editConfirmed {
                                        Label("Bearbeitung freigegeben", systemImage: "lock.open")
                                        Button("Bearbeitung beenden") { editConfirmed = false }
                                            .accessibilityIdentifier("walk.endEditing")
                                    } else if !canEdit {
                                        Label("Vor Änderungen geschützt", systemImage: "lock")
                                        Text("Zum nachträglichen Ändern bitte die Bearbeitung bestätigen.")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        Button("Bearbeiten") { showingEditConfirmation = true }
                                            .buttonStyle(.bordered)
                                            .accessibilityIdentifier("walk.requestEdit")
                                    } else {
                                        Label("Noch direkt bearbeitbar", systemImage: "pencil")
                                        Text("Fünf Minuten nach dem Rundenende werden Änderungen nur noch nach Bestätigung möglich.")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Text("Wie geht es Rosie?").font(.title3.bold())
                        RuheCard {
                            VStack(spacing: 20) {
                                RatingControl(title: "Lahmheit", identifier: "lameness", low: "niedrig", high: "hoch", value: binding(\.lameness, in: walk))
                                Divider()
                                RatingControl(title: "Motivation", identifier: "motivation", low: "niedrig", high: "hoch", value: binding(\.motivation, in: walk))
                            }
                        }.disabled(!canEdit)
                        Text("Beides ist optional. Keine Eingabe ist kein Messwert.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Stationen").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        RuheCard {
                            VStack(spacing: 12) {
                                CheckpointControl(title: "Fahrstuhl", value: binding(\.elevator, in: walk))
                                Divider()
                                CheckpointControl(title: "Flur", value: binding(\.hallway, in: walk))
                                Divider()
                                CheckpointControl(title: "Hof", value: binding(\.courtyard, in: walk))
                            }
                        }.disabled(!canEdit)
                        Text("Vereinbarte Vorgabe: OK. Bei Bedarf ändern oder offen lassen.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !walk.customFields.isEmpty {
                            CustomFieldsCard(fields: walk.customFields, canEdit: canEdit) { fieldID, value in
                                change { try $0.setCustomField(fieldID, value: value) }
                            }
                        }
                        Text("Notiz").font(.title3.bold())
                        RuheCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Was ist dir aufgefallen?").font(.headline)
                                TextEditor(text: Binding(get: { draftNotes }, set: { value in
                                    draftNotes = value
                                    if value != self.walk?.notes || store.pendingNotes[walkID] != nil {
                                        changeNote(value)
                                    }
                                }))
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                                    .accessibilityLabel("Notiz zur Runde")
                                    .accessibilityIdentifier("walk.notes")
                                    .focused($notesFocused)
                                    .disabled(!canEdit)
                                Label("Diktieren mit der iPhone-Tastatur", systemImage: "keyboard")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if walk.route != nil { RouteCard(walk: walk) }
                        if error != nil || store.pendingNotes[walkID] != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Änderung nicht gespeichert", systemImage: "exclamationmark.triangle")
                                Text(error ?? "Die Notiz liegt bisher nur im Arbeitsspeicher. Bitte vor dem Schließen erneut speichern.").font(.footnote)
                                Button("Erneut versuchen") {
                                    if let failedChange { change(failedChange) }
                                    else { change { $0.notes = draftNotes } }
                                }
                            }.foregroundStyle(.red)
                        }
                        Text(error == nil && store.pendingNotes[walkID] == nil ? "Lokal gespeichert · Noch kein Export an Hermes" : "Nicht alle Änderungen gespeichert")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(20)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: canEdit) { _, allowed in
                    if !allowed { notesFocused = false }
                }
                .safeAreaInset(edge: .bottom) {
                    if walk.endedAt == nil {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(spacing: 12))
                            : AnyLayout(HStackLayout(spacing: 12))
                        layout {
                            Button {
                                change { value in
                                    if value.isPaused { try value.resume(at: Date()) }
                                    else { try value.pause(at: Date()) }
                                }
                            } label: {
                                actionLabel(walk.isPaused ? "Fortsetzen" : "Pause", systemImage: walk.isPaused ? "play.fill" : "pause.fill")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.bordered).controlSize(.large)
                            .accessibilityIdentifier(walk.isPaused ? "walk.resume" : "walk.pause")
                            Button { proposal = FinishProposal(date: Date()) } label: {
                                actionLabel("Beenden", systemImage: "stop.fill")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.bordered).tint(.red).controlSize(.large)
                            .accessibilityIdentifier("walk.finish")
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.bar)
                    }
                }
                .sheet(item: $proposal) { proposal in
                    FinishSheet(walk: walk, proposedEnd: proposal.date) { date in
                        try store.update(walkID) { try $0.finish(at: date) }
                        gps.sync()
                    }
                }
                .sheet(isPresented: $editingTimes) {
                    TimeEditSheet(walk: walk) { start, end in
                        try store.update(walkID, confirmingEdit: editConfirmed) { try $0.correctTimes(start: start, end: end) }
                    }
                }
            } else {
                ContentUnavailableView("Runde nicht gefunden", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("Spaziergang")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            draftNotes = store.pendingNotes[walkID] ?? walk?.notes ?? ""
            presentRequestedFinish()
        }
        .onChange(of: finishRequest) { _, _ in presentRequestedFinish() }
        .onDisappear { editConfirmed = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { editConfirmed = false; notesFocused = false }
        }
        .alert("Runde nachträglich bearbeiten?", isPresented: $showingEditConfirmation) {
            Button("Bearbeiten erlauben") { editConfirmed = true }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Du änderst einen abgeschlossenen Eintrag. Änderungen werden direkt gespeichert. Beim Verlassen oder mit „Bearbeitung beenden“ wird die Freigabe aufgehoben.")
        }
        .alert("Änderung nicht gespeichert", isPresented: $showingSaveError) {
            Button("Wiederholen") { if let failedChange { change(failedChange) } }
            Button("Später", role: .cancel) { }
        } message: { Text((error ?? "") + " Die letzte Änderung wurde nicht übernommen.") }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Preserve the complete action title at the user's font size without
            // making the icon compete with "Fortsetzen" for available width.
            Text(title)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    /// Öffnet die vorhandene Abschlussmaske („Runde beenden?“) nur, wenn der Live-Activity-Tipp
    /// sie für genau diese Runde angefordert hat und diese Runde wirklich noch offen ist.
    ///
    /// Eine Anfrage an eine andere Runde wird bewusst NICHT konsumiert: sie bleibt für ihre
    /// eigene Zielrunde stehen. Eine veraltete Anfrage an eine bereits beendete oder fehlende
    /// Runde wird verbraucht, ohne etwas zu öffnen. Beendet wird nichts ohne die Bestätigung.
    private func presentRequestedFinish() {
        guard let request = finishRequest, request.walkID == walkID else { return }
        // Existenz, Offenheit und aktuelle Aktivität werden hier unmittelbar vor der Präsentation
        // erneut geprüft. `walk?.endedAt == nil` allein wäre für eine fehlende Runde fälschlich true.
        if RosieActiveWalkRouting.shouldPresentFinish(
            request,
            for: walkID,
            walkExists: walk != nil,
            isOpen: walk?.endedAt == nil,
            activeWalkID: store.activeWalk?.id
        ) {
            proposal = FinishProposal(date: Date())
        }
        onConsumedFinish(request)
    }

    @ViewBuilder
    private func weatherCard(_ walk: Walk) -> some View {
        RuheCard {
            if let snapshot = walk.weather {
                WeatherSnapshotDetails(kind: .walkStart, snapshot: snapshot)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Wetter beim Start")
                            .accessibilityIdentifier("weather.title")
                    } icon: {
                        Image(systemName: "cloud.sun")
                    }
                    .font(.headline)
                    Text(weather.status(for: walk))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("weather.status")
                }
            }
        }
    }

    private func clockCard(_ walk: Walk, at now: Date, canEdit: Bool) -> some View {
        RuheCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gesamtzeit").font(.subheadline).foregroundStyle(.secondary)
                        Text(durationText(walk.totalDuration(at: now)))
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                            .accessibilityIdentifier("walk.total")
                    }
                    Spacer()
                    Text(walk.endedAt != nil ? "Beendet" : walk.isPaused ? "Pausiert" : "Läuft")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(walk.isPaused ? Color.orange : Color.accentColor)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background((walk.isPaused ? Color.orange : Color.accentColor).opacity(0.1), in: Capsule())
                        .accessibilityIdentifier("walk.state")
                }
                HStack {
                    Text("Start").foregroundStyle(.secondary)
                    Spacer()
                    Text(walk.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .monospacedDigit()
                        .accessibilityIdentifier("walk.startTime")
                }
                .font(.subheadline)
                if let endedAt = walk.endedAt {
                    HStack {
                        Text("Ende").foregroundStyle(.secondary)
                        Spacer()
                        Text(endedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .monospacedDigit()
                            .accessibilityIdentifier("walk.endTime")
                    }
                    .font(.subheadline)
                }
                HStack {
                    Text("Davon Pause: " + durationText(walk.pauseDuration(at: now)))
                        .accessibilityIdentifier("walk.pauseDuration")
                    Spacer()
                    Button("Zeiten", systemImage: "clock") { editingTimes = true }
                        .disabled(!canEdit)
                        .frame(minHeight: 44).accessibilityIdentifier("walk.editTimes")
                }.font(.footnote).foregroundStyle(.secondary)
                if walk.isPaused {
                    Text("Manuelle Pause. Die Gesamtzeit läuft weiter.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<Walk, Value>, in snapshot: Walk) -> Binding<Value> {
        Binding(get: {
            if let current = store.walks.first(where: { $0.id == walkID }) { return current[keyPath: path] }
            return snapshot[keyPath: path]
        }, set: { value in change { $0[keyPath: path] = value } })
    }

    private func changeNote(_ value: String) {
        do {
            try store.updateNotes(walkID, text: value, confirmingEdit: editConfirmed)
            error = nil; failedChange = nil
        } catch {
            self.error = error.localizedDescription
            failedChange = { $0.notes = value }
            showingSaveError = true
        }
    }

    private func change(_ mutation: @escaping (inout Walk) throws -> Void) {
        do {
            try store.update(walkID, confirmingEdit: editConfirmed, change: mutation)
            error = nil; failedChange = nil
        } catch {
            self.error = error.localizedDescription
            failedChange = mutation
            showingSaveError = true
        }
    }
}

private struct FinishSheet: View {
    let walk: Walk
    let proposedEnd: Date
    let confirm: (Date) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Der Endzeitpunkt ist vorgemerkt. Notizen kannst du danach ergänzen, ohne die Runde zu verlängern.")
                    LabeledContent("Endzeit") { Text(proposedEnd, format: .dateTime.hour().minute().second()) }
                    LabeledContent("Gesamtzeit", value: durationText(walk.totalDuration(at: proposedEnd)))
                    LabeledContent("Davon Pause", value: durationText(walk.pauseDuration(at: proposedEnd)))
                }
                Section {
                    Button("Runde beenden") {
                        do { try confirm(proposedEnd); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .font(.headline).accessibilityIdentifier("walk.confirmFinish")
                } footer: { Text("Offene Bewertungen bleiben leer. Nichts wird automatisch bewertet.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Runde beenden?").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.accessibilityIdentifier("walk.cancelFinish")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct TimeEditSheet: View {
    let walk: Walk
    let save: (Date, Date?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?

    init(walk: Walk, save: @escaping (Date, Date?) throws -> Void) {
        self.walk = walk
        self.save = save
        _start = State(initialValue: walk.startedAt)
        _end = State(initialValue: walk.endedAt ?? Date())
    }

    private var isRunning: Bool { walk.endedAt == nil }
    private var correctedEnd: Date? { isRunning ? nil : end }

    #if DEBUG
    private var uiTestWheels: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-store"),
              args.indices.contains(index + 1),
              UUID(uuidString: args[index + 1]) != nil else { return false }
        return true
    }
    #endif

    @ViewBuilder
    private func timePicker(_ title: String, selection: Binding<Date>, identifier: String) -> some View {
        #if DEBUG
        if uiTestWheels {
            DatePicker(title, selection: selection, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .accessibilityIdentifier(identifier)
        } else {
            DatePicker(title, selection: selection, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier(identifier)
        }
        #else
        DatePicker(title, selection: selection, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .accessibilityIdentifier(identifier)
        #endif
    }

    private var preview: Result<Walk, Error> {
        var copy = walk
        do {
            try copy.correctTimes(start: start, end: correctedEnd)
            return .success(copy)
        } catch {
            return .failure(error)
        }
    }

    private var canSave: Bool {
        if case .success = preview { return true }
        return false
    }

    private var displayedError: String? {
        switch preview {
        case .success: return error
        case .failure(let failure): return failure.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    timePicker("Start", selection: $start, identifier: "walk.editStart")
                    if !isRunning {
                        timePicker("Ende", selection: $end, identifier: "walk.editEnd")
                    }
                    if case .success(let corrected) = preview {
                        LabeledContent(
                            "Gesamtzeit",
                            value: durationText(corrected.totalDuration(at: corrected.endedAt ?? Date()))
                        )
                        .accessibilityIdentifier("walk.timePreview")
                    }
                } footer: {
                    Text("Manuelle Pausen bleiben unverändert. Die Zeiten müssen alle Pausen einschließen. GPS-Punkte außerhalb der neuen Zeiten werden beim Speichern entfernt.")
                }
                if let displayedError {
                    Section {
                        Text(displayedError)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("walk.timeError")
                    }
                }
            }
            .navigationTitle("Zeiten korrigieren").navigationBarTitleDisplayMode(.inline)
            .onChange(of: start) { _, _ in error = nil }
            .onChange(of: end) { _, _ in error = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .accessibilityIdentifier("walk.cancelTimes")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do { try save(start, correctedEnd); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("walk.saveTimes")
                }
            }
        }
    }
}
