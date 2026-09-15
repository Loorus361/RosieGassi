import Foundation
import RosieCore

/// Präferenz „Schnellvermerk“ der Live Activity.
///
/// Die Einstellungen schreiben und lesen ausschließlich den vereinbarten Schlüssel
/// `liveActivity.quickNoteFieldID`. Gespeichert wird nur eine Feld-ID als UUID-String;
/// ein gesetzter Feldwert oder eine Revision gehört niemals hierher. Ob die gespeicherte
/// Auswahl gilt, entscheidet immer der aktuelle Feldkatalog: unbekannte, archivierte,
/// ungültige oder nicht mehr Ja/Nein-Felder bedeuten „Keine“ – ohne Ersatzdefinition.
///
/// Diese Datei ist bewusst reine Stiftungs-/Kataloglogik ohne SwiftUI und ohne
/// Backend-Interna: Sie nutzt nur den öffentlichen Auswahlvertrag aus `RosieCore` und
/// lässt sich damit isoliert prüfen.
enum QuickNotePreferences {
    /// Der einzige von den Einstellungen geschriebene Schlüssel.
    static let defaultsKey = LiveActivitySelection.quickNoteFieldDefaultsKey

    // MARK: - Ablage

    /// Ablage der App: normal `.standard`, im DEBUG-UI-Test die validierte, isolierte
    /// Suite `RosieLiveActivity.UITest.<UUID>` – exakt derselbe Vertrag wie im Backend
    /// (dort `RosieLiveActivitySettings`), ohne dessen private Typen zu importieren.
    static func preferenceStore(arguments: [String] = ProcessInfo.processInfo.arguments) -> UserDefaults {
        #if DEBUG
        if let id = uiTestStoreID(arguments: arguments),
           let suite = UserDefaults(suiteName: LiveActivitySelection.uiTestSuiteName(storeID: id)) {
            return suite
        }
        #endif
        return .standard
    }

    #if DEBUG
    /// Nur ein valides `--uitest-store <UUID>` wählt die isolierte Testsuite;
    /// jeder andere oder fehlende Wert bleibt bei der normalen App-Ablage.
    static func uiTestStoreID(arguments: [String]) -> UUID? {
        guard let index = arguments.firstIndex(of: "--uitest-store"),
              arguments.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: arguments[index + 1])
    }
    #endif

    // MARK: - Lesen

    /// Roh gespeicherter Wert, unabhängig von seiner Gültigkeit (UUID-String oder `nil`).
    static func storedValue(in store: UserDefaults) -> String? {
        guard let raw = store.string(forKey: defaultsKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Gespeicherte Feld-ID, sofern der Rohwert eine gültige UUID ist.
    static func storedFieldID(in store: UserDefaults) -> UUID? {
        storedValue(in: store).flatMap(UUID.init(uuidString:))
    }

    /// Auswahl, die für die nächste Runde tatsächlich gilt: eine aktive, nicht archivierte
    /// Ja/Nein-Definition aus dem Katalog oder `nil` = Keine.
    static func resolvedDefinition(in store: UserDefaults, catalog: CustomFieldCatalog) -> CustomFieldDefinition? {
        LiveActivitySelection.resolvedDefinition(storedValue: storedValue(in: store), catalog: catalog)
    }

    /// True, wenn etwas gespeichert ist, das aktuell nicht als Auswahl gilt (ungültige UUID,
    /// unbekanntes, archiviertes oder nicht mehr Ja/Nein-Feld). Die Oberfläche erklärt dann
    /// den Rückfall auf „Keine“, statt eine Ersatzdefinition anzubieten.
    static func hasUnavailableSelection(in store: UserDefaults, catalog: CustomFieldCatalog) -> Bool {
        storedValue(in: store) != nil && resolvedDefinition(in: store, catalog: catalog) == nil
    }

    /// Nur aktive, nicht archivierte Ja/Nein-Felder, in Katalogreihenfolge.
    static func selectableFields(in catalog: CustomFieldCatalog) -> [CustomFieldDefinition] {
        catalog.activeDefinitions.filter { $0.kind == .boolean }
    }

    // MARK: - Schreiben

    /// Setzt die Auswahl für die nächste Runde. `nil` entfernt den Schlüssel (= Keine).
    /// Schreibt ausschließlich die Feld-ID und berührt keine laufende Runde.
    static func setSelection(_ id: UUID?, in store: UserDefaults) {
        if let id {
            store.set(id.uuidString, forKey: defaultsKey)
        } else {
            store.removeObject(forKey: defaultsKey)
        }
    }
}
