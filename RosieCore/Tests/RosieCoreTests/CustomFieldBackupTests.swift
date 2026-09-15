import XCTest
@testable import RosieCore

@MainActor
final class CustomFieldBackupTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testSchemaThreeRoundTripKeepsUnusedArchivedAndOldBackupsWithoutFields() async throws {
        let store = try WalkStore(container: WalkStore.makeContainer(inMemory: true))
        let used = try store.createField(name: "Husten", kind: .boolean)
        let unused = try store.createField(name: "Wasser", kind: .number, unit: "ml")
        try store.archiveField(unused)
        let id = try store.start(at: origin)
        try store.update(id) { try $0.setCustomField(used, value: .boolean(false)) }
        let data = try store.backupData()
        let backup = try WalkBackup.decode(data)
        XCTAssertEqual(backup.schemaVersion, 3)
        XCTAssertEqual(backup.fieldCatalog.entries.count, 2)
        XCTAssertEqual(backup.fieldCatalog.entry(unused)?.archived, true)
        XCTAssertEqual(backup.walks[0].customFields[0].value, .boolean(false))
        XCTAssertNil(backup.walks[0].customFields.first { $0.definition.id == unused })

        let locationFree = try store.locationFreeExportData()
        XCTAssertTrue(String(decoding: locationFree, as: UTF8.self).contains("jaNein"))
        XCTAssertThrowsError(try WalkBackup.decode(locationFree))

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy["schemaVersion"] = 1
        legacy.removeValue(forKey: "fieldCatalog")
        var oldWalk = try XCTUnwrap((legacy["walks"] as? [[String: Any]])?.first)
        oldWalk.removeValue(forKey: "customFields")
        legacy["walks"] = [oldWalk]
        let decodedLegacy = try WalkBackup.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decodedLegacy.schemaVersion, 1)
        XCTAssertTrue(decodedLegacy.fieldCatalog.entries.isEmpty)
        XCTAssertTrue(decodedLegacy.walks[0].customFields.isEmpty)

        let target = try WalkStore(container: WalkStore.makeContainer(inMemory: true))
        let preview = try target.previewRestore(data)
        XCTAssertEqual(preview.catalogAdditions.count, 2)
        XCTAssertTrue(preview.catalogConflicts.isEmpty)
        XCTAssertEqual(try target.restore(preview).added, 1)
        XCTAssertEqual(target.fieldCatalog.entries.count, 2)
        XCTAssertEqual(target.walks[0].customFields[0].value, .boolean(false))
        XCTAssertEqual(target.fieldCatalog.entry(unused)?.archived, true)
    }

    func testCatalogConflictsAndInvalidReferencesAreVisibleNotSilentlyReinterpreted() async throws {
        let local = try WalkStore(container: WalkStore.makeContainer(inMemory: true))
        let fieldID = try local.createField(name: "Schmerz", kind: .scale, scaleMin: 1, scaleMax: 7, scaleStep: 0.5)
        try local.reviseField(fieldID, name: "Schmerz lokal", kind: .scale, scaleMin: 1, scaleMax: 7, scaleStep: 0.5)
        var incoming = CustomFieldCatalog.empty
        try incoming.insert(try CustomFieldDefinition.make(
            id: fieldID, name: "Schmerz Backup", kind: .scale, scaleMin: 1, scaleMax: 7, scaleStep: 0.5
        ))
        let preview = try local.previewRestore(try WalkBackup.encode([], catalog: incoming, exportedAt: origin))
        XCTAssertEqual(preview.catalogConflicts.count, 1)
        XCTAssertEqual(preview.catalogConflicts[0].id, fieldID)
        XCTAssertThrowsError(try local.restore(preview))
        XCTAssertEqual(try local.restore(preview, catalogChoices: [fieldID: .keepLocal]).replaced, 0)
        XCTAssertEqual(local.fieldCatalog.entry(fieldID)?.current.name, "Schmerz lokal")

        var ghostWalk = Walk(startedAt: origin)
        let ghost = try CustomFieldDefinition.make(name: "Geist", kind: .boolean)
        ghostWalk.customFields = [try CustomFieldObservation(definition: ghost)]
        XCTAssertThrowsError(try WalkBackup.encode([ghostWalk], catalog: .empty, exportedAt: origin))
    }

    func testInvalidCatalogBackupLeavesStoreUnchanged() async throws {
        let store = try WalkStore(container: WalkStore.makeContainer(inMemory: true))
        let fieldID = try store.createField(name: "Husten", kind: .boolean)
        let walkID = try store.start(at: origin)
        try store.update(walkID) { try $0.setCustomField(fieldID, value: .boolean(true)) }
        let beforeWalks = store.walks
        let beforeCatalog = store.fieldCatalog

        func envelope(_ catalogJSON: String) -> Data {
            Data("""
            {"dateEncoding":"secondsSince2001-01-01T00:00:00Z","exportedAt":0,"fieldCatalog":\(catalogJSON),"format":"de.carlosanderssohn.RosieGassi.backup","schemaVersion":3,"walkCount":0,"walks":[]}
            """.utf8)
        }

        XCTAssertThrowsError(try store.previewRestore(envelope(
            "{\"entries\":[{\"archived\":false,\"revisions\":[],\"sortIndex\":0}]}"
        ))) { error in
            XCTAssertEqual(error as? BackupError, .invalidArchive)
        }
        XCTAssertThrowsError(try store.previewRestore(envelope(
            "{\"entries\":[{\"archived\":false,\"revisions\":[],\"sortIndex\":9223372036854775808}]}"
        ))) { error in
            XCTAssertEqual(error as? BackupError, .invalidArchive)
        }
        let maxIndexCatalog = """
        {"entries":[{"archived":false,"revisions":[{"id":"00000000-0000-0000-0000-000000000001","kind":"jaNein","name":"Husten","revision":1}],"sortIndex":9223372036854775807}]}
        """
        XCTAssertThrowsError(try store.previewRestore(envelope(maxIndexCatalog))) { error in
            XCTAssertEqual(error as? BackupError, .invalidArchive)
        }
        let overflowStep = 1.0 / Double(Int.max)
        let overflowScale = """
        {"entries":[{"archived":false,"revisions":[{"id":"00000000-0000-0000-0000-000000000002","kind":"skala","name":"Overflow","revision":1,"scaleMin":0,"scaleMax":1,"scaleStep":\(overflowStep)}],"sortIndex":0}]}
        """
        XCTAssertThrowsError(try store.previewRestore(envelope(overflowScale))) { error in
            XCTAssertEqual(error as? BackupError, .invalidArchive)
        }
        XCTAssertEqual(store.walks, beforeWalks)
        XCTAssertEqual(store.fieldCatalog, beforeCatalog)
        XCTAssertEqual(store.walks[0].customFields[0].value, .boolean(true))
    }
}
