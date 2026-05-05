import Foundation
import Core

/// Actor managing the two-stage file lifecycle for captured photos.
///
/// Stage 1 — **tmp/photo-capture/** — written immediately after capture;
/// considered ephemeral. `discard(staged:)` removes it on failure.
///
/// Stage 2 — **AppSupport/photos/{entity}/{id}/** — permanent home after a
/// successful upload. `promote(staged:entity:id:)` performs an atomic move.
///
/// All operations are isolated to this actor, so concurrent calls are safe
/// without external locking.
public actor PhotoStore {

    // MARK: - Directories

    private let stagingDirectory: URL
    private let photosRoot: URL

    public init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-capture", isDirectory: true)
        stagingDirectory = tmp

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        photosRoot = appSupport.appendingPathComponent("photos", isDirectory: true)

        try FileManager.default.createDirectoryIfNeeded(at: stagingDirectory)
        try FileManager.default.createDirectoryIfNeeded(at: photosRoot)
    }

    // MARK: - Stage

    /// Writes `data` to a UUID-named file in the staging directory.
    /// - Returns: URL of the staged file.
    public func stage(data: Data) async throws -> URL {
        let filename = "\(UUID().uuidString).heic"
        let destination = stagingDirectory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        AppLog.ui.debug("PhotoStore: staged \(destination.lastPathComponent, privacy: .public)")
        return destination
    }

    // MARK: - Promote

    /// Moves a staged file to its permanent location under `AppSupport/photos/{entity}/{id}/`.
    ///
    /// If a file already exists at the destination (e.g. retry), it is replaced.
    /// - Parameters:
    ///   - staged: URL returned by ``stage(data:)``.
    ///   - entity: Entity type string, e.g. `"ticket"`, `"customer"`.
    ///   - id: Entity primary key.
    /// - Returns: The new permanent URL.
    public func promote(staged: URL, entity: String, id: Int64) async throws -> URL {
        let entityDir = photosRoot
            .appendingPathComponent(entity, isDirectory: true)
            .appendingPathComponent(String(id), isDirectory: true)
        try FileManager.default.createDirectoryIfNeeded(at: entityDir)

        let destination = entityDir.appendingPathComponent(staged.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: staged, to: destination)
        AppLog.ui.debug("PhotoStore: promoted \(destination.lastPathComponent, privacy: .public) → \(entity)/\(id)")
        return destination
    }

    // MARK: - Discard

    /// Deletes a staged file. No-op if the file does not exist.
    public func discard(staged: URL) async throws {
        guard FileManager.default.fileExists(atPath: staged.path) else { return }
        try FileManager.default.removeItem(at: staged)
        AppLog.ui.debug("PhotoStore: discarded \(staged.lastPathComponent, privacy: .public)")
    }

    // MARK: - List

    /// Returns all photo URLs stored for a given entity / id pair.
    public func listForEntity(_ entity: String, id: Int64) async throws -> [URL] {
        let entityDir = photosRoot
            .appendingPathComponent(entity, isDirectory: true)
            .appendingPathComponent(String(id), isDirectory: true)
        guard FileManager.default.fileExists(atPath: entityDir.path) else {
            return []
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: entityDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )
        // Sort by creation date, oldest first.
        return contents.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lDate < rDate
        }
    }
}

// MARK: - FileManager helpers

private extension FileManager {
    func createDirectoryIfNeeded(at url: URL) throws {
        guard !fileExists(atPath: url.path) else { return }
        try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
}
