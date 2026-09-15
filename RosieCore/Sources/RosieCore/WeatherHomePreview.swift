import Foundation
import Observation

public enum WeatherHomePreviewStatus: Equatable, Sendable {
    case disabled
    case needsExpandedConsent
    case missingHome
    case loading
    case ready
    case unavailable
}

/// Start-screen home weather. Never writes walk snapshots and never locates automatically.
@MainActor @Observable
public final class WeatherHomePreview {
    public var consent = false {
        didSet { if !consent { abortUnauthorized() } }
    }
    public var coversHomePreview = false {
        didSet { if !coversHomePreview { abortUnauthorized() } }
    }
    public private(set) var status: WeatherHomePreviewStatus = .disabled
    public private(set) var snapshot: WeatherSnapshot?
    public private(set) var message = "Wetter ist ausgeschaltet"
    public private(set) var isRefreshing = false
    public private(set) var isCardVisible = false

    private let fetch: @MainActor (WeatherCoordinate, WeatherLocationSource) async throws -> WeatherSnapshot
    private let now: @MainActor () -> Date
    private let maxAge: TimeInterval
    private let timeout: Duration
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var token = UUID()
    private var lastHome: WeatherCoordinate?

    public init(
        timeout: Duration = .seconds(15),
        maxAge: TimeInterval = 15 * 60,
        now: @escaping @MainActor () -> Date = { Date() },
        fetch: @escaping @MainActor (WeatherCoordinate, WeatherLocationSource) async throws -> WeatherSnapshot
    ) {
        self.timeout = timeout
        self.maxAge = maxAge
        self.now = now
        self.fetch = fetch
    }

    public func refresh(home: WeatherCoordinate?, force: Bool = false) {
        lastHome = home
        guard allowsFetch else {
            abortUnauthorized()
            return
        }
        guard let home, home.isValid else {
            cancelWork()
            snapshot = nil
            isRefreshing = false
            status = .missingHome
            message = "Zuhause ist noch nicht festgelegt"
            return
        }
        if !force, let snapshot, snapshot.location == home, now().timeIntervalSince(snapshot.fetchedAt) < maxAge {
            status = .ready
            isRefreshing = false
            message = ""
            return
        }
        guard isCardVisible else { return }
        if snapshot?.location != home {
            snapshot = nil
        }
        startFetch(home: home)
    }

    public func setCardVisible(_ visible: Bool) {
        let becameHidden = isCardVisible && !visible
        isCardVisible = visible
        if visible {
            refresh(home: lastHome)
        } else if becameHidden {
            cancelWork()
        }
    }

    public func cancel() { cancelWork() }
    public func wait() async { await task?.value }

    private var allowsFetch: Bool { consent && coversHomePreview }

    private func abortUnauthorized() {
        cancelWork()
        snapshot = nil
        isRefreshing = false
        publishGate()
    }

    private func publishGate() {
        if !consent {
            status = .disabled
            message = "Wetter ist ausgeschaltet"
        } else if !coversHomePreview {
            status = .needsExpandedConsent
            message = "Wetter vor Runden für Zuhause bestätigen"
        } else if lastHome?.isValid != true {
            status = .missingHome
            message = "Zuhause ist noch nicht festgelegt"
        }
    }

    private func cancelWork() {
        token = UUID()
        task?.cancel()
        deadline?.cancel()
        deadline = nil
        isRefreshing = false
    }

    private func startFetch(home: WeatherCoordinate) {
        cancelWork()
        let request = token
        isRefreshing = true
        if snapshot == nil {
            status = .loading
            message = "Wetter für Zuhause wird geladen …"
        } else {
            status = .ready
            message = "Wird aktualisiert …"
        }
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.token == request else { return }
            self.cancelWork()
            if self.snapshot == nil {
                self.status = .unavailable
            }
            self.message = "Wetter nicht erreichbar · Zeitlimit · später erneut versuchen"
        }
        task = Task {
            defer { if token == request { deadline?.cancel(); deadline = nil; isRefreshing = false } }
            await Task.yield()
            guard allowsFetch, isCardVisible, token == request else { return }
            do {
                let snapshot = try await fetch(home, .home)
                guard allowsFetch, isCardVisible, !Task.isCancelled, token == request else { return }
                try snapshot.validate()
                self.snapshot = snapshot
                status = .ready
                message = ""
            } catch {
                guard token == request, !Task.isCancelled, allowsFetch, isCardVisible else { return }
                if self.snapshot == nil { status = .unavailable }
                message = "Wetter nicht erreichbar · später erneut versuchen. " + error.localizedDescription
            }
        }
    }
}
