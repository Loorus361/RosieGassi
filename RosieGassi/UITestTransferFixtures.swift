#if DEBUG
import Foundation
import RosieCore

// Never runs for the normal store. Test fixtures live only in this app's sandbox.
enum UITestTransferFixtures {
    static var directory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitest-backup-fixtures"),
              let index = args.firstIndex(of: "--uitest-store"), args.indices.contains(index + 1),
              let id = UUID(uuidString: args[index + 1]) else { return nil }
        return URL.documentsDirectory.appending(path: "UITest-Transfer", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    @MainActor
    static func weatherComparison(store: WalkStore, weather: WeatherCoordinator) async throws -> RestorePreview? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitest-weather-comparison"),
              let index = args.firstIndex(of: "--uitest-store"), args.indices.contains(index + 1),
              UUID(uuidString: args[index + 1]) != nil else { return nil }
        if store.walks.isEmpty {
            let id = try store.start()
            weather.setConsent(true)
            weather.engine.capture(id, recordRoute: false, home: WeatherCoordinate(latitude: 52, longitude: 13))
            await weather.engine.wait()
        }
        var object = try JSONSerialization.jsonObject(with: store.backupData()) as! [String: Any]
        var walks = object["walks"] as! [[String: Any]]
        var weather = walks[0]["weather"] as! [String: Any]
        weather["location"] = ["latitude": 53.0, "longitude": 14.0]
        walks[0]["weather"] = weather
        object["walks"] = walks
        return try store.previewRestore(JSONSerialization.data(withJSONObject: object))
    }

    @MainActor
    static func fieldRestoreComparison(store: WalkStore) throws -> RestorePreview? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitest-field-restore-comparison"),
              let index = args.firstIndex(of: "--uitest-store"), args.indices.contains(index + 1),
              UUID(uuidString: args[index + 1]) != nil else { return nil }
        if store.fieldCatalog.entries.isEmpty && store.walks.isEmpty {
            let wasser = try store.createField(name: "Wasser", kind: .number, unit: "ml")
            let schmerz = try store.createField(
                name: "Schmerz", kind: .scale, scaleMin: 1, scaleMax: 7, scaleStep: 0.5
            )
            try store.archiveField(wasser)
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let id = try store.start(at: start)
            try store.update(id) {
                try $0.setCustomField(schmerz, value: .scale(2))
                try $0.finish(at: start.addingTimeInterval(30))
            }
        }
        guard let wasser = store.fieldCatalog.entries.first(where: { $0.current.name == "Wasser" }),
              let schmerz = store.fieldCatalog.entries.first(where: { $0.current.name == "Schmerz" }),
              var walk = store.walks.first else { return nil }
        var incoming = CustomFieldCatalog.empty
        try incoming.insert(try CustomFieldDefinition.make(
            id: wasser.id, name: "Wasser", kind: .number, unit: "l"
        ))
        try incoming.insert(schmerz.current)
        try walk.setCustomField(schmerz.id, value: .scale(3))
        return try store.previewRestore(WalkBackup.encode([walk], catalog: incoming, exportedAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    static func prepare() throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "UITest-Backup.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        if ProcessInfo.processInfo.arguments.contains("--uitest-gps-restore-fixture") {
            // A real backup, imported through Files/preview/merge by GPSRestoreFlowTests.
            // No local GPS preference is changed; restore must disarm capture itself.
            var walk = Walk(startedAt: Date().addingTimeInterval(-120),
                            timeZoneID: "Europe/Berlin", recordRoute: true)
            walk.notes = "DEMO · synthetische offene GPS-Runde zur Wiederherstellung"
            try WalkBackup.encode([walk]).write(to: url, options: .atomic)
            return
        }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var walk = Walk(startedAt: start, timeZoneID: "Europe/Berlin")
        walk.notes = "Synthetisches Backup 🐾"
        walk.lameness = 3.27
        walk.elevator = nil
        try walk.pause(at: start.addingTimeInterval(10))
        try walk.resume(at: start.addingTimeInterval(20))
        try walk.finish(at: start.addingTimeInterval(120))
        try WalkBackup.encode([walk]).write(to: url, options: .atomic)
    }
}
#endif
