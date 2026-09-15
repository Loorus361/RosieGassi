import SwiftUI
import CoreLocation
import RosieCore

/// One app-owned provider. Persisted route intent alone never grants sensor access.
@MainActor @Observable
final class GPSCoordinator: NSObject, @preconcurrency CLLocationManagerDelegate {
    let store: WalkStore
    private let preferences: UserDefaults
    private let testMode: String?
    private let isolatedTest: Bool
    private var manager: CLLocationManager?
    private var activeID: UUID?
    private var inhibited = Set<UUID>()
    private var foreground = false
    private var running = false
    private var requestedPermission = false
    private var captureBeganAt = Date()
    private(set) var consent: Bool
    var nextWalk: Bool
    /// Anzeige-Detailstufe der abgeleiteten Route. Persistiert; fehlender Wert = Standard.
    private(set) var routeFilter: RouteFilterProfile
    private(set) var message = "GPS aus"
    private(set) var error: String?
    /// Bestätigter Aufzeichnungsstatus für die Live Activity. Kein Consent-Ersatz und
    /// keine Berechtigungslogik; reine, bereits geprüfte Darstellung.
    private(set) var liveActivityState: LiveActivityGPSState = .off
    var liveActivityObserver: (@MainActor () -> Void)?
    var weatherSampler: (@MainActor (UUID, WeatherLocationSample) -> Void)?

    init(store: WalkStore) {
        self.store = store
        var defaults = UserDefaults.standard
        var mode: String?
        var isolated = false
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--uitest-store"), args.indices.contains(i + 1),
           let id = UUID(uuidString: args[i + 1]) {
            defaults = UserDefaults(suiteName: "RosieGPS.UITest." + id.uuidString)!
            isolated = true
            if let j = args.firstIndex(of: "--uitest-gps"), args.indices.contains(j + 1),
               ["authorized", "denied", "system"].contains(args[j + 1]) { mode = args[j + 1] }
        }
        #endif
        preferences = defaults
        testMode = mode
        isolatedTest = isolated
        consent = defaults.bool(forKey: "gps.consent")
        nextWalk = defaults.bool(forKey: "gps.consent")
        routeFilter = RouteFilterProfile.stored(defaults.string(forKey: "gps.routeFilter"))
        super.init()
    }

    func grantConsent() {
        consent = true; nextWalk = true
        preferences.set(true, forKey: "gps.consent")
    }

    /// Ändert nur die Anzeigeableitung. Gespeicherte Rohpunkte bleiben unverändert;
    /// die Einstellung wirkt dadurch auch auf bereits vorhandene Runden.
    func setRouteFilter(_ profile: RouteFilterProfile) {
        routeFilter = profile
        preferences.set(profile.rawValue, forKey: "gps.routeFilter")
    }

    /// Zurück zum heutigen Verhalten: Schlüssel entfernen, Standard gilt.
    func resetRouteFilter() {
        routeFilter = .standard
        preferences.removeObject(forKey: "gps.routeFilter")
    }

    func started(_ id: UUID, requested: Bool) {
        if requested && consent { preferences.set(id.uuidString, forKey: "gps.ownedWalk") }
        nextWalk = consent
        sync()
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if value { sync() }
    }

    private func eligible(_ id: UUID) -> Bool {
        consent && !inhibited.contains(id) && store.activeWalk?.id == id
            && preferences.string(forKey: "gps.ownedWalk") == id.uuidString
            && store.canRecordRoute(id)
    }

    func sync() {
        guard let id = store.activeWalk?.id, eligible(id) else {
            stopSensor()
            publish(.off)
            return
        }
        if activeID != id {
            stopSensor()
            guard foreground else { return }
            activeID = id
            captureBeganAt = Date()
            publish(.waiting)
        }
        guard foreground || running else { return }
        if testMode == "denied" {
            publish(.denied)
            message = "Standortzugriff verweigert · Runde läuft ohne GPS"
            return
        }
        if testMode == "authorized" {
            if !running { beginCapture(id) }
            return
        }
        // Ordinary UI tests never create a real location provider either.
        guard !isolatedTest || testMode == "system" else {
            publish(.unknown)
            message = "Standortzugriff im UI-Test deaktiviert"
            return
        }
        if manager == nil {
            let provider = CLLocationManager()
            manager = provider
            provider.delegate = self
            provider.desiredAccuracy = kCLLocationAccuracyBest
            provider.distanceFilter = 5
            provider.activityType = .fitness
            provider.allowsBackgroundLocationUpdates = true
            provider.showsBackgroundLocationIndicator = true
            provider.pausesLocationUpdatesAutomatically = false
        }
        guard let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            publish(.waiting)
            message = "Standortzugriff noch nicht erlaubt"
            if foreground && !requestedPermission {
                requestedPermission = true
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            publish(.denied)
            store.weatherInvalidated?(id)
            manager.stopUpdatingLocation(); running = false
            message = "Standortzugriff nicht erlaubt · Runde läuft ohne GPS"
        case .authorizedWhenInUse, .authorizedAlways:
            if !running && foreground { beginCapture(id) }
            if running {
                publish(.recording)
                message = manager.accuracyAuthorization == .reducedAccuracy
                    ? "GPS zeichnet auf · nur ungefährer Standort; Punkte können fehlen"
                    : "GPS zeichnet auf · wartet auf verlässliche Punkte"
            } else {
                publish(.waiting)
            }
        @unknown default:
            publish(.unknown)
            store.weatherInvalidated?(id)
            manager.stopUpdatingLocation(); running = false
            message = "Standortzugriff unbekannt · keine GPS-Aufzeichnung"
        }
    }

    private func publish(_ state: LiveActivityGPSState) {
        guard liveActivityState != state else { return }
        liveActivityState = state
        liveActivityObserver?()
    }

    private func beginCapture(_ id: UUID) {
        guard eligible(id), activeID == id, foreground else { return }
        do {
            try store.beginRouteSegment(id)
            captureBeganAt = Date()
            running = true
            manager?.startUpdatingLocation()
            publish(.recording)
            message = testMode == "authorized" ? "DEMO · GPS zeichnet auf (synthetisch)" : "GPS zeichnet auf · wartet auf verlässliche Punkte"
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func stopSensor() {
        if let activeID { store.weatherInvalidated?(activeID) }
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        activeID = nil
        running = false
        requestedPermission = false
        publish(.off)
    }

    func stopRoute(_ id: UUID) {
        inhibited.insert(id)
        preferences.removeObject(forKey: "gps.ownedWalk")
        stopSensor() // Privacy takes priority even if the following save fails.
        publish(.off)
        message = "GPS beendet · gespeicherte Route bleibt erhalten"
        do { try store.stopRoute(id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func revokeConsent() {
        consent = false; nextWalk = false
        preferences.set(false, forKey: "gps.consent")
        if let id = store.activeWalk?.id, store.activeWalk?.route != nil { stopRoute(id) }
        else { stopSensor() }
        preferences.removeObject(forKey: "gps.ownedWalk")
    }

    func confirmRestored(_ id: UUID) {
        guard consent, foreground, store.activeWalk?.id == id,
              store.activeWalk?.route?.requiresCaptureConfirmation == true else { return }
        do {
            try store.confirmRestoredRoute(id)
            preferences.set(id.uuidString, forKey: "gps.ownedWalk")
            inhibited.remove(id)
            sync()
        } catch { self.error = error.localizedDescription }
    }

    func status(for walk: Walk) -> String {
        if walk.endedAt != nil { return "GPS beendet" }
        if walk.route?.requiresCaptureConfirmation == true { return "Wiederhergestellte Route · GPS wartet auf ausdrückliche Freigabe" }
        if walk.route == nil { return "GPS für diese Runde aus" }
        if !consent || inhibited.contains(walk.id) || walk.route?.captureRequested != true { return "GPS beendet · gespeicherte Route bleibt erhalten" }
        return message
    }

    func canAddTestPoint(_ id: UUID) -> Bool {
        testMode == "authorized" && running && activeID == id && eligible(id)
    }

    func addTestPoint(_ id: UUID) {
        #if DEBUG
        guard canAddTestPoint(id) else { return }
        let count = store.activeWalk?.route?.points.count ?? 0
        append(id, points: [RoutePoint(timestamp: Date(), latitude: 52 + Double(count) * 0.00003,
                                      longitude: 13, horizontalAccuracy: 5)])
        #endif
    }

    private func append(_ id: UUID, points: [RoutePoint]) {
        guard activeID == id, running, eligible(id) else { return }
        do {
            try store.appendRoutePoints(id, points: points.filter { $0.timestamp >= captureBeganAt }, receivedAt: Date())
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager, let id = activeID, eligible(id) else { return }
        sync()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, let id = activeID, eligible(id), running else { return }
        // Authorization can change before its delegate callback clears running.
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            store.weatherInvalidated?(id)
            manager.stopUpdatingLocation(); running = false
            publish(.denied)
            message = "Standortzugriff nicht erlaubt · Runde läuft ohne GPS"
            return
        }
        let points = locations.map {
            RoutePoint(timestamp: $0.timestamp, latitude: $0.coordinate.latitude,
                       longitude: $0.coordinate.longitude, horizontalAccuracy: $0.horizontalAccuracy)
        }
        let receivedAt = Date()
        for point in points {
            let sample = WeatherLocationSample(
                coordinate: WeatherCoordinate(latitude: point.latitude, longitude: point.longitude),
                accuracy: point.horizontalAccuracy,
                timestamp: point.timestamp
            )
            guard WeatherLocalityPolicy.accepts(sample, capturedFrom: captureBeganAt, receivedAt: receivedAt) else { continue }
            weatherSampler?(id, sample)
        }
        append(id, points: points)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager, let id = activeID, eligible(id) else { return }
        publish(.interrupted)
        message = "GPS-Signal unterbrochen · keine verlässlichen Punkte"
        do { try store.beginRouteSegment(id) }
        catch { self.error = error.localizedDescription }
        if (error as? CLError)?.code == .denied {
            store.weatherInvalidated?(id)
            manager.stopUpdatingLocation(); running = false
            publish(.denied)
            message = "Standortzugriff nicht verfügbar · Runde läuft ohne GPS"
        }
    }
}
