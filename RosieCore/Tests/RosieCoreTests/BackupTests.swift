import XCTest
@testable import RosieCore

final class BackupTests: XCTestCase {
    func testUnrepresentableCalendarDatesAreRejected() throws {
        XCTAssertThrowsError(try WalkBackup.encode([Walk(startedAt: Date(timeIntervalSince1970: 1e100))]))
        XCTAssertThrowsError(try WalkBackup.encode([Walk(startedAt: Date(timeIntervalSince1970: -1e100))]))
    }

    func testUntrustedBackupIsValidatedBeforeUse() throws {
        let walk = Walk(startedAt: Date())
        let data = try WalkBackup.encode([walk])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("schemaVersion", 999 as Any), ("format", "another-app"),
                             ("dateEncoding", "unix-seconds"), ("walkCount", 2)] {
            var altered = original
            altered[key] = value
            XCTAssertThrowsError(try WalkBackup.decode(JSONSerialization.data(withJSONObject: altered)), key)
        }
        var invalid = walk
        invalid.lameness = 8
        // Construct untrusted bytes without going through the validated exporter.
        var altered = original
        altered["walks"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([invalid]))
        XCTAssertThrowsError(try WalkBackup.decode(JSONSerialization.data(withJSONObject: altered)))
        XCTAssertThrowsError(try WalkBackup.encode([walk, walk]))
        XCTAssertThrowsError(try WalkBackup.encode([walk, Walk(startedAt: Date())]))
        XCTAssertThrowsError(try WalkBackup.decode(Data("{broken".utf8)))
    }

    func testBackupRoundTripPreservesEveryFieldExactly() throws {
        let start = Date(timeIntervalSinceReferenceDate: 812_345_678.1234567)
        var walk = Walk(startedAt: start, timeZoneID: "Europe/Berlin")
        walk.lameness = 3.27
        walk.elevator = nil
        walk.hallway = .hesitant
        walk.courtyard = .no
        walk.notes = "Äpfel, \"Zitat\"\nZweite Zeile 🐾"
        try walk.pause(at: start.addingTimeInterval(17.125))
        let data = try WalkBackup.encode([walk], exportedAt: start)
        let backup = try WalkBackup.decode(data)
        XCTAssertEqual(backup.walks, [walk])
        XCTAssertEqual(backup.exportedAt, start)
        XCTAssertNil(backup.walks[0].motivation)
        XCTAssertNil(backup.walks[0].elevator)
        XCTAssertTrue(backup.walks[0].isPaused)
    }
}
