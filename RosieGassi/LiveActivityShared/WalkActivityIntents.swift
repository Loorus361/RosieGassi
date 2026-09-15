import Foundation
import AppIntents

/// Genau die zwei deklarativen Befehle, die eine Live Activity auslösen darf.
/// Bewusst ohne Toggle-, Start-, Ende- oder Löschbefehl. Diese Datei bleibt frei von
/// Store-/GPS-Abhängigkeiten; ausgeführt wird ausschließlich im App-Prozess.
public enum WalkActivityRequest: Equatable, Sendable {
    case setPaused(walkID: UUID, sessionID: UUID, paused: Bool, at: Date)
    case markQuickNoteYes(walkID: UUID, sessionID: UUID, fieldID: UUID, revision: Int, at: Date)
}

/// Brücke zwischen Deklaration (hier, auch in der Extension) und Ausführung (App-Prozess).
///
/// Die App-Runtime hängt beim Start genau einen Handler ein. Ist er nicht gesetzt
/// (z. B. Extension-Kontext oder ein Start ohne App-Vorbereitung), ist die Aktion ein
/// stiller No-op — niemals ein ungeprüfter Schreibzugriff.
public enum WalkActivityIntentHandler {
    @MainActor public static var perform: (@MainActor (WalkActivityRequest) async -> Void)?
}

/// Pausieren oder fortsetzen. Ein Tipp öffnet nie einen Dialog und startet nie eine Runde.
/// Der Aktionszeitpunkt wird bewusst NICHT in der Oberfläche gerendert: er entsteht bei
/// der Ausführung im App-Prozess (der Orchestrator stempelt mit seiner injizierbaren Uhr).
@available(iOS 17.0, *)
public struct SetPausedIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Runde pausieren oder fortsetzen"

    @Parameter(title: "Runde")
    public var walkID: String
    @Parameter(title: "Sitzung")
    public var sessionID: String
    @Parameter(title: "Pausiert")
    public var paused: Bool

    public init() {}

    public init(walkID: UUID, sessionID: UUID, paused: Bool) {
        self.walkID = walkID.uuidString
        self.sessionID = sessionID.uuidString
        self.paused = paused
    }

    public func perform() async throws -> some IntentResult {
        guard let walk = UUID(uuidString: walkID), let session = UUID(uuidString: sessionID) else {
            return .result()
        }
        if let handler = await WalkActivityIntentHandler.perform {
            await handler(.setPaused(walkID: walk, sessionID: session, paused: paused, at: Date()))
        }
        return .result()
    }
}

/// Schnellvermerk: setzt ausschließlich Ja. Wiederholte Tipps bleiben idempotent.
@available(iOS 17.0, *)
public struct MarkQuickNoteYesIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Schnellvermerk Ja"

    @Parameter(title: "Runde")
    public var walkID: String
    @Parameter(title: "Sitzung")
    public var sessionID: String
    @Parameter(title: "Feld")
    public var fieldID: String
    @Parameter(title: "Revision")
    public var revision: Int

    public init() {}

    public init(walkID: UUID, sessionID: UUID, fieldID: UUID, revision: Int) {
        self.walkID = walkID.uuidString
        self.sessionID = sessionID.uuidString
        self.fieldID = fieldID.uuidString
        self.revision = revision
    }

    public func perform() async throws -> some IntentResult {
        guard let walk = UUID(uuidString: walkID),
              let session = UUID(uuidString: sessionID),
              let field = UUID(uuidString: fieldID) else {
            return .result()
        }
        if let handler = await WalkActivityIntentHandler.perform {
            await handler(.markQuickNoteYes(walkID: walk, sessionID: session, fieldID: field, revision: revision, at: Date()))
        }
        return .result()
    }
}
