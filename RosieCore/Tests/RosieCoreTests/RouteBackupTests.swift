import XCTest
@testable import RosieCore

final class RouteBackupTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    func testSchemaTwoFullBackupAndDistinctLocationFreeExport() throws {
        var walk = Walk(startedAt: t, recordRoute: true)
        try walk.route!.append([RoutePoint(timestamp: t, latitude: 52.123456, longitude: 13.123456, horizontalAccuracy: 5)], startedAt: t, receivedAt: t)
        let full = try WalkBackup.encode([walk])
        XCTAssertEqual(try WalkBackup.decode(full).schemaVersion, 3)
        XCTAssertEqual(try WalkBackup.decode(full).walks, [walk])
        let privateData = try WalkBackup.encodeWithoutLocations([walk])
        let json = String(decoding: privateData, as: UTF8.self)
        XCTAssertFalse(json.contains("latitude"))
        XCTAssertFalse(json.contains("longitude"))
        XCTAssertFalse(json.contains("route"))
        XCTAssertTrue(json.contains("location-free-export"))
        XCTAssertThrowsError(try WalkBackup.decode(privateData))
        let csv = String(decoding: try WalkCSV.encode([walk]), as: UTF8.self)
        XCTAssertFalse(csv.contains("52.123456"))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: full) as? [String: Any])
        legacy["schemaVersion"] = 1
        var oldWalk = try XCTUnwrap((legacy["walks"] as? [[String: Any]])?.first)
        oldWalk.removeValue(forKey: "route")
        oldWalk.removeValue(forKey: "elevator")
        legacy["walks"] = [oldWalk]
        let decoded = try WalkBackup.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.walks[0].route)
        XCTAssertNil(decoded.walks[0].elevator)
        oldWalk["route"] = ["captureRequested": true, "points": [["latitude": 200]]]
        legacy["schemaVersion"] = 2
        legacy["walks"] = [oldWalk]
        XCTAssertThrowsError(try WalkBackup.decode(JSONSerialization.data(withJSONObject: legacy)))
    }

    func testArchiveExactSizeBoundary() throws {
        var walk = Walk(startedAt: t)
        let initial = try WalkBackup.encode([walk], exportedAt: t)
        walk.notes = String(repeating: "x", count: WalkBackup.maximumBytes - initial.count)
        let exact = try WalkBackup.encode([walk], exportedAt: t)
        XCTAssertEqual(exact.count, WalkBackup.maximumBytes)
        XCTAssertEqual(try WalkBackup.decode(exact).walkCount, 1)
        walk.notes += "x"
        XCTAssertThrowsError(try WalkBackup.encode([walk], exportedAt: t))
        XCTAssertThrowsError(try WalkBackup.decode(exact + Data([32])))
    }
}
