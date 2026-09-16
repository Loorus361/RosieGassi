import SwiftUI
import RosieCore

enum RosieRootTab: Hashable {
    case today, history, evaluation, data, settings
}

struct RootView: View {
    let store: WalkStore
    @Environment(GPSCoordinator.self) private var gps
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RosieRootTab = .today
    /// Aus einem Live-Activity-Tipp übernommene Anfrage: strikt an Ziel-Walk-ID und Absicht
    /// (`open`/`finish`) gebunden. Wird erst beim passenden Verbraucher geleert, damit keine
    /// fremde oder veraltete Runde eine Abschlussmaske erhält.
    @State private var pendingRequest: RosieActiveWalkLink.PendingRequest?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Heute", systemImage: "sun.max", value: RosieRootTab.today) {
                TodayScreen(
                    store: store,
                    selectedTab: selectedTab,
                    requestedWalk: pendingRequest,
                    onConsumedRequest: { request in
                        pendingRequest = RosieActiveWalkRouting.consume(pendingRequest, matching: request)
                    }
                )
            }
            Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: RosieRootTab.history) {
                HistoryScreen(store: store)
            }
            Tab("Auswertung", systemImage: "chart.xyaxis.line", value: RosieRootTab.evaluation) {
                EvaluationScreen(store: store)
            }
            Tab("Daten", systemImage: "externaldrive", value: RosieRootTab.data) {
                DataScreen(store: store)
            }
            Tab("Einstellungen", systemImage: "gearshape", value: RosieRootTab.settings) {
                SettingsScreen(store: store)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onAppear { gps.setForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in gps.setForeground(phase == .active) }
        .onChange(of: store.activeWalk) { _, walk in
            gps.sync()
            // Eine Anfrage, deren Zielrunde nicht mehr aktiv ist, verfällt: keine fremde Runde.
            if let pending = pendingRequest, !RosieActiveWalkRouting.accepts(pending, activeWalkID: walk?.id) {
                pendingRequest = nil
            }
        }
        .onOpenURL { url in handleOpenURL(url) }
    }

    /// Einziger unterstützter Deep Link: `rosiegassi://active-walk/<walkUUID>` (optional
    /// `?action=finish` für die Abschlussmaske).
    ///
    /// Nur die aktive, passende Runde wird geöffnet. Ein stale oder ungültiger Verweis
    /// öffnet höchstens die neutrale Heute-Ansicht: kein Start, keine Mutation, kein
    /// GPS-Consent und keine fremde Runde. `finish` beendet ebenfalls nichts selbst,
    /// sondern öffnet nur die Abschlussmaske zum Bestätigen oder Abbrechen.
    private func handleOpenURL(_ url: URL) {
        selectedTab = .today
        guard let parsed = RosieActiveWalkLink.request(from: url) else {
            pendingRequest = nil
            return
        }
        let request = RosieActiveWalkLink.PendingRequest(parsed)
        // Nur wenn die Zielrunde gerade aktiv ist. Ein fremder/veralteter Link verfällt,
        // ohne eine andere Runde zu öffnen oder zu verändern.
        guard RosieActiveWalkRouting.accepts(request, activeWalkID: store.activeWalk?.id) else {
            pendingRequest = nil
            return
        }
        pendingRequest = request
    }
}

/// Reiner Parser des Live-Activity-Deeplinks: siehe `RosieActiveWalkLink.swift`.

struct TodayScreen: View {
    private enum ConsentPrompt: Identifiable {
        case gps, weather
        var id: Self { self }
    }

    let store: WalkStore
    var selectedTab: RosieRootTab = .today
    /// Von der Live Activity übernommene Anfrage (Ziel-Walk-ID + Absicht); `nil` = keine.
    var requestedWalk: RosieActiveWalkLink.PendingRequest?
    var onConsumedRequest: (RosieActiveWalkLink.PendingRequest) -> Void = { _ in }
    @Environment(GPSCoordinator.self) private var gps
    @Environment(WeatherCoordinator.self) private var weather
    @State private var consentPrompt: ConsentPrompt?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayedWalkID: UUID?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let id = displayedWalkID {
                    WalkScreen(
                        store: store,
                        walkID: id,
                        finishRequest: requestedWalk,
                        onConsumedFinish: onConsumedRequest
                    )
                        // Eigene View-Identität je Runde: Wechselt das Ziel von einer sichtbaren
                        // historischen Runde zur aktiven Runde, wird der WalkScreen neu aufgebaut
                        // und sein `onAppear` wertet die offene Finish-Anfrage erneut aus. Ohne
                        // Identität bliebe `finishRequest` unverändert und der Verbrauch fiele aus.
                        .id(id)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Heute", systemImage: "chevron.left") { displayedWalkID = nil }
                            }
                        }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                                .foregroundStyle(.secondary)
                            RuheCard {
                                VStack(alignment: .leading, spacing: 22) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Spaziergang").font(.headline)
                                            Text(store.activeWalk == nil ? "Noch nicht gestartet" : "Eine Runde ist noch offen")
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    } icon: { SymbolTile(name: "figure.walk") }
                                    Text("Eine Runde.\nIn eurem Tempo.").font(.title2.weight(.semibold))
                                    Text("Zeit festhalten. Beobachten, wie es Rosie unterwegs geht.")
                                        .foregroundStyle(.secondary)
                                    if store.activeWalk == nil {
                                        Toggle("GPS für die nächste Runde", isOn: Binding(
                                            get: { gps.nextWalk },
                                            set: { value in
                                                if value && !gps.consent { consentPrompt = .gps }
                                                else { gps.nextWalk = value }
                                            }))
                                            .accessibilityIdentifier("gps.nextWalk")
                                    } else if store.activeWalk?.route?.requiresCaptureConfirmation == true, !gps.consent {
                                        Button {
                                            consentPrompt = .gps
                                        } label: {
                                            Text("GPS-Routen aktivieren")
                                                .frame(minHeight: 44)
                                        }
                                        .accessibilityIdentifier("gps.restoreConsent")
                                        Text("Danach die Aufzeichnung in der wiederhergestellten Runde gesondert freigeben. Aktivieren allein startet keine Aufnahme.")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Button(action: start) {
                                        Label(store.activeWalk == nil ? "Spaziergang starten" : "Zur laufenden Runde", systemImage: "play.fill")
                                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                                            .frame(maxWidth: .infinity, minHeight: 30)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                                    .accessibilityIdentifier("walk.start")
                                    Label("Offline auf diesem iPhone", systemImage: "checkmark.shield")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            HomeWeatherCard(weather: weather) {
                                consentPrompt = .weather
                            }
                        }
                        .padding(20)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle("Rosie")
                }
            }
            .alert("Runde nicht gestartet", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Erneut versuchen", action: start)
                Button("Abbrechen", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
        .onAppear {
            if displayedWalkID == nil { displayedWalkID = store.activeWalk?.id }
            applyRequestedWalk()
            syncHomePreviewVisibility()
        }
        .onChange(of: requestedWalk) { _, _ in applyRequestedWalk() }
        .onChange(of: displayedWalkID) { _, _ in syncHomePreviewVisibility() }
        .onChange(of: scenePhase) { _, _ in syncHomePreviewVisibility() }
        .onChange(of: selectedTab) { _, _ in syncHomePreviewVisibility() }
        .alert(
            consentPrompt == .weather ? "Wetter aktivieren?" : "GPS-Routen aktivieren?",
            isPresented: Binding(
                get: { consentPrompt != nil },
                set: { if !$0 { consentPrompt = nil } }
            ),
            presenting: consentPrompt
        ) { prompt in
            Button("Aktivieren") {
                switch prompt {
                case .gps: gps.grantConsent()
                case .weather: weather.setConsent(true)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { prompt in
            Text(prompt == .weather
                 ? WeatherConsentCopy.activation
                 : "GPS speichert deine private Route auf diesem iPhone, auch in manuellen Pausen und im Hintergrund bis zum Rundenende. Künftige Runden starten standardmäßig mit GPS; du kannst es vor jeder Runde ausschalten. Standortzugriff wird erst nach dem Start angefragt. Routen können Wohnort und Bewegungsmuster zeigen.")
        }
    }

    private func syncHomePreviewVisibility() {
        let visible = selectedTab == .today && displayedWalkID == nil && scenePhase == .active
        Task { @MainActor in
            weather.setHomePreviewVisible(visible)
        }
    }

    /// Übernimmt eine angeforderte aktive Runde. Öffnet ausschließlich den aktiven,
    /// passenden Walk; sonst bleibt die neutrale Heute-Ansicht stehen.
    ///
    /// `open`-Anfragen sind nach dem Öffnen verbraucht. `finish`-Anfragen verbraucht der
    /// `WalkScreen` selbst, damit die Abschlussmaske garantiert an genau dieser Runde hängt
    /// und nicht an einer zwischenzeitlich dargestellten anderen.
    private func applyRequestedWalk() {
        guard let requested = requestedWalk else { return }
        guard store.activeWalk?.id == requested.walkID else {
            onConsumedRequest(requested)
            return
        }
        displayedWalkID = requested.walkID
        if requested.action == .open { onConsumedRequest(requested) }
    }

    private func start() {
        do {
            let isNew = store.activeWalk == nil
            let requested = gps.consent && gps.nextWalk
            let id = try store.start(recordRoute: requested)
            if isNew {
                gps.started(id, requested: requested)
                weather.capture(for: id, recordRoute: requested)
            }
            displayedWalkID = id; error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

struct HistoryScreen: View {
    let store: WalkStore
    @Environment(GPSCoordinator.self) private var gps
    @State private var pendingDeletion: Walk?
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.walks.isEmpty {
                    ContentUnavailableView("Noch keine Runden", systemImage: "figure.walk", description: Text("Dein erster Spaziergang erscheint hier, sobald du ihn startest."))
                } else {
                    List(store.walks) { walk in
                        NavigationLink(value: walk.id) { WalkRow(walk: walk) }
                            .accessibilityIdentifier("history.walk")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Löschen", systemImage: "trash") { pendingDeletion = walk }
                                    .tint(.red)
                                    .accessibilityIdentifier("history.delete")
                            }
                            .accessibilityAction(named: "Runde löschen") { pendingDeletion = walk }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Verlauf")
            .navigationDestination(for: UUID.self) { id in WalkScreen(store: store, walkID: id) }
            .alert("Runde löschen?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), presenting: pendingDeletion) { walk in
                Button("Löschen", role: .destructive) {
                    do { try store.delete(walk.id); gps.sync() }
                    catch { deletionError = error.localizedDescription }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { walk in
                Text("Die Runde vom \(walk.startedAt.formatted(date: .abbreviated, time: .shortened)) wird mit allen Beobachtungen und Notizen von diesem iPhone gelöscht.\(walk.endedAt == nil ? " Auch die laufende Zeitmessung wird verworfen." : "") Das lässt sich nicht rückgängig machen. Vorhandene Backup-Dateien bleiben unverändert.")
            }
            .alert("Runde nicht gelöscht", isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: { Text(deletionError ?? "") }
        }
    }
}

struct WalkRow: View {
    let walk: Walk
    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(name: "figure.walk")
            VStack(alignment: .leading, spacing: 4) {
                Text(walk.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.headline)
                Text(walk.endedAt == nil ? (walk.isPaused ? "Pausiert" : "Noch unterwegs") : "Abgeschlossen")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let compact = walk.weather?.compactSummary, !compact.isEmpty {
                    Text(compact)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("weather.history.compact")
                }
            }
            Spacer(minLength: 8)
            if let end = walk.endedAt {
                Text(durationText(walk.totalDuration(at: end))).monospacedDigit().font(.subheadline)
            }
        }
    }
}

struct RuheCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SymbolTile: View {
    let name: String
    var body: some View {
        Image(systemName: name).font(.title2).foregroundStyle(Color.accentColor)
            .frame(width: 46, height: 46)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

func durationText(_ interval: TimeInterval) -> String {
    let seconds = Int(max(0, interval))
    if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
