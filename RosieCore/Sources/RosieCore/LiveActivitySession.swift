import Foundation

// MARK: - Sitzung

/// App-private Sitzung einer Runde für die Live Activity.
///
/// Kein Bestandteil von Backup, CSV oder SwiftData-Schema: eigener atomarer JSON-Sidecar
/// unter Application Support. Sie ist die einzige Schreibberechtigung für Schnellaktionen
/// aus der Activity heraus; Activity-Attribute allein reichen nie.
public struct LiveActivitySession: Codable, Equatable, Sendable {
    public let walkID: UUID
    public let sessionID: UUID
    /// Beim Rundenstart eingefrorene Definition des Schnellvermerks. `nil` = Keine.
    public var quickNoteDefinition: CustomFieldDefinition?
    /// Gebundene echte Activity-ID. `nil` = keine sichere Bindung (keine Schnellaktion).
    public var activityID: String?

    public init(
        walkID: UUID,
        sessionID: UUID = UUID(),
        quickNoteDefinition: CustomFieldDefinition? = nil,
        activityID: String? = nil
    ) {
        self.walkID = walkID
        self.sessionID = sessionID
        self.quickNoteDefinition = quickNoteDefinition
        self.activityID = activityID
    }
}

// MARK: - Sidecar-Speicher

@MainActor
public protocol LiveActivitySessionStoring: AnyObject {
    func load() throws -> LiveActivitySession?
    func save(_ session: LiveActivitySession) throws
    func clear() throws
    /// Crash-Riegel. Muss dauerhaft geschrieben sein, BEVOR Rundendaten ersetzt werden,
    /// damit ein Absturz zwischen Datenersetzung und Sitzungsaufräumen keine alte
    /// Schreibberechtigung wiederbelebt.
    func setFence() throws
    func clearFence() throws
    func isFenced() -> Bool
}

/// Atomarer JSON-Sidecar. Schreibfehler werden nach oben gemeldet; der Aufrufer
/// lässt die Runde dann ohne sichere Activity-Bindung weiterlaufen.
public final class LiveActivitySessionFileStore: LiveActivitySessionStoring {
    public let directory: URL
    public let sessionURL: URL
    public let fenceURL: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        sessionURL = directory.appending(path: "live-activity-session.json")
        fenceURL = directory.appending(path: "live-activity-session.fence")
    }

    public func load() throws -> LiveActivitySession? {
        guard fileManager.fileExists(atPath: sessionURL.path) else { return nil }
        let data = try Data(contentsOf: sessionURL)
        return try JSONDecoder().decode(LiveActivitySession.self, from: data)
    }

    public func save(_ session: LiveActivitySession) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: sessionURL, options: [.atomic])
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: sessionURL.path) else { return }
        try fileManager.removeItem(at: sessionURL)
    }

    public func setFence() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1]).write(to: fenceURL, options: [.atomic])
    }

    public func clearFence() throws {
        guard fileManager.fileExists(atPath: fenceURL.path) else { return }
        try fileManager.removeItem(at: fenceURL)
    }

    public func isFenced() -> Bool {
        fileManager.fileExists(atPath: fenceURL.path)
    }
}

/// In-Memory-Variante für Tests und isolierte Läufe. Fehler injizierbar.
public final class LiveActivitySessionMemoryStore: LiveActivitySessionStoring {
    public var session: LiveActivitySession?
    public var fenced = false
    public var saveError: Error?
    public var clearError: Error?
    public var fenceError: Error?
    public private(set) var saveCount = 0

    public init(session: LiveActivitySession? = nil) {
        self.session = session
    }

    public func load() throws -> LiveActivitySession? { session }

    public func save(_ session: LiveActivitySession) throws {
        if let saveError { throw saveError }
        saveCount += 1
        self.session = session
    }

    public func clear() throws {
        if let clearError { throw clearError }
        session = nil
    }

    public func setFence() throws {
        if let fenceError { throw fenceError }
        fenced = true
    }

    public func clearFence() throws { fenced = false }

    public func isFenced() -> Bool { fenced }
}

// MARK: - Auswahlvertrag für die nächste Runde

/// Der einzige von den Einstellungen geschriebene Schlüssel. Wert ist ein UUID-String
/// oder fehlt. Die Auswahl ist eine Feld-ID, kein gesetzter Feldwert.
public enum LiveActivitySelection {
    public static let quickNoteFieldDefaultsKey = "liveActivity.quickNoteFieldID"
    /// Debug-Suite der Einstellungs-UI-Tests; enthält keine Produktionsdaten.
    public static let uiTestSuitePrefix = "RosieLiveActivity.UITest."

    public static func uiTestSuiteName(storeID: UUID) -> String {
        uiTestSuitePrefix + storeID.uuidString
    }

    /// Ungültige UUID, unbekanntes oder archiviertes Feld, aktueller Typ ungleich Ja/Nein
    /// oder fehlende Auswahl ergeben „Keine“; niemals eine Ersatzdefinition wählen.
    public static func resolvedDefinition(storedValue: String?, catalog: CustomFieldCatalog) -> CustomFieldDefinition? {
        guard let raw = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let id = UUID(uuidString: raw),
              let entry = catalog.entry(id),
              !entry.archived,
              entry.current.kind == .boolean else { return nil }
        return entry.current
    }

    /// Beim Start einer neuen Runde gilt exakt die in dieser Runde eingefrorene Definition.
    public static func frozenDefinition(fieldID: UUID?, walk: Walk, catalog: CustomFieldCatalog) -> CustomFieldDefinition? {
        guard let fieldID,
              let entry = catalog.entry(fieldID),
              !entry.archived,
              entry.current.kind == .boolean,
              let observation = walk.customFields.first(where: { $0.definition.id == fieldID }),
              observation.definition.kind == .boolean else { return nil }
        return observation.definition
    }
}
