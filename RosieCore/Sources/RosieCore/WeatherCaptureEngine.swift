import Foundation
import Observation

/// App-lifetime start enrichment. Dependencies run on the main actor, including all privacy gates.
@MainActor @Observable
public final class WeatherCaptureEngine {
    public static let startBudget: Duration = .seconds(30)

    public var consent = false { didSet { if !consent { cancel() } } }
    public private(set) var message = "Wetter deaktiviert"
    public private(set) var walkID: UUID?
    private let store: WalkStore
    private let locate: @MainActor () async -> WeatherCoordinate?
    private let fetch: @MainActor (WeatherCoordinate, WeatherLocationSource) async throws -> WeatherSnapshot
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var deadline: Task<Void, Never>?
    private let timeout: Duration
    private let startWindow: TimeInterval
    private let now: @MainActor () -> Date
    private var localitySamples: [WeatherLocationSample] = []
    private var captureBeganAt: Date?

    public init(store: WalkStore, timeout: Duration = WeatherCaptureEngine.startBudget, now: @escaping @MainActor () -> Date = { Date() }, locate: @escaping @MainActor () async -> WeatherCoordinate?,
                fetch: @escaping @MainActor (WeatherCoordinate, WeatherLocationSource) async throws -> WeatherSnapshot) {
        self.timeout = timeout
        self.startWindow = Self.seconds(timeout)
        self.now = now
        self.store = store; self.locate = locate; self.fetch = fetch
        store.weatherInvalidated = { [weak self] id in
            if self?.walkID == id { self?.cancel() }
        }
    }
    public func capture(_ id: UUID, recordRoute: Bool, home: WeatherCoordinate?) {
        guard store.claimWeatherStart(id) else { return }
        walkID = id
        guard consent else { message = "Wetter deaktiviert · keine Koordinaten übertragen"; return }
        cancel()
        walkID = id
        let request = token
        let beganAt = now()
        captureBeganAt = beganAt
        message = "Wetter wird beim Start geladen …"
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.token == request else { return }
            self.cancel()
            self.message = "Wetter nicht verfügbar · Zeitlimit · Runde läuft weiter"
        }
        task = Task {
            defer { if token == request { deadline?.cancel(); deadline = nil } }
            guard consent, token == request, store.activeWalk?.id == id, !recordRoute || store.canRecordRoute(id) else { return }
            if recordRoute {
                await captureRecordedRoute(id, request: request, beganAt: beganAt, home: home)
            } else {
                await attachResolved(id, request: request, beganAt: beganAt, recordRoute: false, gps: nil, home: home)
            }
        }
    }
    public func cancel() { token = UUID(); task?.cancel(); deadline?.cancel(); deadline = nil; localitySamples = []; captureBeganAt = nil; message = "Kein Wetter · Anfrage beendet" }
    public func wait() async { await task?.value }
    public func noteLocalitySample(_ id: UUID, _ sample: WeatherLocationSample) {
        guard consent, walkID == id, localitySamples.count < 32 else { return }
        guard let beganAt = captureBeganAt,
              WeatherLocalityPolicy.accepts(sample, capturedFrom: beganAt, receivedAt: now()) else { return }
        localitySamples.append(sample)
    }

    private func captureRecordedRoute(_ id: UUID, request: UUID, beganAt: Date, home: WeatherCoordinate?) async {
        let gps = await locate()
        guard consent, token == request, !Task.isCancelled, store.activeWalk?.id == id, store.canRecordRoute(id) else { return }
        guard withinStartWindow(beganAt) else {
            message = "Wetter nicht verfügbar · Start-Zeitfenster abgelaufen · Runde läuft weiter"
            return
        }
        if let choice = resolvedChoice(gps: gps, home: home) {
            await attach(choice, id: id, request: request, beganAt: beganAt, recordRoute: true)
            return
        }
        while consent, token == request, !Task.isCancelled, store.activeWalk?.id == id, store.canRecordRoute(id) {
            guard withinStartWindow(beganAt) else {
                message = "Wetter nicht verfügbar · Start-Zeitfenster abgelaufen · Runde läuft weiter"
                return
            }
            if let choice = resolvedChoice(gps: nil, home: home) {
                await attach(choice, id: id, request: request, beganAt: beganAt, recordRoute: true)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if token == request, !Task.isCancelled {
            message = "Wetter nicht verfügbar · kein verlässlicher Ort · Runde läuft weiter"
        }
    }

    private func attachResolved(_ id: UUID, request: UUID, beganAt: Date, recordRoute: Bool, gps: WeatherCoordinate?,
                                home: WeatherCoordinate?) async {
        guard let choice = WeatherLocationResolver.resolve(recordRoute: recordRoute, gps: gps, home: home) else {
            message = "Wetter nicht verfügbar · kein verlässlicher Ort · Runde läuft weiter"
            return
        }
        await attach(choice, id: id, request: request, beganAt: beganAt, recordRoute: recordRoute)
    }

    private func attach(_ choice: WeatherLocationChoice, id: UUID, request: UUID, beganAt: Date, recordRoute: Bool) async {
        guard consent, !Task.isCancelled, token == request else { return }
        guard store.activeWalk?.id == id, !recordRoute || store.canRecordRoute(id) else { return }
        guard withinStartWindow(beganAt) else {
            message = "Wetter nicht verfügbar · Start-Zeitfenster abgelaufen · Runde läuft weiter"
            return
        }
        do {
            let snapshot = try await fetch(choice.coordinate, choice.source)
            guard consent, !Task.isCancelled, token == request, store.activeWalk?.id == id,
                  !recordRoute || store.canRecordRoute(id), withinStartWindow(beganAt) else { return }
            _ = try store.attachWeather(id, snapshot: snapshot)
            message = "Wetter beim Start · Open-Meteo"
        } catch {
            guard token == request, !Task.isCancelled else { return }
            message = "Wetter nicht erreichbar · Runde läuft weiter. " + error.localizedDescription
        }
    }

    private func resolvedChoice(gps: WeatherCoordinate?, home: WeatherCoordinate?) -> WeatherLocationChoice? {
        WeatherLocationResolver.resolve(recordRoute: true, gps: gps, home: home, localitySamples: evidenceSamples())
    }

    private func evidenceSamples() -> [WeatherLocationSample] {
        let stored = (store.activeWalk?.route?.points ?? []).prefix(8).map {
            WeatherLocationSample(coordinate: WeatherCoordinate(latitude: $0.latitude, longitude: $0.longitude),
                                  accuracy: $0.horizontalAccuracy, timestamp: $0.timestamp)
        }
        return WeatherLocalityPolicy.uniqueObservations(localitySamples + stored)
    }

    private func withinStartWindow(_ beganAt: Date) -> Bool {
        (0...startWindow).contains(now().timeIntervalSince(beganAt))
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
