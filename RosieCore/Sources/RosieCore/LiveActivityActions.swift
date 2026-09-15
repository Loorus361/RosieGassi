import Foundation

// MARK: - Anzeigezustand (Feldspiegel des ContentState)

/// Kleiner, stabiler Codable-Status der GPS-Aufzeichnung.
public enum LiveActivityGPSState: String, Codable, Equatable, Sendable {
    case off
    case waiting
    case recording
    case denied
    case interrupted
    case unknown
}

/// Genau die Felder, die die Live Activity darstellen darf. Bewusst gespiegelt im
/// gemeinsamen `WalkActivityAttributes.ContentState` der App/Extension (dort ohne
/// RosieCore-Abhängigkeit). Keine Rohpunkte, keine restlichen Beobachtungen, keine Notizen.
public struct LiveActivityDisplayState: Codable, Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var isPaused: Bool
    /// Geschätzte Strecke; `nil` bedeutet „noch keine Schätzung“, nie erfundene 0 m.
    public var estimatedDistanceMeters: Double?
    /// Tatsächlich gespeicherte GPS-Punkte, nicht gefilterte Linienpunkte.
    public var storedPointCount: Int
    public var gpsStatus: LiveActivityGPSState
    public var updatedAt: Date
    public var quickNoteFieldID: UUID?
    public var quickNoteRevision: Int?
    public var quickNoteName: String?
    /// `nil` = unbeantwortet, sonst Ja/Nein.
    public var quickNoteValue: Bool?
    public var quickNoteAvailable: Bool

    /// Anzeige-Obergrenze für den Feldnamen. Stabile ID/Revision werden nie beschnitten.
    public static let displayNameLimit = 60
    /// Harte Apple-Grenze des gesamten Payloads (statische und dynamische Daten zusammen).
    public static let payloadByteBudget = 4096
    /// Sicherheitsabstand für Attribute und Kodierungsrahmen.
    public static let payloadSafetyMargin = 256

    public init(
        startedAt: Date,
        endedAt: Date? = nil,
        isPaused: Bool = false,
        estimatedDistanceMeters: Double? = nil,
        storedPointCount: Int = 0,
        gpsStatus: LiveActivityGPSState = .unknown,
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

    /// Neutraler Endzustand für verwaiste/unpassende Activities.
    public static func emptyState(now: Date = Date()) -> LiveActivityDisplayState {
        LiveActivityDisplayState(startedAt: now, endedAt: now, gpsStatus: .off, updatedAt: now)
    }

    /// Begrenzt nur die Anzeige; ändert nie die gespeicherte Definition.
    public static func limitedName(_ name: String) -> String {
        name.count <= displayNameLimit ? name : String(name.prefix(displayNameLimit - 1)) + "…"
    }

    public func encodedByteCount() throws -> Int {
        try JSONEncoder().encode(self).count
    }

    /// Überschreitung verhindert die Activity, niemals den Rundenstart.
    public func fitsPayloadBudget() -> Bool {
        guard let size = try? encodedByteCount() else { return false }
        return size <= Self.payloadByteBudget - Self.payloadSafetyMargin
    }
}

// MARK: - Deklarative Befehle

/// Nur diese zwei Befehle existieren. Kein Toggle-, Start-, Ende- oder Löschbefehl.
public enum WalkActivityCommand: Equatable, Sendable {
    case setPaused(walkID: UUID, sessionID: UUID, paused: Bool, at: Date)
    case markQuickNoteYes(walkID: UUID, sessionID: UUID, fieldID: UUID, revision: Int, at: Date)
}

public enum LiveActivityActionError: String, LocalizedError, Equatable, Sendable {
    case noSession
    case sessionMismatch
    case activityNotLive
    case noActiveRound
    case roundCompleted
    case quickNoteUnavailable
    case quickNoteArchived
    case quickNoteKindChanged
    case quickNoteRevisionMismatch
    /// Riegel einer begonnenen Datenersetzung steht: keine Schreibfreigabe, bis die
    /// dauerhafte Invalidierung nachweislich erfolgreich war.
    case dataReplacementPending

    public var errorDescription: String? {
        switch self {
        case .noSession: "Für diese Runde liegt keine sichere Live-Activity-Bindung vor."
        case .sessionMismatch: "Diese Aktion gehört zu einer älteren Runde."
        case .activityNotLive: "Diese Live Activity ist nicht mehr aktiv."
        case .noActiveRound: "Es läuft gerade keine passende Runde."
        case .roundCompleted: "Diese Runde ist bereits abgeschlossen."
        case .quickNoteUnavailable: "Dieser Schnellvermerk gehört nicht zu dieser Runde."
        case .quickNoteArchived: "Dieses Feld wurde archiviert."
        case .quickNoteKindChanged: "Dieses Feld ist kein Ja/Nein-Feld mehr."
        case .quickNoteRevisionMismatch: "Die Felddefinition passt nicht mehr zu dieser Runde."
        case .dataReplacementPending: "Diese Runde wird gerade wiederhergestellt und ist kurz gesperrt."
        }
    }
}

public enum LiveActivityActionResult: Equatable, Sendable {
    /// Änderung bestätigt gespeichert (oder idempotenter No-op).
    case applied
    /// Vertraglich abgelehnt; am bestätigten Datenstand wurde nichts verändert.
    case rejected(LiveActivityActionError)
    /// Speicherfehler; kein Erfolgszustand veröffentlicht.
    case failed
}

// MARK: - Vertragsprüfung vor jedem Schreibzugriff

public enum LiveActivityGate {
    public static func activeSession(_ session: LiveActivitySession?, command: WalkActivityCommand) throws -> LiveActivitySession {
        guard let session else { throw LiveActivityActionError.noSession }
        let walkID: UUID
        let sessionID: UUID
        switch command {
        case .setPaused(let walk, let candidate, _, _):
            walkID = walk
            sessionID = candidate
        case .markQuickNoteYes(let walk, let candidate, _, _, _):
            walkID = walk
            sessionID = candidate
        }
        guard session.walkID == walkID, session.sessionID == sessionID else {
            throw LiveActivityActionError.sessionMismatch
        }
        return session
    }

    /// Activity-State allein ist nie Schreibautorität: es muss eine echt laufende,
    /// zu Sitzung und Runde passende Activity geben.
    public static func validateLiveActivity(session: LiveActivitySession, handles: [LiveActivityHandle]) throws {
        guard let activityID = session.activityID,
              handles.contains(where: { $0.id == activityID && $0.walkID == session.walkID && $0.sessionID == session.sessionID })
        else { throw LiveActivityActionError.activityNotLive }
    }

    public static func activeRound(_ walk: Walk?, walkID: UUID) throws -> Walk {
        guard let walk, walk.id == walkID else { throw LiveActivityActionError.noActiveRound }
        guard walk.endedAt == nil else { throw LiveActivityActionError.roundCompleted }
        return walk
    }

    /// Für den Schnellvermerk: exakt die in Runde UND Katalog vorhandene, historisch
    /// passende Ja/Nein-Revision. Eine neue Ja/Nein-Revision bindet weiter die alte;
    /// Typwechsel, fehlende Historie und Archivierung sperren.
    @discardableResult
    public static func quickNoteDefinition(
        fieldID: UUID,
        revision: Int,
        walk: Walk,
        catalog: CustomFieldCatalog
    ) throws -> CustomFieldDefinition {
        guard let observation = walk.customFields.first(where: { $0.definition.id == fieldID }) else {
            throw LiveActivityActionError.quickNoteUnavailable
        }
        guard observation.definition.kind == .boolean, observation.definition.revision == revision else {
            throw LiveActivityActionError.quickNoteRevisionMismatch
        }
        guard let stored = catalog.definition(id: fieldID, revision: revision), stored == observation.definition else {
            throw LiveActivityActionError.quickNoteRevisionMismatch
        }
        guard let entry = catalog.entry(fieldID), !entry.archived else {
            throw LiveActivityActionError.quickNoteArchived
        }
        guard entry.current.kind == .boolean else {
            throw LiveActivityActionError.quickNoteKindChanged
        }
        return observation.definition
    }

    /// F1: Der Schnellvermerk ist an genau die in der Sitzung eingefrorene Auswahl
    /// gebunden. Fehlende Auswahl, ein anderes Feld und eine abweichende Revision werden
    /// abgelehnt, bevor irgendetwas geschrieben wird. Die zusätzliche Gleichheit der
    /// vollständigen Definition prüft der Aufrufer gegen die eingefrorene Rundendefinition.
    public static func quickNoteBinding(
        session: LiveActivitySession,
        fieldID: UUID,
        revision: Int
    ) throws -> CustomFieldDefinition {
        guard let bound = session.quickNoteDefinition else {
            throw LiveActivityActionError.quickNoteUnavailable
        }
        guard bound.id == fieldID else {
            throw LiveActivityActionError.quickNoteUnavailable
        }
        guard bound.revision == revision else {
            throw LiveActivityActionError.quickNoteRevisionMismatch
        }
        return bound
    }
}

// MARK: - Transport (in der App: ActivityKit; in Tests: Fake)

public struct LiveActivityHandle: Equatable, Sendable {
    public let id: String
    public let walkID: UUID
    public let sessionID: UUID

    public init(id: String, walkID: UUID, sessionID: UUID) {
        self.id = id
        self.walkID = walkID
        self.sessionID = sessionID
    }
}

@MainActor
public protocol LiveActivityTransport: AnyObject {
    var isEnabled: Bool { get }
    func activeHandles() -> [LiveActivityHandle]
    func startActivity(walkID: UUID, sessionID: UUID) throws -> String
    func updateActivity(id: String, state: LiveActivityDisplayState) async
    func endActivity(id: String, state: LiveActivityDisplayState) async
}

// MARK: - Serialisierung und Zusammenfassung der Updates

/// FIFO-Pipeline: höchstens ein Update gleichzeitig unterwegs. Ein neuerer Zustand
/// ersetzt einen noch nicht gesendeten älteren; nach dem Ende wird für dieselbe
/// Activity kein weiteres Update mehr gesendet. Damit kann ein älteres, asynchrones
/// Update nie nach Abschluss oder neuerem Snapshot gewinnen.
@MainActor
public final class LiveActivityUpdatePipeline {
    private let transport: LiveActivityTransport
    private var pending: [(activityID: String, state: LiveActivityDisplayState, isFinal: Bool)] = []
    private var running = false
    /// Beendete Activities: nach dem finalen Ende wird kein weiteres Update mehr gesendet.
    private var finished = Set<String>()
    public private(set) var deliveredCount = 0

    public init(transport: LiveActivityTransport) {
        self.transport = transport
    }

    public var hasPending: Bool { !pending.isEmpty }

    /// FIFO. Ein neuerer Zustand ersetzt den noch nicht gesendeten älteren derselben
    /// Activity; ein finales Ende verdrängt ausstehende Updates dieser Activity und
    /// blockiert danach jedes weitere Update für sie.
    public func enqueue(activityID: String, state: LiveActivityDisplayState, isFinal: Bool) {
        if isFinal { finished.insert(activityID) }
        guard !finished.contains(activityID) || isFinal else { return }
        if isFinal {
            pending.removeAll { $0.activityID == activityID }
            pending.append((activityID, state, true))
        } else if let index = pending.lastIndex(where: { $0.activityID == activityID }) {
            pending[index] = (activityID, state, false)
        } else {
            pending.append((activityID, state, false))
        }
    }

    public func drain() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while !pending.isEmpty {
            let next = pending.removeFirst()
            if next.isFinal {
                await transport.endActivity(id: next.activityID, state: next.state)
            } else {
                await transport.updateActivity(id: next.activityID, state: next.state)
            }
            deliveredCount += 1
        }
    }

    public func reset() {
        pending.removeAll()
    }
}

// MARK: - Orchestrierung

/// Produktionspfad der Live Activity. Alle Fehler der Activity-Schicht bleiben hier
/// gefangen und dürfen Rundenstart, GPS, Speicherung und Abschluss nie blockieren.
@MainActor
public final class LiveActivityOrchestrator {
    /// Technische GPS-Ausgangswerte höchstens alle 10 Sekunden.
    public static let gpsUpdateInterval: TimeInterval = 10

    private let store: WalkStore
    private let transport: LiveActivityTransport
    private let sessionStore: LiveActivitySessionStoring
    private let now: () -> Date
    private let selectionProvider: () -> UUID?
    public let pipeline: LiveActivityUpdatePipeline
    public private(set) var boundSession: LiveActivitySession?

    private var lastGPSSendAt: Date?
    private var pendingState: LiveActivityDisplayState?
    private var pendingActivityID: String?
    /// Zuletzt beobachteter Zustand der Runde, um sofortige von zusammengefassten
    /// Aktualisierungen zu unterscheiden (Pause/Vermerk sofort, GPS gebündelt).
    private var lastObserved: (isPaused: Bool, quickNoteValue: Bool?)?

    public init(
        store: WalkStore,
        transport: LiveActivityTransport,
        sessionStore: LiveActivitySessionStoring,
        now: @escaping () -> Date = Date.init,
        selectionProvider: @escaping () -> UUID? = { nil }
    ) {
        self.store = store
        self.transport = transport
        self.sessionStore = sessionStore
        self.now = now
        self.selectionProvider = selectionProvider
        pipeline = LiveActivityUpdatePipeline(transport: transport)
    }

    // MARK: Anzeigezustand

    public static func displayState(
        walk: Walk,
        session: LiveActivitySession,
        filter: RouteFilterProfile,
        gpsStatus: LiveActivityGPSState,
        now: Date
    ) -> LiveActivityDisplayState {
        let definition = session.quickNoteDefinition
        let observation = definition.flatMap { frozen in
            walk.customFields.first { $0.definition.id == frozen.id }
        }
        var value: Bool?
        if case .boolean(let stored)? = observation?.value { value = stored }
        return LiveActivityDisplayState(
            startedAt: walk.startedAt,
            endedAt: walk.endedAt,
            isPaused: walk.isPaused,
            estimatedDistanceMeters: walk.route?.estimatedDistanceMeters(profile: filter),
            storedPointCount: walk.route?.points.count ?? 0,
            gpsStatus: gpsStatus,
            updatedAt: now,
            quickNoteFieldID: definition?.id,
            quickNoteRevision: definition?.revision,
            quickNoteName: definition.map { LiveActivityDisplayState.limitedName($0.name) },
            quickNoteValue: value,
            quickNoteAvailable: walk.endedAt == nil && definition != nil && observation != nil
        )
    }

    // MARK: Rundenlebenszyklus

    /// Start der Activity erst nach erfolgreicher Sitzungsablage. Jeder Fehler lässt
    /// die Runde gespeichert und benutzbar; ohne dauerhafte Bindung gibt es keine
    /// Schnellaktion.
    public func roundStarted(
        _ walk: Walk,
        selectionFieldID: UUID?,
        filter: RouteFilterProfile,
        gpsStatus: LiveActivityGPSState
    ) {
        guard !sessionStore.isFenced() else { return }
        guard walk.endedAt == nil else { return }
        if let existing = try? sessionStore.load(), existing.walkID == walk.id {
            boundSession = existing
            reconcile(activeWalk: walk, filter: filter, gpsStatus: gpsStatus)
            return
        }
        let definition = LiveActivitySelection.frozenDefinition(
            fieldID: selectionFieldID,
            walk: walk,
            catalog: store.fieldCatalog
        )
        let session = LiveActivitySession(walkID: walk.id, quickNoteDefinition: definition)
        do {
            try sessionStore.save(session)
        } catch {
            boundSession = nil
            return
        }
        boundSession = session
        guard transport.isEnabled else { return }
        let state = Self.displayState(walk: walk, session: session, filter: filter, gpsStatus: gpsStatus, now: now())
        guard state.fitsPayloadBudget() else { return }
        do {
            let activityID = try transport.startActivity(walkID: walk.id, sessionID: session.sessionID)
            var bound = session
            bound.activityID = activityID
            do {
                try sessionStore.save(bound)
                boundSession = bound
            } catch {
                // Ohne dauerhafte Bindung keine Schreibberechtigung: sofort beenden.
                pipeline.enqueue(activityID: activityID, state: state, isFinal: true)
                return
            }
            lastGPSSendAt = now()
            lastObserved = (state.isPaused, state.quickNoteValue)
            pipeline.enqueue(activityID: activityID, state: state, isFinal: false)
        } catch {
            boundSession = session
        }
    }

    /// Laufende Runde aktualisieren. GPS-Werte zusammengefasst; Status, Pause,
    /// Vermerk und Ende sofort.
    public func roundUpdated(
        _ walk: Walk,
        filter: RouteFilterProfile,
        gpsStatus: LiveActivityGPSState,
        immediate: Bool = false
    ) {
        guard !sessionStore.isFenced() else { return }
        guard walk.endedAt == nil else {
            roundFinished(walk, filter: filter, gpsStatus: gpsStatus)
            return
        }
        guard let session = try? sessionStore.load(), session.walkID == walk.id else { return }
        boundSession = session
        guard let activityID = session.activityID else { return }
        let state = Self.displayState(walk: walk, session: session, filter: filter, gpsStatus: gpsStatus, now: now())
        lastObserved = (state.isPaused, state.quickNoteValue)
        let stamp = now()
        if !immediate, let last = lastGPSSendAt, stamp.timeIntervalSince(last) < Self.gpsUpdateInterval {
            pendingState = state
            pendingActivityID = activityID
            return
        }
        deliver(state, activityID: activityID, at: stamp)
    }

    /// Nach erfolgreichem Abschluss: finalen Content mit Endzeit senden, Sitzung beenden.
    /// Betrifft ausschließlich die tatsächlich gebundene Runde; Ereignisse zu einer
    /// historischen Runde (andere Walk-ID) lassen die aktive Bindung unberührt.
    public func roundFinished(_ walk: Walk, filter: RouteFilterProfile, gpsStatus: LiveActivityGPSState) {
        guard !sessionStore.isFenced(),
              let session = try? sessionStore.load(),
              session.walkID == walk.id else { return }
        guard let activityID = session.activityID else {
            invalidateSession()
            return
        }
        let state = Self.displayState(walk: walk, session: session, filter: filter, gpsStatus: gpsStatus, now: now())
        pipeline.enqueue(activityID: activityID, state: state, isFinal: true)
        invalidateSession()
    }

    /// Löschen der gebundenen Runde: Bindung verwerfen, ihre Activity beenden. Nur die
    /// tatsächliche betroffene Walk-ID (die der Sitzung) wird behandelt.
    public func roundRemoved() {
        let session = try? sessionStore.load()
        for handle in transport.activeHandles() where session.map({ $0.walkID == handle.walkID }) ?? true {
            pipeline.enqueue(activityID: handle.id, state: LiveActivityDisplayState.emptyState(now: now()), isFinal: true)
        }
        invalidateSession()
    }

    /// F3: Historische Runde löschen/ersetzen darf die Bindung einer laufenden anderen
    /// Runde nicht entfernen.
    public func roundRemoved(walkID: UUID) {
        guard let session = try? sessionStore.load(), session.walkID == walkID else { return }
        roundRemoved()
    }

    /// Kaltstart/Wiederanbindung. Passt eine Sitzung zu einer echten, laufenden Runde,
    /// wird sie angebunden; alles andere wird beendet. Kein blindes zweites `request`.
    public func reconcile(activeWalk: Walk?, filter: RouteFilterProfile, gpsStatus: LiveActivityGPSState) {
        if sessionStore.isFenced() {
            settleAfterDataReplacement()
            return
        }
        var session = try? sessionStore.load()
        var matched = false
        for handle in transport.activeHandles() {
            if let cached = session,
               let activeWalk,
               activeWalk.endedAt == nil,
               activeWalk.id == handle.walkID,
               cached.walkID == handle.walkID,
               cached.sessionID == handle.sessionID {
                matched = true
                if cached.activityID != handle.id {
                    var rebound = cached
                    rebound.activityID = handle.id
                    try? sessionStore.save(rebound)
                    session = rebound
                }
            } else {
                pipeline.enqueue(activityID: handle.id, state: LiveActivityDisplayState.emptyState(now: now()), isFinal: true)
            }
        }
        if var cached = session, !matched, cached.activityID != nil {
            cached.activityID = nil
            try? sessionStore.save(cached)
            session = cached
        }
        if let cached = session, cached.walkID != activeWalk?.id {
            try? sessionStore.clear()
            session = nil
        }
        boundSession = session
        if matched, let activeWalk {
            roundUpdated(activeWalk, filter: filter, gpsStatus: gpsStatus, immediate: true)
        }
    }

    /// Verspäteten zusammengefassten Zustand nachsenden.
    public func flushPending() {
        guard let state = pendingState, let activityID = pendingActivityID else { return }
        deliver(state, activityID: activityID, at: now())
    }

    // MARK: Schnellaktionen

    public func perform(
        _ command: WalkActivityCommand,
        filter: RouteFilterProfile,
        gpsStatus: LiveActivityGPSState
    ) -> LiveActivityActionResult {
        do {
            // F2: Ein stehender Riegel sperrt jede Aktion, bis die dauerhafte
            // Invalidierung nachweislich abgeschlossen ist.
            guard !sessionStore.isFenced() else { throw LiveActivityActionError.dataReplacementPending }
            let session = try LiveActivityGate.activeSession(try sessionStore.load(), command: command)
            try LiveActivityGate.validateLiveActivity(session: session, handles: transport.activeHandles())
            let walk = try LiveActivityGate.activeRound(store.activeWalk, walkID: session.walkID)
            boundSession = session
            switch command {
            case .setPaused(_, _, let paused, _):
                // F4: Der wirksame Aktionszeitpunkt entsteht im Ausführungspfad
                // (injizierbare Uhr), nicht aus einem in der Oberfläche gerenderten Wert.
                let updated = try store.setPausedFromLiveActivity(walk.id, paused: paused, at: now())
                roundUpdated(updated, filter: filter, gpsStatus: gpsStatus, immediate: true)
                return .applied
            case .markQuickNoteYes(_, _, let fieldID, let revision, _):
                // F1: exakte Bindung an die eingefrorene Auswahl UND an die in der Runde
                // tatsächlich vorhandene, vollständige Definition.
                let bound = try LiveActivityGate.quickNoteBinding(session: session, fieldID: fieldID, revision: revision)
                let frozen = try LiveActivityGate.quickNoteDefinition(
                    fieldID: fieldID,
                    revision: revision,
                    walk: walk,
                    catalog: store.fieldCatalog
                )
                guard frozen == bound else { throw LiveActivityActionError.quickNoteRevisionMismatch }
                let updated = try store.markQuickNoteYesFromLiveActivity(walk.id, fieldID: fieldID)
                roundUpdated(updated, filter: filter, gpsStatus: gpsStatus, immediate: true)
                return .applied
            }
        } catch let error as LiveActivityActionError {
            return .rejected(error)
        } catch {
            return .failed
        }
    }

    // MARK: Ereignisverteilung

    /// Save-Ereignisse des Stores. Wird bewusst nicht nur aus SwiftUI-`onChange`
    /// gespeist, damit Hintergrund-GPS und Intent-Kaltstart ebenfalls reagieren.
    public func handle(_ change: WalkStoreChange, filter: RouteFilterProfile, gpsStatus: LiveActivityGPSState) {
        switch change {
        case .started(let walkID, let isNew):
            guard let walk = store.walks.first(where: { $0.id == walkID }) else { return }
            if isNew {
                roundStarted(walk, selectionFieldID: selectionProvider(), filter: filter, gpsStatus: gpsStatus)
            } else {
                reconcile(activeWalk: walk, filter: filter, gpsStatus: gpsStatus)
            }
        case .updated(let walkID):
            // F3: Nur die tatsächlich gebundene Runde darf Sitzung/Activity verändern.
            // Eine historische Korrektur (andere Walk-ID) lässt die laufende Bindung
            // und ihre Live Activity unberührt.
            guard let session = try? sessionStore.load(), session.walkID == walkID,
                  let walk = store.walks.first(where: { $0.id == walkID }) else { return }
            if walk.endedAt != nil {
                roundFinished(walk, filter: filter, gpsStatus: gpsStatus)
            } else {
                roundUpdated(walk, filter: filter, gpsStatus: gpsStatus, immediate: isImmediateChange(walk))
            }
        case .deleted(let walkID):
            roundRemoved(walkID: walkID)
        case .replaced:
            roundRemoved()
        }
    }

    // MARK: Intern

    /// Pause und Schnellvermerk wirken sofort; reine GPS-Änderungen werden gebündelt.
    private func isImmediateChange(_ walk: Walk) -> Bool {
        guard let last = lastObserved else { return true }
        return last.isPaused != walk.isPaused || last.quickNoteValue != observedQuickNoteValue(walk)
    }

    private func observedQuickNoteValue(_ walk: Walk) -> Bool? {
        guard let fieldID = (try? sessionStore.load())?.quickNoteDefinition?.id else { return nil }
        if case .boolean(let value)? = walk.customFields.first(where: { $0.definition.id == fieldID })?.value { return value }
        return nil
    }

    private func deliver(_ state: LiveActivityDisplayState, activityID: String, at stamp: Date) {
        lastGPSSendAt = stamp
        pendingState = nil
        pendingActivityID = nil
        pipeline.enqueue(activityID: activityID, state: state, isFinal: false)
    }

    private func resetPending() {
        lastGPSSendAt = nil
        pendingState = nil
        pendingActivityID = nil
    }

    /// F2: Sitzung und Crash-Riegel werden nur dann gelöscht, wenn die dauerhafte
    /// Session-Invalidierung nachweislich erfolgreich war. Schlägt das Löschen fehl,
    /// bleibt der Riegel stehen und sperrt jede weitere Schreibaktion.
    private func invalidateSession() {
        do {
            try sessionStore.clear()
            try? sessionStore.clearFence()
        } catch {
            // Riegel und alte Sitzung bleiben bestehen: keine unsichere Freigabe.
        }
        boundSession = nil
        resetPending()
    }

    /// Fenceregel: nach einer Datenersetzung ist jede alte Bindung ungültig.
    private func settleAfterDataReplacement() {
        for handle in transport.activeHandles() {
            pipeline.enqueue(activityID: handle.id, state: LiveActivityDisplayState.emptyState(now: now()), isFinal: true)
        }
        invalidateSession()
    }
}
