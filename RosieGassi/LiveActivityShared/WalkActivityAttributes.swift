import Foundation
import ActivityKit

/// Statische Attribute der Live Activity: nur Identität, nie Nutzdaten.
public struct WalkActivityAttributes: ActivityAttributes {
    public typealias ContentState = LiveActivityContentState

    public var walkID: UUID
    public var sessionID: UUID

    public init(walkID: UUID, sessionID: UUID) {
        self.walkID = walkID
        self.sessionID = sessionID
    }
}

/// Gemeinsamer Darstellungsvertrag zwischen App und Widget-Extension.
///
/// Diese Datei darf ausschließlich abhängigkeitsfrei bleiben (Foundation; in der
/// Extension zusätzlich ActivityKit). Sie enthält bewusst keinen Store-, GPS- oder
/// Persistenzcode. Der Datenvertrag ist in `docs/LIVE-ACTIVITY-DATENVERTRAG.md`
/// festgehalten.
public struct LiveActivityContentState: Codable, Hashable, Sendable {
    // Feldspiegel von `RosieCore.LiveActivityDisplayState`. Die App-Zuordnung
    // (`LiveActivityCoordinator`) setzt jedes Feld explizit, damit ein Auseinanderlaufen
    // sofort einen Übersetzungsfehler erzeugt.
    public var startedAt: Date
    public var endedAt: Date?
    public var isPaused: Bool
    /// Geschätzte Strecke; `nil` = „noch keine Schätzung“/„—“.
    public var estimatedDistanceMeters: Double?
    /// Tatsächlich gespeicherte GPS-Punkte, nicht gefilterte Linienpunkte.
    public var storedPointCount: Int
    public var gpsStatus: String
    public var updatedAt: Date
    public var quickNoteFieldID: UUID?
    public var quickNoteRevision: Int?
    public var quickNoteName: String?
    /// `nil` = unbeantwortet, sonst Ja/Nein.
    public var quickNoteValue: Bool?
    public var quickNoteAvailable: Bool

    public init(
        startedAt: Date,
        endedAt: Date? = nil,
        isPaused: Bool = false,
        estimatedDistanceMeters: Double? = nil,
        storedPointCount: Int = 0,
        gpsStatus: String = "unknown",
        updatedAt: Date,
        quickNoteFieldID: UUID? = nil,
        quickNoteRevision: Int? = nil,
        quickNoteName: String? = nil,
        quickNoteValue: Bool? = nil,
        quickNoteAvailable: Bool = false
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isPaused = isPaused
        self.estimatedDistanceMeters = estimatedDistanceMeters
        self.storedPointCount = storedPointCount
        self.gpsStatus = gpsStatus
        self.updatedAt = updatedAt
        self.quickNoteFieldID = quickNoteFieldID
        self.quickNoteRevision = quickNoteRevision
        self.quickNoteName = quickNoteName
        self.quickNoteValue = quickNoteValue
        self.quickNoteAvailable = quickNoteAvailable
    }
}

/// Kurzer, stabiler Codable-Status der GPS-Aufzeichnung für die Darstellung.
public enum LiveActivityGPSStatusCode {
    public static let off = "off"
    public static let waiting = "waiting"
    public static let recording = "recording"
    public static let denied = "denied"
    public static let interrupted = "interrupted"
    public static let unknown = "unknown"

    public static func displayName(_ raw: String) -> String {
        switch raw {
        case recording: "GPS zeichnet auf"
        case waiting: "GPS wartet"
        case denied: "Kein Standortzugriff"
        case interrupted: "GPS unterbrochen"
        case off: "GPS aus"
        default: "Status offen"
        }
    }
}
