import XCTest
@testable import RosieCore

final class TransferFileTests: XCTestCase {
    func testReadBackIsExactAndOversizedFilesAreRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.json")
        let expected = try WalkBackup.encode([Walk(startedAt: Date())])
        try expected.write(to: url, options: .atomic)
        XCTAssertEqual(try TransferFile.read(url), expected)
        try Data(repeating: 32, count: WalkBackup.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try TransferFile.read(url))
        XCTAssertThrowsError(try WalkBackup.decode(Data(repeating: 32, count: WalkBackup.maximumBytes + 1)))
    }
}
