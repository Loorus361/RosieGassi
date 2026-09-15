import XCTest
@testable import RosieCore

@MainActor
final class RestoreTests: XCTestCase {
    func testFailedBatchRollsBackReplacementAndAdditionThenCanRetry() async throws {
        struct DiskFailure: Error {}
        var fail = false
        let container = try WalkStore.makeContainer(inMemory: true)
        let store = try WalkStore(container: container, persist: {
            if fail { throw DiskFailure() }
            try $0.save()
        })
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let oldID = try store.start(at: start)
        try store.update(oldID) { try $0.finish(at: start.addingTimeInterval(60)) }
        var replacement = store.walks[0]
        replacement.notes = "Version aus Backup"
        var addition = Walk(startedAt: start.addingTimeInterval(120))
        try addition.finish(at: start.addingTimeInterval(180))
        let unrelatedID = try store.start(at: start.addingTimeInterval(240))
        let before = store.walks
        let preview = try store.previewRestore(WalkBackup.encode([replacement, addition]))
        fail = true
        XCTAssertThrowsError(try store.restore(preview, choices: [oldID: .useBackup]))
        XCTAssertEqual(store.walks, before)
        XCTAssertEqual(try WalkStore(container: container).walks, before)
        fail = false
        let result = try store.restore(preview, choices: [oldID: .useBackup])
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.replaced, 1)
        XCTAssertEqual(store.activeWalk?.id, unrelatedID)
        XCTAssertEqual(try WalkStore(container: container).walks.count, 3)
    }

    func testStalePreviewAndUnsavedDraftsBlockTransfer() async throws {
        struct DiskFailure: Error {}
        var fail = false
        let store = try WalkStore(container: WalkStore.makeContainer(inMemory: true), persist: {
            if fail { throw DiskFailure() }
            try $0.save()
        })
        let id = try store.start()
        let data = try store.backupData()
        let preview = try store.previewRestore(data)
        try store.update(id) { $0.notes = "Nach Vorschau geändert" }
        XCTAssertThrowsError(try store.restore(preview))
        fail = true
        XCTAssertThrowsError(try store.update(id) { $0.notes = "Ungespeicherter Entwurf" })
        XCTAssertThrowsError(try store.backupData())
        XCTAssertThrowsError(try store.csvData())
        XCTAssertThrowsError(try store.previewRestore(data))
        XCTAssertThrowsError(try store.restore(preview))
        XCTAssertEqual(store.pendingNotes[id], "Ungespeicherter Entwurf")
    }

    func testSecondOpenWalkCanBeExcludedWithoutChangingLocalWalk() async throws {
        let store = try WalkStore(container: WalkStore.makeContainer(inMemory: true))
        let localID = try store.start()
        let incoming = Walk(startedAt: Date())
        let preview = try store.previewRestore(WalkBackup.encode([incoming]))
        XCTAssertThrowsError(try store.restore(preview))
        let result = try store.restore(preview, excluded: [incoming.id])
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(store.activeWalk?.id, localID)
    }

    func testConflictRequiresExplicitChoice() async throws {
        let container = try WalkStore.makeContainer(inMemory: true)
        let store = try WalkStore(container: container)
        let id = try store.start(at: Date(timeIntervalSince1970: 1_800_000_000))
        let archived = try store.backupData()
        try store.update(id) { $0.notes = "Lokale Änderung" }
        let preview = try store.previewRestore(archived)
        XCTAssertEqual(preview.conflicts.count, 1)
        XCTAssertThrowsError(try store.restore(preview))
        XCTAssertEqual(store.walks[0].notes, "Lokale Änderung")
        XCTAssertEqual(try store.restore(preview, choices: [id: .keepLocal]).skipped, 1)
        XCTAssertEqual(store.walks[0].notes, "Lokale Änderung")
        let refreshed = try store.previewRestore(archived)
        XCTAssertEqual(try store.restore(refreshed, choices: [id: .useBackup]).replaced, 1)
        XCTAssertEqual(try WalkStore(container: container).walks[0].notes, "")
    }

    func testRestoreAddsNewWalksAndRepeatedImportIsIdempotent() async throws {
        let source = try WalkStore(container: WalkStore.makeContainer(inMemory: true))
        let id = try source.start(at: Date(timeIntervalSince1970: 1_800_000_000))
        try source.update(id) { walk in
            walk.notes = "Synthetisch"
            walk.lameness = 3.27
            try walk.pause(at: walk.startedAt.addingTimeInterval(10))
        }
        let data = try source.backupData()
        let container = try WalkStore.makeContainer(inMemory: true)
        let target = try WalkStore(container: container)
        let preview = try target.previewRestore(data)
        XCTAssertEqual(preview.additions.count, 1)
        XCTAssertTrue(target.walks.isEmpty, "Vorschau darf nicht schreiben")
        let result = try target.restore(preview)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(target.walks, source.walks)
        XCTAssertEqual(try WalkStore(container: container).walks, source.walks)
        let repeated = try target.previewRestore(data)
        XCTAssertEqual(repeated.identicalCount, 1)
        XCTAssertEqual(try target.restore(repeated).added, 0)
        XCTAssertEqual(target.walks.count, 1)
    }
}
