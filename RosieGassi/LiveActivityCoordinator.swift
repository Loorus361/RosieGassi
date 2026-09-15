@preconcurrency import ActivityKit
import Foundation
import RosieCore
import UIKit

/// ActivityKit-Adapter. Jeder Aufruf ist gegen einen fehlenden/beendeten Handle
/// abgesichert; ein Fehler der Activity-Schicht wird nie weitergereicht und kann
/// Rundenstart, GPS, Speicherung oder Abschluss nicht blockieren.
@MainActor
final class ActivityKitTransport: LiveActivityTransport {
    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func activeHandles() -> [LiveActivityHandle] {
        Activity<WalkActivityAttributes>.activities.map {
            LiveActivityHandle(id: $0.id, walkID: $0.attributes.walkID, sessionID: $0.attributes.sessionID)
        }
    }

    func startActivity(walkID: UUID, sessionID: UUID) throws -> String {
        let attributes = WalkActivityAttributes(walkID: walkID, sessionID: sessionID)
        let now = Date()
        let content = ActivityContent(
            state: LiveActivityContentState(startedAt: now, updatedAt: now),
            staleDate: nil
        )
        let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return activity.id
    }

    func updateActivity(id: String, state: LiveActivityDisplayState) async {
        guard let activity = activity(for: id) else { return }
        let content = ActivityContent(
            state: LiveActivityContentState(state),
            // Veraltet-Kennzeichnung 60 s nach dem letzten bestätigten Stand.
            staleDate: state.updatedAt.addingTimeInterval(60)
        )
        await activity.update(content)
    }

    func endActivity(id: String, state: LiveActivityDisplayState) async {
        guard let activity = activity(for: id) else { return }
        let content = ActivityContent(state: LiveActivityContentState(state), staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
    }

    private func activity(for id: String) -> Activity<WalkActivityAttributes>? {
        Activity<WalkActivityAttributes>.activities.first { $0.id == id }
    }
}

extension LiveActivityContentState {
    /// Explizite, vollständige Zuordnung aus dem Core-Anzeigezustand. Weil jedes Feld
    /// einzeln gesetzt wird, erzeugt ein neues oder fehlendes Feld auf einer der beiden
    /// Seiten sofort einen Übersetzungsfehler.
    init(_ state: LiveActivityDisplayState) {
        self.init(
            startedAt: state.startedAt,
            endedAt: state.endedAt,
            isPaused: state.isPaused,
            estimatedDistanceMeters: state.estimatedDistanceMeters,
            storedPointCount: state.storedPointCount,
            gpsStatus: state.gpsStatus.rawValue,
            updatedAt: state.updatedAt,
            quickNoteFieldID: state.quickNoteFieldID,
            quickNoteRevision: state.quickNoteRevision,
            quickNoteName: state.quickNoteName,
            quickNoteValue: state.quickNoteValue,
            quickNoteAvailable: state.quickNoteAvailable
        )
    }
}

/// App-langlebige Orchestrierung der Live Activity. Reagiert auf bestätigte
/// Store-Speicherungen (nicht nur auf SwiftUI-`onChange`), damit auch Hintergrund-GPS und
/// Intent-Kaltstart funktionieren.
@MainActor
final class LiveActivityCoordinator {
    private let store: WalkStore
    private let gps: GPSCoordinator
    private let sessions: LiveActivitySessionFileStore
    private let transport: ActivityKitTransport
    private let orchestrator: LiveActivityOrchestrator
    private var observers: [NSObjectProtocol] = []

    init(store: WalkStore, gps: GPSCoordinator) {
        let sessionStore = RosieLiveActivitySessionStore.make()
        let transport = ActivityKitTransport()
        self.store = store
        self.gps = gps
        self.sessions = sessionStore
        self.transport = transport
        self.orchestrator = LiveActivityOrchestrator(
            store: store,
            transport: transport,
            sessionStore: sessionStore,
            selectionProvider: { RosieLiveActivitySettings.selectedFieldID() }
        )

        // F2: Derselbe Sidecar setzt vor jeder Datenersetzung den Crash-Riegel, den der
        // Orchestrator vor jeder Aktion prüft. `sessions` hält keinen Store-Verweis,
        // daher kein Zyklus.
        let sessions = sessionStore
        store.liveActivityFence = { try sessions.setFence() }

        store.changeObserver = { [weak self] change in self?.handle(change) }
        gps.liveActivityObserver = { [weak self] in self?.refreshFromGPSStatus() }

        // Kaltstart vor der UI: abgleichen, nicht blind neu anfordern.
        orchestrator.reconcile(
            activeWalk: store.activeWalk,
            filter: gps.routeFilter,
            gpsStatus: gps.liveActivityState
        )
        drain()

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileAndFlush() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.orchestrator.flushPending(); self?.drain() }
        })
    }

    /// Führt einen Live-Activity-Befehl aus. Es gibt keinen Weg, über den ein Fehler
    /// der Activity-Schicht den bestätigten Datenstand beschädigen könnte.
    func perform(_ request: WalkActivityRequest) async {
        let command: WalkActivityCommand
        switch request {
        case .setPaused(let walkID, let sessionID, let paused, let at):
            command = .setPaused(walkID: walkID, sessionID: sessionID, paused: paused, at: at)
        case .markQuickNoteYes(let walkID, let sessionID, let fieldID, let revision, let at):
            command = .markQuickNoteYes(walkID: walkID, sessionID: sessionID, fieldID: fieldID, revision: revision, at: at)
        }
        _ = orchestrator.perform(command, filter: gps.routeFilter, gpsStatus: gps.liveActivityState)
        await orchestrator.pipeline.drain()
    }

    private func handle(_ change: WalkStoreChange) {
        orchestrator.handle(change, filter: gps.routeFilter, gpsStatus: gps.liveActivityState)
        drain()
    }

    private func refreshFromGPSStatus() {
        guard let walk = store.activeWalk else { return }
        orchestrator.roundUpdated(walk, filter: gps.routeFilter, gpsStatus: gps.liveActivityState, immediate: true)
        drain()
    }

    private func reconcileAndFlush() {
        orchestrator.flushPending()
        orchestrator.reconcile(
            activeWalk: store.activeWalk,
            filter: gps.routeFilter,
            gpsStatus: gps.liveActivityState
        )
        drain()
    }

    private func drain() {
        Task { await orchestrator.pipeline.drain() }
    }
}
