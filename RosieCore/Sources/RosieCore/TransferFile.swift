import Foundation

public enum TransferFile {
    // Bound memory use before decoding, and coordinate access with Files/iCloud providers.
    public static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result {
                let file = try FileHandle(forReadingFrom: readable)
                defer { try? file.close() }
                let data = try file.read(upToCount: WalkBackup.maximumBytes + 1) ?? Data()
                guard data.count <= WalkBackup.maximumBytes else { throw BackupError.tooLarge }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.invalidArchive }
        return try result.get()
    }
}
