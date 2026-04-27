import Foundation
import Core
import Networking

// §4.1 — Disk-backed ticket list cache.
//
// Purpose: cold launches show cached data instantly while the network
//   fetch completes in the background (render-from-disk pattern).
//
// Storage: one JSON file per (filter, keyword) combination under
//   {CachesDirectory}/BizarreCRM/Tickets/<key>.json
// Data: raw server `data` array payload re-encoded from the decoded
//   [TicketSummary] values via JSONEncoder → individual property mirroring.
//
// NOTE: Encoding requires TicketSummary to be Codable. Until Networking
// adds Encodable conformance to TicketSummary, we store a lightweight
// mirror `CachedTicketRecord` which captures only the display fields
// needed for an offline list render. Server truth is loaded on refresh.
//
// Replaces the in-memory-only strategy from TicketCachedRepositoryImpl's
// TODO comment; `TicketCachedRepositoryImpl` remains the source-of-truth
// authority and uses this store as a read-ahead layer.

// MARK: - Disk-cache record (offline display fields)

/// Minimal snapshot of a TicketSummary for offline list rendering.
/// Contains only the display fields shown in TicketListView rows.
struct CachedTicketRecord: Codable, Sendable {
    let id: Int64
    let orderId: String
    let customerDisplayName: String?
    let statusName: String?
    let statusColor: String?
    let urgency: String?
    let totalCents: Int
    let dueOn: String?
    let updatedAt: String
    let isPinned: Bool
    let slaStatus: String?

    init(from summary: TicketSummary) {
        id                  = summary.id
        orderId             = summary.orderId
        customerDisplayName = summary.customer?.displayName
        statusName          = summary.status?.name
        statusColor         = summary.status?.color
        urgency             = summary.urgency
        totalCents          = summary.total
        dueOn               = summary.dueOn
        updatedAt           = summary.updatedAt
        isPinned            = summary.isPinned
        slaStatus           = summary.slaStatus
    }
}

// MARK: - Disk cache actor

/// Thread-safe JSON file cache for ticket lists.
/// Used by `TicketCachedRepositoryImpl.readDiskCache()` and
/// `TicketCachedRepositoryImpl.writeDiskCache(_:for:)`.
actor TicketDiskCache {

    // MARK: Singleton

    static let shared = TicketDiskCache()
    private init() {}

    // MARK: Types

    private struct DiskEntry: Codable {
        let records: [CachedTicketRecord]
        let savedAt: Date
    }

    // MARK: Public interface

    /// Returns cached records for `key`, or nil if absent / stale / unreadable.
    func read(key: String, maxAgeSeconds: Int = 3600) -> [CachedTicketRecord]? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(DiskEntry.self, from: data) else {
            return nil
        }
        let age = Date().timeIntervalSince(entry.savedAt)
        guard age <= Double(maxAgeSeconds) else {
            AppLog.ui.debug("Ticket disk cache stale for key '\(key, privacy: .public)' (age \(Int(age))s)")
            return nil
        }
        return entry.records
    }

    /// Persists `summaries` to disk for `key`.
    func write(_ summaries: [TicketSummary], key: String) {
        guard let url = fileURL(for: key) else { return }
        let records = summaries.map { CachedTicketRecord(from: $0) }
        let entry = DiskEntry(records: records, savedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.ui.warning("Ticket disk cache write failed for '\(key, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes all cached files. Called on sign-out.
    func purgeAll() {
        guard let base = baseDirectory() else { return }
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Private

    private func fileURL(for key: String) -> URL? {
        guard let base = baseDirectory() else { return nil }
        // Sanitise key to a valid filename component.
        let safe = key.replacingOccurrences(of: "/|\\| ", with: "_", options: .regularExpression)
        return base.appendingPathComponent("\(safe).json")
    }

    private func baseDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent("BizarreCRM/Tickets", isDirectory: true)
    }
}
