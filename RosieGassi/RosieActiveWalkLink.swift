import Foundation

/// Reiner Parser und Erzeuger des Live-Activity-Deeplinks
/// `rosiegassi://active-walk/<walkUUID>` (optional `?action=finish`).
///
/// Muss mit der Erzeugung in der Widget-Extension
/// (`WalkActivityDeepLink.url(walkID:)`/`.finishURL(walkID:)`) übereinstimmen. Bewusst frei von
/// SwiftUI und RosieCore, damit die Regel isoliert prüfbar ist.
enum RosieActiveWalkLink {
    static let scheme = "rosiegassi"
    static let host = "active-walk"
    static let finishAction = "finish"

    /// Was der Tipp ausgelöst hat: `open` öffnet nur die Runde, `finish` zusätzlich die
    /// vorhandene Abschlussmaske („Runde beenden?“) dieser Runde.
    enum Action: Equatable {
        case open, finish
    }

    struct Request: Equatable {
        let walkID: UUID
        let action: Action
    }

    static func url(walkID: UUID, action: Action = .open) -> URL {
        let base = "\(scheme)://\(host)/\(walkID.uuidString)"
        switch action {
        case .open: return URL(string: base)!
        case .finish: return URL(string: "\(base)?action=\(finishAction)")!
        }
    }

    /// Liefert nur bei exakt passendem Schema/Host und gültiger UUID eine Anfrage.
    /// Alles andere (fremder Verweis, fehlende/kaputte Kennung) ist `nil`. Eine unbekannte
    /// Aktion ist bewusst nur `open`: Ein Abschluss entsteht nie ohne ausdrücklichen finish-Verweis.
    static func request(from url: URL) -> Request? {
        guard let walkID = walkID(from: url) else { return nil }
        let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "action" })?
            .value
        return Request(walkID: walkID, action: action == finishAction ? .finish : .open)
    }

    static func walkID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host else { return nil }
        guard let component = url.pathComponents.first(where: { $0 != "/" }),
              let id = UUID(uuidString: component) else { return nil }
        return id
    }

    /// Eine im App-Lebenszyklus verfolgte Anfrage: Zielrunde, Absicht und eine eigene
    /// Identität. Jeder Tipp erzeugt eine neue Identität, damit derselbe Link (z. B. nach
    /// Abbrechen der Abschlussmaske) erneut wirkt und nicht als „unverändert“ verpufft.
    struct PendingRequest: Equatable, Identifiable {
        let id: UUID
        let walkID: UUID
        let action: Action

        init(id: UUID = UUID(), walkID: UUID, action: Action) {
            self.id = id
            self.walkID = walkID
            self.action = action
        }

        init(_ parsed: Request, id: UUID = UUID()) {
            self.init(id: id, walkID: parsed.walkID, action: parsed.action)
        }
    }
}

/// Reine, produktiv genutzte Entscheidungslogik des Verbraucherpfads.
///
/// Die Anfrage bleibt bis zum Verbrauch an ihre Ziel-Walk-ID gebunden. Nur die exakt
/// passende, noch offene Runde darf die Abschlussmaske erhalten; fremde, veraltete oder
/// zwischenzeitlich beendete Runden bleiben unberührt und werden nie mutiert.
enum RosieActiveWalkRouting {
    /// Nimmt eine Anfrage nur an, wenn die aktuell aktive Runde exakt die Zielrunde ist.
    static func accepts(_ request: RosieActiveWalkLink.PendingRequest, activeWalkID: UUID?) -> Bool {
        guard let activeWalkID else { return false }
        return activeWalkID == request.walkID
    }

    /// Diese Ansicht (genau diese Runde) präsentiert nur eine `finish`-Anfrage an genau diese
    /// Runde, wenn sie tatsächlich existiert, noch offen und weiterhin die aktive Runde ist.
    /// Historische, beendete, entfernte oder zwischenzeitlich gewechselte Runden, `open`-Anfragen
    /// und `nil` nie.
    ///
    /// `walkExists` ist Pflicht, weil ein fehlender Walk über `walk?.endedAt == nil` fälschlich als
    /// „offen“ gelten würde; `activeWalkID` wird hier erneut geprüft, damit der Verbraucher sich
    /// nicht auf eine frühere Parent-Entscheidung verlässt.
    static func shouldPresentFinish(
        _ request: RosieActiveWalkLink.PendingRequest?,
        for walkID: UUID,
        walkExists: Bool,
        isOpen: Bool,
        activeWalkID: UUID?
    ) -> Bool {
        guard let request, request.action == .finish, request.walkID == walkID else { return false }
        return walkExists && isOpen && activeWalkID == walkID
    }

    /// Verbraucht ausschließlich die eigene Anfrage. Eine zwischenzeitlich eingetroffene
    /// neuere Anfrage bleibt stehen, damit sie nicht stillschweigend verloren geht.
    static func consume(
        _ pending: RosieActiveWalkLink.PendingRequest?,
        matching current: RosieActiveWalkLink.PendingRequest?
    ) -> RosieActiveWalkLink.PendingRequest? {
        pending == current ? nil : pending
    }
}
