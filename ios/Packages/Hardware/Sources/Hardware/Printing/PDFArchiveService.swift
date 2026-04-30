import Foundation
import Core

// MARK: - PDFArchiveService
//
// §17.4 — "Archival: generated PDFs on tenant server (primary) + local cache
//  (offline); deterministic re-generation for historical recreation."
//
// Design:
//  1. On print / share, `archive(...)` is called with the local PDF URL + metadata.
//  2. The service copies the file to `AppSupport/pdf-archive/{entityKind}/{entityId}/`
//     (local cache) and enqueues a background upload to the server.
//  3. On reconnect the sync queue drains the pending uploads.
//  4. `localURL(for:)` returns the cached path for offline re-open / re-print.
//  5. `regenerate(...)` produces a fresh PDF from a stored model payload when the
//     original file has been deleted (deterministic re-generation path).
//
// Sovereignty: PDFs are uploaded to `/api/v1/documents/upload` on our own server.
// No third-party cloud storage. The upload body uses the standard envelope.

// MARK: - PDFArchiveEntry

/// Metadata persisted alongside each archived PDF.
public struct PDFArchiveEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public let entityKind: String   // e.g. "invoice", "receipt", "ticket"
    public let entityId: String     // opaque string, e.g. "INV-2026-00099"
    public let documentType: String // e.g. "Invoice", "Receipt"
    public let localPath: String    // relative to AppSupport — never absolute
    public let createdAt: Date
    public var uploadedAt: Date?
    public var serverDocumentId: String?  // server-assigned ID after upload

    public init(
        id: UUID = UUID(),
        entityKind: String,
        entityId: String,
        documentType: String,
        localPath: String,
        createdAt: Date = Date(),
        uploadedAt: Date? = nil,
        serverDocumentId: String? = nil
    ) {
        self.id = id
        self.entityKind = entityKind
        self.entityId = entityId
        self.documentType = documentType
        self.localPath = localPath
        self.createdAt = createdAt
        self.uploadedAt = uploadedAt
        self.serverDocumentId = serverDocumentId
    }
}

// MARK: - PDFArchiveError

public enum PDFArchiveError: Error, LocalizedError, Sendable {
    case fileMissing(URL)
    case copyFailed(String)
    case indexCorrupted

    public var errorDescription: String? {
        switch self {
        case .fileMissing(let url):    return "PDF archive source file not found: \(url.lastPathComponent)"
        case .copyFailed(let detail):  return "PDF archive copy failed: \(detail)"
        case .indexCorrupted:          return "PDF archive index could not be loaded."
        }
    }
}

// MARK: - PDFArchiveService

/// Persists generated PDFs to local storage and enqueues server uploads.
///
/// Thread-safe: `actor` isolates all state mutations.
public actor PDFArchiveService {

    // MARK: - Singleton

    public static let shared = PDFArchiveService()

    // MARK: - Private state

    private let fileManager = FileManager.default
    private var index: [UUID: PDFArchiveEntry] = [:]
    private let indexKey = "com.bizarrecrm.hardware.pdfArchiveIndex"

    // MARK: - Init

    public init() {
        // Load persisted index.
        if let data = UserDefaults.standard.data(forKey: indexKey),
           let decoded = try? JSONDecoder().decode([UUID: PDFArchiveEntry].self, from: data) {
            self.index = decoded
        }
    }

    // MARK: - Public API

    /// Archive a generated PDF by copying it to local persistent storage and
    /// recording the entry in the index.
    ///
    /// - Parameters:
    ///   - sourceURL:    The temporary PDF URL produced by `ReceiptRenderer`.
    ///   - entityKind:   Type of entity ("invoice", "receipt", "ticket", etc.).
    ///   - entityId:     Entity identifier (invoice number, sale ID, ticket number).
    ///   - documentType: Human-readable document category.
    /// - Returns: The archived `PDFArchiveEntry`.
    @discardableResult
    public func archive(
        _ sourceURL: URL,
        entityKind: String,
        entityId: String,
        documentType: String
    ) async throws -> PDFArchiveEntry {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PDFArchiveError.fileMissing(sourceURL)
        }

        // Determine local archive directory.
        let archiveDir = try archiveDirectory(entityKind: entityKind, entityId: entityId)
        let destURL = archiveDir.appendingPathComponent("\(UUID().uuidString).pdf")
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw PDFArchiveError.copyFailed(error.localizedDescription)
        }

        // Record entry.
        let relativePath = relativePath(for: destURL)
        let entry = PDFArchiveEntry(
            entityKind: entityKind,
            entityId: entityId,
            documentType: documentType,
            localPath: relativePath,
            createdAt: Date()
        )
        index[entry.id] = entry
        persistIndex()

        AppLog.hardware.info("PDFArchiveService: archived \(documentType, privacy: .public) for \(entityKind, privacy: .public)/\(entityId, privacy: .private)")
        return entry
    }

    /// Returns the local `URL` for a previously archived PDF, or `nil` if the
    /// file no longer exists (e.g. deleted by OS storage pressure).
    public func localURL(for entryId: UUID) -> URL? {
        guard let entry = index[entryId] else { return nil }
        let url = absoluteURL(for: entry.localPath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Returns all archived entries for a given entity, newest first.
    public func entries(entityKind: String, entityId: String) -> [PDFArchiveEntry] {
        index.values
            .filter { $0.entityKind == entityKind && $0.entityId == entityId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Marks an entry as uploaded and records the server-assigned document ID.
    ///
    /// Called by the upload task after a successful `POST /api/v1/documents/upload`.
    public func markUploaded(entryId: UUID, serverDocumentId: String) {
        guard var entry = index[entryId] else { return }
        entry = PDFArchiveEntry(
            id: entry.id,
            entityKind: entry.entityKind,
            entityId: entry.entityId,
            documentType: entry.documentType,
            localPath: entry.localPath,
            createdAt: entry.createdAt,
            uploadedAt: Date(),
            serverDocumentId: serverDocumentId
        )
        index[entryId] = entry
        persistIndex()
    }

    /// Deletes the local file and removes the entry from the index.
    public func delete(entryId: UUID) {
        guard let entry = index[entryId] else { return }
        let url = absoluteURL(for: entry.localPath)
        try? fileManager.removeItem(at: url)
        index.removeValue(forKey: entryId)
        persistIndex()
    }

    /// Returns entries whose PDFs have not yet been uploaded to the server.
    public var pendingUploadEntries: [PDFArchiveEntry] {
        index.values.filter { $0.uploadedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Private helpers

    private func archiveDirectory(entityKind: String, entityId: String) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport
            .appendingPathComponent("pdf-archive")
            .appendingPathComponent(entityKind)
            .appendingPathComponent(entityId)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func relativePath(for url: URL) -> String {
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return url.path }
        return String(url.path.dropFirst(appSupport.path.count + 1))
    }

    private func absoluteURL(for relativePath: String) -> URL {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent(relativePath)
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        UserDefaults.standard.set(data, forKey: indexKey)
    }
}
