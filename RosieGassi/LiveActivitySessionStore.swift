import Foundation
import RosieCore

/// App-privater Sidecar-Ort der Live-Activity-Sitzung.
///
/// Normale App: eigener Ordner unter Application Support (nicht im Gesundheits-Backup,
/// kein App-Group-Container, keine SwiftData-/CSV-Änderung). Debug-UI-Tests laufen in
/// einem isolierten Ordner je `--uitest-store <UUID>`.
@MainActor
enum RosieLiveActivitySessionStore {
    static func make() -> LiveActivitySessionFileStore {
        LiveActivitySessionFileStore(directory: directory())
    }

    static func directory() -> URL {
        #if DEBUG
        if let id = uiTestStoreID() {
            return URL.applicationSupportDirectory
                .appending(path: "UITestStores", directoryHint: .isDirectory)
                .appending(path: "LiveActivity-" + id.uuidString, directoryHint: .isDirectory)
        }
        #endif
        return URL.applicationSupportDirectory
            .appending(path: "LiveActivity", directoryHint: .isDirectory)
    }

    #if DEBUG
    static func uiTestStoreID() -> UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--uitest-store"),
              args.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: args[index + 1])
    }
    #endif
}

/// Auswahlpräferenz für die nächste Runde. Liest ausschließlich den vereinbarten Key.
@MainActor
enum RosieLiveActivitySettings {
    static var defaults: UserDefaults {
        #if DEBUG
        if let id = RosieLiveActivitySessionStore.uiTestStoreID(),
           let isolated = UserDefaults(suiteName: LiveActivitySelection.uiTestSuiteName(storeID: id)) {
            return isolated
        }
        #endif
        return .standard
    }

    /// Roh gelesene Feld-ID der nächsten Runde. Die inhaltliche Prüfung gegen den
    /// Feldkatalog übernimmt der Orchestrator beim Start der neuen Runde.
    static func selectedFieldID() -> UUID? {
        guard let raw = defaults.string(forKey: LiveActivitySelection.quickNoteFieldDefaultsKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }
}
