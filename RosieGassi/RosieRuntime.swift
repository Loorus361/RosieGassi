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
        if args.contains("--uitest-evaluation-fixture") {
            try seedEvaluationFixture(store: store)
            return
        }
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

    /// Synthetischer Bestand für den schnellen Sichtcheck der Auswertung.
    /// Die Daten werden ausschließlich in dem durch `--uitest-store <UUID>` isolierten Store angelegt.
    private static func seedEvaluationFixture(store: WalkStore) throws {
        guard store.walks.isEmpty else { return }

        let vorigesEssen = try store.createField(name: "Essen vor dem Gassi", kind: .boolean)
        let wasser = try store.createField(name: "Wasser", kind: .number, unit: "ml")
        let ruhigeOption = try CustomFieldOption(label: "ruhig")
        let normaleOption = try CustomFieldOption(label: "normal")
        let aufregendeOption = try CustomFieldOption(label: "aufgeregt")
        let tagesform = try store.createField(
            name: "Tagesform", kind: .graded,
            options: [ruhigeOption, normaleOption, aufregendeOption]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let heute = calendar.startOfDay(for: Date())

        for dayOffset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: heute) else { continue }
            for roundIndex in 0..<3 {
                let startHour = 7 + roundIndex * 5
                guard let start = calendar.date(bySettingHour: startHour, minute: 15 + dayOffset * 3, second: 0, of: day) else { continue }
                let duration = 24 * 60 + Double((dayOffset * 11 + roundIndex * 13) % 25) * 60
                let pauseStart = start.addingTimeInterval(duration * 0.38)
                let pauseEnd = pauseStart.addingTimeInterval(4 * 60 + Double((dayOffset + roundIndex) % 4) * 60)
                let end = start.addingTimeInterval(duration)
                let id = try store.start(at: start)

                try store.update(id, at: end, confirmingEdit: true) {
                    $0.motivation = (dayOffset + roundIndex) % 5 == 0 ? nil : Double(3 + ((dayOffset * 2 + roundIndex) % 5))
                    $0.lameness = (dayOffset + roundIndex) % 4 == 0 ? nil : Double(1 + ((dayOffset + roundIndex * 2) % 5))
                    $0.notes = "Synthetische Vorschau · Runde " + String(roundIndex + 1) + " · Notiz"
                    $0.elevator = roundIndex == 1 ? .hesitant : .ok
                    $0.hallway = dayOffset % 3 == 0 ? .hesitant : .ok
                    $0.courtyard = roundIndex == 2 ? .no : .ok
                    try $0.pause(at: pauseStart)
                    try $0.resume(at: pauseEnd)
                    try $0.setCustomField(vorigesEssen, value: .boolean((dayOffset + roundIndex) % 2 == 0))
                    try $0.setCustomField(wasser, value: .number(120 + Double(dayOffset * 15 + roundIndex * 35)))
                    let option = [ruhigeOption, normaleOption, aufregendeOption][(dayOffset + roundIndex) % 3]
                    try $0.setCustomField(tagesform, value: .choice(option.id))
                    try $0.finish(at: end)
                }
            }
        }
    }
    #endif
}
