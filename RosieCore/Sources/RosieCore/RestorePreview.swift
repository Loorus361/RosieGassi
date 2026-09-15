import Foundation

public enum RestoreChoice: String, Sendable, CaseIterable {
    case keepLocal, useBackup
}

public struct RestoreConflict: Identifiable, Sendable {
    public var id: UUID { local.id }
    public let local: Walk
    public let backup: Walk
}

public struct CatalogConflict: Identifiable, Sendable {
    public var id: UUID { fieldID }
    public let fieldID: UUID
    public let local: CustomFieldCatalogEntry
    public let backup: CustomFieldCatalogEntry
}

public struct RestorePreview: Identifiable, Sendable {
    public let id = UUID()
    public let additions: [Walk]
    public let identicalCount: Int
    public let conflicts: [RestoreConflict]
    public let catalogAdditions: [CustomFieldCatalogEntry]
    public let catalogIdenticalCount: Int
    public let catalogConflicts: [CatalogConflict]
    let baseline: [Walk]
    let catalogBaseline: CustomFieldCatalog

    init(local: [Walk], catalog: CustomFieldCatalog, backup: WalkBackup) throws {
        let existing = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        conflicts = backup.walks.compactMap { walk in
            guard let old = existing[walk.id], old != walk else { return nil }
            return RestoreConflict(local: old, backup: walk)
        }
        additions = backup.walks.filter { existing[$0.id] == nil }
        identicalCount = backup.walks.count - additions.count - conflicts.count
        let existingCatalog = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.id, $0) })
        catalogConflicts = backup.fieldCatalog.entries.compactMap { entry in
            guard let old = existingCatalog[entry.id], old != entry else { return nil }
            return CatalogConflict(fieldID: entry.id, local: old, backup: entry)
        }
        catalogAdditions = backup.fieldCatalog.entries.filter { existingCatalog[$0.id] == nil }
        catalogIdenticalCount = backup.fieldCatalog.entries.count - catalogAdditions.count - catalogConflicts.count
        baseline = local
        catalogBaseline = catalog
    }
}

public struct RestoreResult: Sendable {
    public let added: Int
    public let replaced: Int
    public let skipped: Int
}
