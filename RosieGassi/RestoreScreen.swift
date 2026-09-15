import SwiftUI
import RosieCore

struct RestoreScreen: View {
    let store: WalkStore
    let preview: RestorePreview
    let completed: (RestoreResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [UUID: RestoreChoice] = [:]
    @State private var catalogChoices: [UUID: RestoreChoice] = [:]
    @State private var excluded: Set<UUID> = []
    @State private var confirming = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(preview.additions.count) neu · \(preview.identicalCount) identisch · \(preview.conflicts.count) abweichend · \(preview.catalogAdditions.count) neue Felder · \(preview.catalogConflicts.count) abweichende Felder")
                        .accessibilityIdentifier("restore.summary")
                    Text("Noch nichts übernommen. Nicht enthaltene lokale Runden bleiben erhalten. Identische Runden werden nicht doppelt angelegt.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !preview.additions.isEmpty {
                    Section("Neue Runden") {
                        ForEach(preview.additions) { walk in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: Binding(get: { !excluded.contains(walk.id) }, set: { value in
                                    if value { excluded.remove(walk.id) } else { excluded.insert(walk.id) }
                                })) {
                                    Text(walk.startedAt, format: .dateTime.day().month().year().hour().minute())
                                }
                                .accessibilityIdentifier("restore.include.\(walk.id)")
                                DisclosureGroup("Inhalt ansehen") { BackupWalkDetails(walk: walk) }
                                if walk.endedAt == nil {
                                    Text("Offene Runde: wird als \(walk.isPaused ? "pausiert" : "laufend") wiederhergestellt. Die Zeit läuft ab dem ursprünglichen Start weiter.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !preview.conflicts.isEmpty {
                    Section {
                        ForEach(preview.conflicts) { conflict in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(conflict.local.startedAt, format: .dateTime.day().month().year().hour().minute()).font(.headline)
                                if conflict.local.weather != conflict.backup.weather {
                                    Label("Wetter-Snapshot abweichend: Werte, Zeitpunkt oder Wetter-Ort unterscheiden sich. Beide Versionen prüfen.", systemImage: "cloud.sun")
                                        .font(.footnote).accessibilityIdentifier("restore.weatherConflict")
                                }
                                if conflict.local.route != conflict.backup.route {
                                    Label("GPS-Route abweichend: Standortpunkte oder Aufzeichnungsstatus unterscheiden sich. Prüfe beide Versionen vor dem Ersetzen.", systemImage: "location")
                                        .font(.footnote)
                                        .accessibilityIdentifier("restore.routeConflict")
                                }
                            }
                            DisclosureGroup("Auf diesem iPhone") { BackupWalkDetails(walk: conflict.local) }
                            DisclosureGroup("Im Backup") { BackupWalkDetails(walk: conflict.backup) }
                            Picker("Version", selection: Binding<RestoreChoice?>(get: { choices[conflict.id] }, set: { choices[conflict.id] = $0 })) {
                                Text("Bitte wählen").tag(nil as RestoreChoice?)
                                Text("iPhone behalten").tag(RestoreChoice.keepLocal as RestoreChoice?)
                                Text("Backup übernehmen").tag(RestoreChoice.useBackup as RestoreChoice?)
                            }
                            .accessibilityIdentifier("restore.choice")
                        }
                    } header: { Text("Abweichende Versionen") } footer: {
                        Text("‚Backup übernehmen‘ ersetzt die gesamte betreffende Runde, einschließlich Zeiten, Pausen, Bewertungen, Notiz, eigener Felder, Wetter-Snapshot mit Wetter-Ort und GPS-Route. Lokale GPS-Daten werden dabei überschrieben, auch wenn das Backup keine Route enthält. Es gibt keine automatische Bevorzugung einer Version.")
                    }
                }
                if !preview.catalogConflicts.isEmpty {
                    Section {
                        ForEach(preview.catalogConflicts) { conflict in
                            Text(conflict.local.current.name).font(.headline)
                            Text("Lokal: \(conflict.local.current.contractDescription)\(conflict.local.archived ? " · archiviert" : "")")
                                .font(.footnote)
                            Text("Backup: \(conflict.backup.current.contractDescription)\(conflict.backup.archived ? " · archiviert" : "")")
                                .font(.footnote)
                            DisclosureGroup {
                                CatalogEntryDetails(entry: conflict.local)
                            } label: {
                                Text("Lokale Felddefinition")
                            }
                            .accessibilityIdentifier("restore.catalog.local")
                            DisclosureGroup {
                                CatalogEntryDetails(entry: conflict.backup)
                            } label: {
                                Text("Felddefinition im Backup")
                            }
                            .accessibilityIdentifier("restore.catalog.backup")
                            Picker("Feldversion", selection: Binding<RestoreChoice?>(get: { catalogChoices[conflict.id] }, set: { catalogChoices[conflict.id] = $0 })) {
                                Text("Bitte wählen").tag(nil as RestoreChoice?)
                                Text("iPhone behalten").tag(RestoreChoice.keepLocal as RestoreChoice?)
                                Text("Backup übernehmen").tag(RestoreChoice.useBackup as RestoreChoice?)
                            }
                            .accessibilityIdentifier("restore.catalogChoice")
                        }
                    } header: { Text("Abweichende Felder") } footer: {
                        Text("Keine stille Umdeutung. Alte Runden behalten ihre gebundene Definition; die Katalogwahl betrifft künftige Runden und unbenutzte Definitionen.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("restore.error") }
                Section {
                    Text("Wenn zwei offene Runden entstehen würden, wird nichts gespeichert. Wähle dann eine neue offene Runde ab oder beende zuerst die lokale Runde.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Bei wiederhergestellten offenen Runden startet die GPS-Aufzeichnung nicht automatisch. Dafür ist eine erneute ausdrückliche Freigabe erforderlich; gespeicherte Routenpunkte bleiben erhalten.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("restore.gpsSafety")
                }
            }
            .navigationTitle("Backup prüfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.accessibilityIdentifier("restore.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zusammenführen") { confirming = true }
                        .disabled(choices.count != preview.conflicts.count || catalogChoices.count != preview.catalogConflicts.count)
                        .accessibilityIdentifier("restore.merge")
                }
            }
            .confirmationDialog("Auswahl zusammenführen?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Auswahl übernehmen") { apply() }.accessibilityIdentifier("restore.confirm")
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("\(preview.additions.count - excluded.count) neue Runden ergänzen. \(choices.values.filter { $0 == .useBackup }.count) vorhandene Versionen ersetzen, einschließlich ihrer GPS-Daten und Wetter-Snapshots. Andere lokale Runden bleiben erhalten. Die GPS-Aufzeichnung wiederhergestellter offener Runden startet nicht automatisch.")
            }
        }
    }

    private func apply() {
        do {
            let result = try store.restore(preview, choices: choices, excluded: excluded, catalogChoices: catalogChoices)
            completed(result)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private func customFieldText(_ observation: CustomFieldObservation) -> String {
    switch observation.value {
    case .missing: return "Offen"
    case .boolean(true): return "Ja"
    case .boolean(false): return "Nein"
    case .scale(let value), .number(let value):
        let number = DecimalText.displayText(value)
        if let unit = observation.definition.unit, !unit.isEmpty { return number + " " + unit }
        return number
    case .choice(let id):
        return observation.definition.label(for: .choice(id)) ?? "Stufe unbekannt"
    }
}

private struct CatalogEntryDetails: View {
    let entry: CustomFieldCatalogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.archived ? "Status: archiviert" : "Status: aktiv")
            Text("Reihenfolge: \(entry.displayedOrder)")
            ForEach(Array(entry.revisions.enumerated()), id: \.element.revision) { _, definition in
                Text(definition.contractDescription)
            }
        }
        .font(.footnote)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BackupWalkDetails: View {
    let walk: Walk
    @Environment(GPSCoordinator.self) private var gps
    private func instant(_ date: Date?) -> String {
        guard let date else { return "Offen" }
        return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let weather = walk.weather {
                Text("Wetter: " + weather.summary)
                Text("Quelle: \(weather.source) · Ort: \(weather.locationSource == .home ? "Zuhause" : "GPS dieser Runde")")
                Text("Abgerufen: \(instant(weather.fetchedAt))")
                if let coordinate = weather.location {
                    Text("Wetter-Koordinaten: \(String(coordinate.latitude)), \(String(coordinate.longitude))")
                } else { Text("Keine Wetter-Koordinaten gespeichert") }
                if let observed = weather.observedAt { Text("Wetterstand: \(instant(observed))") }
                if let interval = weather.observationIntervalSeconds { Text("Messintervall: \(interval) Sekunden") }
            } else { Text("Kein Wetter-Snapshot gespeichert") }
            Text("Start: \(instant(walk.startedAt))\nEnde: \(instant(walk.endedAt))\nZeitzone: \(walk.timeZoneID)")
            Text("Lahmheit: \(walk.lameness.map { String($0) } ?? "Nicht bewertet")\nMotivation: \(walk.motivation.map { String($0) } ?? "Nicht bewertet")")
            Text("Fahrstuhl: \(walk.elevator?.displayName ?? "Offen") · Flur: \(walk.hallway?.displayName ?? "Offen") · Hof: \(walk.courtyard?.displayName ?? "Offen")")
            ForEach(walk.customFields, id: \.definition.id) { observation in
                Text("\(observation.definition.name) · \(observation.definition.contractDescription): \(customFieldText(observation))")
                    .accessibilityIdentifier("restore.field.\(observation.definition.name)")
            }
            ForEach(Array(walk.pauses.enumerated()), id: \.offset) { _, pause in
                Text("Pause: \(instant(pause.startedAt)) → \(instant(pause.endedAt))")
            }
            Text(walk.notes.isEmpty ? "Keine Notiz" : walk.notes)
            BackupRouteDetails(route: walk.route, profile: gps.routeFilter)
            Text("ID: \(walk.id.uuidString)").font(.caption2).foregroundStyle(.secondary)
        }
        .font(.footnote)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BackupRouteDetails: View {
    let route: WalkRoute?
    let profile: RouteFilterProfile

    private func instant(_ date: Date?) -> String {
        guard let date else { return "Nicht vorhanden" }
        return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    var body: some View {
        if let route {
            VStack(alignment: .leading, spacing: 6) {
                Text("GPS: \(route.points.count) Punkte · \(Set(route.points.map(\.segmentID)).count) Segmente mit Punkten")
                Text("Erster GPS-Punkt: \(instant(route.points.first?.timestamp))\nLetzter GPS-Punkt: \(instant(route.points.last?.timestamp))")
                Text("Geschätzte GPS-Distanz: \(route.estimatedDistanceMeters(profile: profile).map { $0.formatted(.number.precision(.fractionLength(1))) + " m" } ?? "Nicht verfügbar")")
                Text("Aufzeichnung angefordert: \(route.captureRequested ? "Ja" : "Nein") · Erneute Freigabe erforderlich: \(route.requiresCaptureConfirmation == true ? "Ja" : "Nein")")
                Text("Diese Angaben beschreiben den gespeicherten Stand, keine aktuelle Standortfreigabe. Beim Wiederherstellen startet GPS nicht automatisch.")
                    .foregroundStyle(.secondary)
                if !route.points.isEmpty {
                    DisclosureGroup("Private GPS-Punkte ansehen") {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(route.points.enumerated()), id: \.offset) { index, point in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Punkt \(index + 1): \(instant(point.timestamp))")
                                    Text("Breite: \(String(point.latitude)) · Länge: \(String(point.longitude))")
                                    Text("Horizontale Genauigkeit: \(String(point.horizontalAccuracy)) m")
                                    Text("Segment: \(point.segmentID.uuidString)").font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Text("Keine GPS-Route gespeichert")
                .foregroundStyle(.secondary)
        }
    }
}
