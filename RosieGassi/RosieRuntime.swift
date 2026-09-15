import SwiftUI
import RosieCore

/// Ein gemeinsamer, lazy erzeugter `@MainActor`-Eigentümer von Store und Coordinatoren.
///
/// UI und Live-Activity-Intents greifen auf genau diese Instanz zu; sie ist bewusst
/// unabhängig von `WindowGroup.task`, damit auch ein Intent-Kaltstart ohne sichtbare UI
/// denselben bestätigten Datenstand benutzt.
@MainActor
final class RosieRuntime {
    let store: WalkStore
    let gps: GPSCoordinator
    let weather: WeatherCoordinator
    let liveActivity: LiveActivityCoordinator

    private static var cached: RosieRuntime?

    static func shared() throws -> RosieRuntime {
        if let cached { return cached }
        let runtime = try RosieRuntime()
        cached = runtime
        return runtime
    }

    private init() throws {
        var url: URL?
        #if DEBUG
        if let id = RosieLiveActivitySessionStore.uiTestStoreID() {
            let folder = URL.applicationSupportDirectory.appending(path: "UITestStores", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = folder.appending(path: id.uuidString + ".store")
        }
        #endif
        let store = try WalkStore(container: WalkStore.makeContainer(url: url))
        #if DEBUG
        try UITestTransferFixtures.prepare()
        try RosieRuntime.seedUITestData(store: store, isolated: url != nil)
        #endif
        let gps = GPSCoordinator(store: store)
        let weather = WeatherCoordinator(store: store)
        gps.weatherSampler = { [weak weather] id, sample in
            weather?.engine.noteLocalitySample(id, sample)
        }
        self.store = store
        self.gps = gps
        self.weather = weather
        self.liveActivity = LiveActivityCoordinator(store: store, gps: gps)
    }

    #if DEBUG
    /// Nur für isolierte UI-Test-Stores. Keine Wirkung auf Carlos' echten Datenstand.
    private static func seedUITestData(store: WalkStore, isolated: Bool) throws {
        guard isolated else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitest-seed-boolean-field"), store.fieldCatalog.entries.isEmpty {
            _ = try store.createField(name: "Husten", kind: .boolean)
        }
        guard store.walks.isEmpty else { return }
        if args.contains("--uitest-protected-round") || args.contains("--uitest-expiring-round") {
            let end = Date().addingTimeInterval(args.contains("--uitest-expiring-round") ? -270 : -600)
            let id = try store.start(at: end.addingTimeInterval(-60))
            try store.update(id) { try $0.finish(at: end) }
        } else if args.contains("--uitest-midnight-round") {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
            let startOfToday = calendar.startOfDay(for: Date())
            let id = try store.start(at: startOfToday.addingTimeInterval(-10 * 60))
            try store.update(id) { try $0.finish(at: startOfToday.addingTimeInterval(10 * 60)) }
        } else if args.contains("--uitest-time-correction-round") {
            let end = Date().addingTimeInterval(-3600)
            let id = try store.start(at: end.addingTimeInterval(-3600))
            try store.update(id) { try $0.finish(at: end) }
        }
    }
    #endif
}
