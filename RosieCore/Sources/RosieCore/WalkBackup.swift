import Foundation

public enum BackupError: LocalizedError {
    case invalidArchive, unsupportedVersion, tooLarge, multipleOpenWalks
    case unsavedNotes, unresolvedConflicts, stalePreview

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "Die Datei ist kein vollständiges, gültiges Rosie-Gassi-Backup. Es wurde nichts übernommen."
        case .unsupportedVersion: "Dieses Backup verwendet eine andere Formatversion. Bitte mit einer passenden App-Version öffnen."
        case .tooLarge: "Die Datei überschreitet die Grenze von 25 MiB bzw. 100.000 Runden. Es wurde nichts übernommen."
        case .multipleOpenWalks: "Es würden mehrere offene Runden entstehen. Bitte eine offene Runde abwählen oder die lokale Runde zuerst beenden."
        case .unsavedNotes: "Es gibt noch ungespeicherte Notizen. Bitte diese zuerst in der Runde erneut speichern."
        case .unresolvedConflicts: "Bitte für jede abweichende Runde und jedes abweichende Feld ausdrücklich eine Version wählen."
        case .stalePreview: "Der Datenstand hat sich seit der Vorschau geändert. Bitte das Backup erneut öffnen."
        }
    }
}

public struct WalkBackup: Codable, Sendable {
    public static let maximumBytes = 25 * 1_024 * 1_024
    public let format: String
    public let schemaVersion: Int
    public let dateEncoding: String
    public let exportedAt: Date
    public let walkCount: Int
    public let walks: [Walk]
    public let fieldCatalog: CustomFieldCatalog

    init(format: String, schemaVersion: Int, dateEncoding: String, exportedAt: Date, walkCount: Int, walks: [Walk], fieldCatalog: CustomFieldCatalog) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.dateEncoding = dateEncoding
        self.exportedAt = exportedAt
        self.walkCount = walkCount
        self.walks = walks
        self.fieldCatalog = fieldCatalog
    }

    enum CodingKeys: String, CodingKey {
        case format, schemaVersion, dateEncoding, exportedAt, walkCount, walks, fieldCatalog
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        dateEncoding = try container.decode(String.self, forKey: .dateEncoding)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        walkCount = try container.decode(Int.self, forKey: .walkCount)
        walks = try container.decode([Walk].self, forKey: .walks)
        fieldCatalog = try container.decodeIfPresent(CustomFieldCatalog.self, forKey: .fieldCatalog) ?? .empty
    }

    public static func encode(_ walks: [Walk], catalog: CustomFieldCatalog = .empty, exportedAt: Date = Date()) throws -> Data {
        let backup = WalkBackup(format: "de.carlosanderssohn.RosieGassi.backup", schemaVersion: 3,
                                dateEncoding: "secondsSince2001-01-01T00:00:00Z", exportedAt: exportedAt,
                                walkCount: walks.count, walks: walks, fieldCatalog: catalog)
        try backup.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(backup)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    /// Deliberately NOT a restorable backup. Omits the entire GPS envelope.
    public static func encodeWithoutLocations(_ walks: [Walk], catalog: CustomFieldCatalog = .empty, exportedAt: Date = Date()) throws -> Data {
        try validateWalks(walks, catalog: catalog)
        let redacted = walks.map { walk in
            var copy = walk
            copy.route = nil
            if var weather = copy.weather {
                weather.location = nil
                copy.weather = weather
            }
            return copy
        }
        let export = WalkBackup(format: "de.carlosanderssohn.RosieGassi.location-free-export", schemaVersion: 3,
                                dateEncoding: "secondsSince2001-01-01T00:00:00Z", exportedAt: exportedAt,
                                walkCount: redacted.count, walks: redacted, fieldCatalog: catalog)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(export)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> WalkBackup {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let backup: WalkBackup
        do { backup = try JSONDecoder().decode(WalkBackup.self, from: data) }
        catch { throw BackupError.invalidArchive }
        try backup.validate()
        return backup
    }

    public func validate() throws {
        guard [1, 2, 3].contains(schemaVersion) else { throw BackupError.unsupportedVersion }
        guard format == "de.carlosanderssohn.RosieGassi.backup",
              dateEncoding == "secondsSince2001-01-01T00:00:00Z",
              exportedAt.timeIntervalSinceReferenceDate.isFinite,
              walkCount == walks.count else { throw BackupError.invalidArchive }
        try Self.validateWalks(walks, catalog: fieldCatalog)
    }

    static func validateWalks(_ walks: [Walk], catalog: CustomFieldCatalog? = nil) throws {
        guard walks.count <= 100_000 else { throw BackupError.tooLarge }
        guard Set(walks.map(\.id)).count == walks.count else { throw BackupError.invalidArchive }
        guard walks.filter({ $0.endedAt == nil }).count <= 1 else { throw BackupError.multipleOpenWalks }
        if let catalog {
            do { try catalog.validate() } catch { throw BackupError.invalidArchive }
        }
        for walk in walks {
            guard TimeZone(identifier: walk.timeZoneID) != nil else { throw BackupError.invalidArchive }
            try walk.validate()
            let dates = [walk.startedAt] + [walk.endedAt].compactMap { $0 }
                + walk.pauses.flatMap { [$0.startedAt] + [$0.endedAt].compactMap { $0 } }
            guard dates.allSatisfy({ $0 >= .distantPast && $0 <= .distantFuture }) else { throw BackupError.invalidArchive }
            if let catalog {
                for observation in walk.customFields {
                    do { try catalog.matching(observation) } catch { throw BackupError.invalidArchive }
                }
            }
        }
    }
}
