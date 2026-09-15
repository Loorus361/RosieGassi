import SwiftUI
import UniformTypeIdentifiers
import RosieCore

struct TransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalidArchive }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DataScreen: View {
    let store: WalkStore
    @Environment(WeatherCoordinator.self) private var weather
    @State private var document: TransferDocument?
    @State private var exportType: UTType = .json
    @State private var filename = "Rosie-Gassi-Backup"
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmingRouteBackup = false
    @State private var confirmingWeather = false
    @State private var busy = false
    @State private var preview: RestorePreview?
    @State private var error: String?
    @State private var success: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(store.walks.count) Runden auf diesem iPhone", systemImage: "externaldrive")
                    Text("Sichere regelmäßig eine Kopie außerhalb dieser App. Beim Löschen der App können lokale Daten verloren gehen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button(weather.consent ? "Wetter deaktivieren" : "Wetter aktivieren") {
                        if weather.consent { weather.setConsent(false) } else { confirmingWeather = true }
                    }
                    .accessibilityIdentifier("weather.consent")
                    .accessibilityValue(weather.consent ? "1" : "0")
                    if weather.isSynthetic { Text("DEMO · synthetisches Wetter, keine Netzabfrage").font(.caption) }
                    Text("Koordinaten fürs Wetter gehen an Open-Meteo. Ohne Netz bleibt die Runde nutzbar. Snapshot nur beim Start; auf der Startseite aktuelles Wetter fürs gespeicherte Zuhause.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if weather.home == nil {
                        Text("Zuhause ist noch nicht festgelegt.")
                            .accessibilityIdentifier("weather.homeMissing")
                    } else {
                        Text("Zuhause für Wetter ist gespeichert.")
                            .accessibilityIdentifier("weather.homeSet")
                    }
                    Button("Aktuellen Standort als Zuhause speichern") {
                        weather.captureHomeFromCurrentLocation()
                    }
                    .accessibilityIdentifier("weather.setHome")
                    if weather.home != nil {
                        Button("Zuhause entfernen", role: .destructive) { weather.clearHome() }
                            .accessibilityIdentifier("weather.clearHome")
                    }
                    if !weather.homeMessage.isEmpty {
                        Text(weather.homeMessage).font(.footnote).accessibilityIdentifier("weather.homeStatus")
                    }
                    Text("Zuhause speichern bleibt lokal. Die Wetter-Aktivierung erlaubt die Übertragung, wenn die Startseite sichtbar ist, und beim Start künftiger Runden. Ohne GPS wird Zuhause genutzt; bei GPS-Ausfall nicht.").font(.footnote)
                    if weather.consent && !weather.coversHomePreview {
                        Text("Die bisherige Freigabe gilt nur für den Rundenstart. Wetter auf der Startseite braucht eine erneute Bestätigung.")
                            .font(.footnote)
                        Button("Wetter für Zuhause bestätigen") { confirmingWeather = true }
                            .accessibilityIdentifier("weather.home.confirmExpanded")
                    }
                    Text("Wetterdaten: Open-Meteo.com (CC BY 4.0)")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Wetter") }
                Section {
                    Button {
                        if store.walks.contains(where: { $0.route != nil || $0.weather?.location != nil }) {
                            success = nil
                            confirmingRouteBackup = true
                        } else {
                            prepareExport(.backup)
                        }
                    } label: {
                        Label("Backup sichern · JSON", systemImage: "externaldrive.badge.plus")
                    }.accessibilityIdentifier("data.backup")
                    Text("Vollständige Momentaufnahme: Runden, Zeiten, Pausen, Bewertungen, Notizen, eigene Felder samt Katalog, Wetter-Snapshots und alle GPS-Routen einschließlich privater Standortdaten, auch private Start- und Endpunkte. Auch offene Runden bleiben offen. Zum Wiederherstellen geeignet.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("data.backupPrivacy")
                } header: { Text("Sicherung") } footer: {
                    Text("Im Systemdialog wählst du den Speicherort, etwa iCloud Drive oder einen Ordner unter ‚Auf meinem iPhone‘. Keine automatische Synchronisierung.")
                }
                Section {
                    Button { prepareExport(.locationFree) } label: {
                        Label("Ohne Standorte exportieren · JSON", systemImage: "location.slash")
                    }.accessibilityIdentifier("data.locationFreeExport")
                    Text("Lässt alle GPS-Routen und Wetter-Koordinaten weg. Temperatur, Wetterzustand und eigene Feldwerte bleiben. Kein vollständiges Backup und nicht zum Wiederherstellen geeignet. Notizen und Zeitangaben bleiben enthalten; selbst notierte Orte werden nicht entfernt.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("data.locationFreePrivacy")
                    Button { prepareExport(.csv) } label: {
                        Label("Tabelle exportieren · CSV", systemImage: "tablecells")
                    }.accessibilityIdentifier("data.csv")
                    Text("Für Numbers und Hermes, ohne GPS-Koordinaten. Wetterwerte ohne Ort. Fehlende Werte bleiben leer; Gesamtzeit und Pausen bleiben getrennt. Kein vollständiger Ersatz für das JSON-Backup.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { prepareExport(.customFields) } label: {
                        Label("Eigene Felder · CSV", systemImage: "list.bullet.rectangle")
                    }.accessibilityIdentifier("data.customFieldsCsv")
                    Text("Zusätzliche Datei eigene-felder.csv im Langformat: eine Zeile je gebundenes Feld, auch ohne Wert. Der Kern-CSV bleibt unverändert.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Auswertung") }
                Section {
                    Button { success = nil; importing = true } label: {
                        Label("Backup wiederherstellen", systemImage: "arrow.triangle.merge")
                    }.accessibilityIdentifier("data.restore")
                    Text("Zuerst Vorschau, dann Zusammenführen. Identische Runden werden übersprungen; bei abweichenden Versionen entscheidest du. Nicht im Backup enthaltene Runden bleiben erhalten.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Wiederherstellung") } footer: {
                    Text("Nur Rosie-Gassi-JSON-Backups. Kein Import des bisherigen CSV-Tagebuchs. Vor dem Ersetzen einzelner Versionen am besten den aktuellen Stand sichern.")
                }
                if !store.pendingNotes.isEmpty {
                    Section {
                        Label("Ungespeicherte Notizen: Bitte zuerst in der Runde erneut speichern.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                if busy { ProgressView("Datei wird geprüft …") }
                if let success {
                    Section {
                        Label(success, systemImage: "checkmark.circle")
                            .accessibilityIdentifier("data.success")
                    }
                }
                Section {
                    Text("Die Dateien enthalten private Beobachtungen und Zeitangaben und sind nicht zusätzlich verschlüsselt. Teile sie nur bewusst. Eine iCloud-Kopie ist erst nach erfolgreichem Upload auch außerhalb dieses iPhones verfügbar.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(busy)
            .navigationTitle("Daten")
            .alert("Wetter aktivieren?", isPresented: $confirmingWeather) {
                Button("Aktivieren") { weather.setConsent(true) }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(WeatherConsentCopy.activation)
            }
            .alert("Backup mit Standortdaten sichern?", isPresented: $confirmingRouteBackup) {
                Button("Mit Standortdaten sichern") { prepareExport(.backup) }
                    .accessibilityIdentifier("data.confirmRouteBackup")
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Das vollständige Backup enthält Wetter-Koordinaten (auch Zuhause ohne GPS-Route) und alle GPS-Routen mit Koordinaten und Messzeiten, einschließlich privater Start- und Endpunkte. Sichere und teile diese Datei nur bewusst. Für eine Weitergabe ohne GPS-Routen gibt es den separaten Export ‚Ohne Standorte‘; dieser ist kein wiederherstellbares Backup.")
            }

            .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: filename) { result in
                finishExport(result)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                loadImport(result)
            }
            #if DEBUG
            .fileDialogDefaultDirectory(UITestTransferFixtures.directory)
            .task {
                do {
                    if let fixture = try await UITestTransferFixtures.weatherComparison(store: store, weather: weather) { preview = fixture }
                    if let fixture = try UITestTransferFixtures.fieldRestoreComparison(store: store) { preview = fixture }
                }
                catch { self.error = error.localizedDescription }
            }
            #endif
            .sheet(item: $preview) { plan in
                RestoreScreen(store: store, preview: plan) { result in
                    success = "Zusammengeführt: \(result.added) ergänzt, \(result.replaced) ersetzt, \(result.skipped) übersprungen."
                }
            }
            .alert("Vorgang nicht abgeschlossen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private enum ExportKind { case backup, locationFree, csv, customFields }

    private func prepareExport(_ kind: ExportKind) {
        do {
            success = nil
            let data: Data
            let prefix: String
            switch kind {
            case .backup:
                data = try store.backupData()
                prefix = "Backup-"
                exportType = .json
            case .locationFree:
                data = try store.locationFreeExportData()
                prefix = "Ohne-Standorte-"
                exportType = .json
            case .csv:
                data = try store.csvData()
                prefix = "Tabelle-"
                exportType = .commaSeparatedText
            case .customFields:
                data = try store.customFieldCSVData()
                prefix = "eigene-felder-"
                exportType = .commaSeparatedText
            }
            document = TransferDocument(data: data)
            if kind == .customFields {
                filename = "eigene-felder"
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                filename = "Rosie-Gassi-" + prefix + formatter.string(from: Date())
            }
            exporting = true
        } catch { self.error = error.localizedDescription }
    }

    private func finishExport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription }
        case .success(let url):
            guard let expected = document?.data else { return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    let actual = try await Task.detached { try TransferFile.read(url) }.value
                    guard actual == expected else { throw BackupError.invalidArchive }
                    success = "Datei gespeichert und zurückgelesen: \(url.lastPathComponent). Gesichert ist der Stand beim Tippen auf Export."
                } catch {
                    self.error = "iOS hat die Datei abgelegt, aber die Rückleseprüfung war nicht erfolgreich. Bitte die Datei prüfen und gegebenenfalls erneut sichern.\n" + error.localizedDescription
                }
            }
        }
    }

    private func loadImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription }
        case .success(let url):
            busy = true
            Task {
                defer { busy = false }
                do {
                    let data = try await Task.detached { try TransferFile.read(url) }.value
                    preview = try store.previewRestore(data)
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
