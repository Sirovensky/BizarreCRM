import Foundation
import Core
import Networking
import Persistence

// MARK: - TimeclockOfflineQueue
//
// §14.3 — Persists clock-in / clock-out events locally when the device is
// offline, then drains them to the server on reconnect.
//
// Architecture:
//  - Pending events stored in the Keychain. BUGHUNT-2026-05-17: previously
//    UserDefaults — but each `PendingTimeclockEvent` carries the user's PIN,
//    which must NEVER live in unencrypted plist storage. Migrated to
//    `KeychainKey.timeclockOfflineQueue`; any legacy UserDefaults rows are
//    drained on first load and the plist key is removed.
//  - Drain is idempotent: each event carries an idempotency key so a retry
//    after a partial flush won't duplicate entries.
//  - On successful server write the event is removed from the queue.
//  - Events retain chronological order (array, FIFO).
//
// Callers:
//  `ClockInOutViewModel` calls `enqueue` when offline, and `Sync` drain loop
//  calls `drain(api:)` when connectivity is restored.

public enum TimeclockAction: String, Codable, Sendable {
    case clockIn  = "clock_in"
    case clockOut = "clock_out"
}

public struct PendingTimeclockEvent: Codable, Sendable, Identifiable {
    public let id: String             // Idempotency key (UUID)
    public let userId: Int64
    public let action: TimeclockAction
    public let pin: String            // Required by server for clock-in/out
    public let enqueuedAt: Date

    public init(userId: Int64, action: TimeclockAction, pin: String) {
        self.id = UUID().uuidString
        self.userId = userId
        self.action = action
        self.pin = pin
        self.enqueuedAt = Date()
    }
}

@globalActor
public actor TimeclockOfflineQueue {

    public static let shared = TimeclockOfflineQueue()

    /// Legacy UserDefaults key. Kept only for one-shot migration into Keychain.
    private let legacyDefaultsKey = "bizarrecrm.timeclock.offline_queue"
    private var pending: [PendingTimeclockEvent] = []
    private var isDraining = false

    private init() {
        // Preferred storage: Keychain (PINs are secrets).
        if let raw = KeychainStore.shared.get(.timeclockOfflineQueue),
           let data = Data(base64Encoded: raw),
           let events = try? JSONDecoder().decode([PendingTimeclockEvent].self, from: data) {
            pending = events
            return
        }
        // One-shot migration: drain anything that was previously persisted to
        // UserDefaults, write it back to the Keychain, then clear the plist
        // entry so the PIN never lingers there.
        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let events = try? JSONDecoder().decode([PendingTimeclockEvent].self, from: data) {
            pending = events
            persist()
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
    }

    // MARK: - Public API

    /// Enqueue a clock event for later server submission.
    public func enqueue(_ event: PendingTimeclockEvent) {
        pending.append(event)
        persist()
        AppLog.sync.info("Timeclock queued: \(event.action.rawValue, privacy: .public) userId=\(event.userId, privacy: .private)")
    }

    /// Returns a snapshot of pending events — for display in the UI.
    public var pendingEvents: [PendingTimeclockEvent] { pending }

    /// True when there are unsent events.
    public var hasPending: Bool { !pending.isEmpty }

    /// Drain all pending events to the server in order.
    /// Safe to call repeatedly; concurrent calls are serialised via the actor.
    public func drain(api: APIClient) async {
        guard !pending.isEmpty, !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        var remaining: [PendingTimeclockEvent] = []
        var cancelledIndex: Int? = nil
        for (index, event) in pending.enumerated() {
            do {
                switch event.action {
                case .clockIn:
                    _ = try await api.clockIn(userId: event.userId, pin: event.pin)
                case .clockOut:
                    _ = try await api.clockOut(userId: event.userId, pin: event.pin)
                }
                AppLog.sync.info(
                    "Timeclock drained: \(event.action.rawValue, privacy: .public) id=\(event.id, privacy: .public)"
                )
            } catch is CancellationError {
                // BUGHUNT-2026-05-17: stop draining when the task is cancelled
                // and re-queue this event AND every subsequent unprocessed
                // event. The previous code re-threw nothing and kept iterating
                // on a cancelled task, which then issued every remaining
                // network call on a dead Task — each fail-catch was logged
                // as a payload failure and the events stayed queued anyway,
                // but the rest of the app saw a flood of CancellationError
                // log noise and the chrono ordering of "first event keeps
                // its slot" was effectively preserved by accident only.
                cancelledIndex = index
                break
            } catch {
                AppLog.sync.error(
                    "Timeclock drain failed: \(error.localizedDescription, privacy: .public) — keeping in queue"
                )
                remaining.append(event)
            }
        }
        if let start = cancelledIndex {
            remaining.append(contentsOf: pending[start..<pending.count])
        }
        pending = remaining
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        // Serialise + base64-encode so the Keychain (which stores strings via
        // KeychainStore) keeps the JSON intact. When the queue is empty,
        // remove the Keychain entry entirely so an attacker dumping the
        // Keychain doesn't find a stale list of historical clock events.
        if pending.isEmpty {
            try? KeychainStore.shared.remove(.timeclockOfflineQueue)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? KeychainStore.shared.set(data.base64EncodedString(), for: .timeclockOfflineQueue)
    }
}
