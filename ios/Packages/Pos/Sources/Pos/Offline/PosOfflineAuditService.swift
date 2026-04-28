#if canImport(UIKit)
import Foundation
import Observation
import Core

// MARK: - PosOfflineAuditService (§16.12 offline audit — duration + sync time)

/// §16.12 — Records offline outage duration and per-sale sync timestamps so
/// managers can report: "3 sales made during a 20-minute outage — all reconciled."
///
/// **Design:**
/// - `recordOutageStart()` is called when the device transitions offline during
///   an active POS session.
/// - `recordOutageEnd()` is called when connectivity is restored.
/// - `recordSaleSync(idempotencyKey:syncedAt:)` stamps each offline sale when the
///   sync drain loop confirms the server received it.
/// - `outageRecords` is the append-only audit log — persisted in `UserDefaults`
///   as a lightweight MVP (§20.5 GRDB migration pending).
///
/// **Manager report source:** `PosOutageSummary.all()` aggregates the records
/// into the "N sales during Xmin outage — all reconciled" report format.
///
/// Thread safety: `@MainActor` — all mutations happen on the main actor.
@MainActor
@Observable
public final class PosOfflineAuditService {

    // MARK: - Singleton

    public static let shared = PosOfflineAuditService()

    // MARK: - Observable state

    /// Most-recent outage record, or `nil` when currently online.
    public private(set) var currentOutage: PosOutageRecord? = nil

    /// Append-only log of all outage records (including the in-progress one).
    public private(set) var outageRecords: [PosOutageRecord] = []

    // MARK: - Private

    private let storageKey = "pos.offline.outageRecords"

    public init() {
        loadPersistedRecords()
    }

    // MARK: - Public API

    /// Call when the device goes offline during an active POS session.
    /// Idempotent — calling while already offline is a no-op.
    public func recordOutageStart(at date: Date = .now) {
        guard currentOutage == nil else { return }
        let record = PosOutageRecord(outageStartedAt: date)
        currentOutage = record
        outageRecords.append(record)
        persistRecords()
        AppLog.pos.info("PosOfflineAuditService: outage started at \(date.formatted(), privacy: .public)")
    }

    /// Call when connectivity is restored.
    /// Sets `outageEndedAt` on the current record and clears `currentOutage`.
    public func recordOutageEnd(at date: Date = .now) {
        guard let ongoing = currentOutage,
              let index = outageRecords.firstIndex(where: { $0.id == ongoing.id }) else {
            currentOutage = nil
            return
        }
        outageRecords[index].outageEndedAt = date
        currentOutage = nil
        persistRecords()
        let durationMinutes = ongoing.durationMinutes(to: date)
        let saleCount = self.outageRecords[index].saleSyncs.count
        AppLog.pos.info("PosOfflineAuditService: outage ended — duration \(durationMinutes, privacy: .public) min, \(saleCount, privacy: .public) sales queued")
    }

    /// Call from the sync drain loop when the server confirms an offline sale.
    /// - Parameters:
    ///   - idempotencyKey: The client UUID used as the sale's idempotency key.
    ///   - syncedAt: Timestamp of successful server confirmation.
    public func recordSaleSync(idempotencyKey: String, syncedAt: Date = .now) {
        // Find the most recent outage that contains this sale
        guard let index = outageRecords.lastIndex(where: { record in
            record.pendingSaleIdempotencyKeys.contains(idempotencyKey)
        }) else {
            AppLog.pos.warning("PosOfflineAuditService: sync for unknown sale key \(idempotencyKey, privacy: .public)")
            return
        }
        let sync = PosOutageSaleSync(idempotencyKey: idempotencyKey, syncedAt: syncedAt)
        outageRecords[index].saleSyncs.append(sync)
        persistRecords()
        AppLog.pos.info("PosOfflineAuditService: sale \(idempotencyKey, privacy: .private) synced at \(syncedAt.formatted(), privacy: .public)")
    }

    /// Register an offline sale with the current outage.
    /// Call from `PosSyncOpExecutor` when a sale is queued during an outage.
    public func registerOfflineSale(idempotencyKey: String) {
        guard let index = outageRecords.indices.last else { return }
        if outageRecords[index].outageEndedAt == nil {
            outageRecords[index].pendingSaleIdempotencyKeys.append(idempotencyKey)
            persistRecords()
        }
    }

    /// Returns a human-readable manager report string for the most-recent completed outage.
    /// Example: "3 sales made during a 20-min outage — 3 of 3 reconciled."
    public var mostRecentOutageSummary: String? {
        guard let record = outageRecords.last(where: { $0.outageEndedAt != nil }) else {
            return nil
        }
        let total  = record.pendingSaleIdempotencyKeys.count
        let synced = record.saleSyncs.count
        let mins   = record.durationMinutes(to: record.outageEndedAt ?? .now)
        if total == 0 {
            return "No sales during the \(mins)-min outage."
        }
        let all = synced == total ? "all reconciled" : "\(synced) of \(total) reconciled"
        return "\(total) sale\(total == 1 ? "" : "s") made during a \(mins)-min outage — \(all)."
    }

    // MARK: - Persistence (UserDefaults MVP)

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(outageRecords) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadPersistedRecords() {
        guard let data  = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([PosOutageRecord].self, from: data) else { return }
        outageRecords = records
        // Restore in-progress outage if the app was killed mid-outage.
        currentOutage = records.first(where: { $0.outageEndedAt == nil })
    }
}

// MARK: - PosOutageRecord

/// A single offline outage event and the sales captured during it.
public struct PosOutageRecord: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public let outageStartedAt: Date
    public var outageEndedAt: Date? = nil

    /// Idempotency keys of all offline sales registered during this outage.
    public var pendingSaleIdempotencyKeys: [String] = []

    /// Sync confirmations received from the server for the above sales.
    public var saleSyncs: [PosOutageSaleSync] = []

    /// Whether all queued sales have been confirmed by the server.
    public var isFullyReconciled: Bool {
        !pendingSaleIdempotencyKeys.isEmpty &&
        saleSyncs.count >= pendingSaleIdempotencyKeys.count
    }

    /// Duration of the outage in minutes (rounded).
    public func durationMinutes(to endDate: Date = .now) -> Int {
        let seconds = endDate.timeIntervalSince(outageStartedAt)
        return max(1, Int(seconds / 60))
    }
}

// MARK: - PosOutageSaleSync

/// Records when a specific offline sale was confirmed by the server.
public struct PosOutageSaleSync: Codable, Sendable {
    public let idempotencyKey: String
    public let syncedAt: Date
}
#endif
