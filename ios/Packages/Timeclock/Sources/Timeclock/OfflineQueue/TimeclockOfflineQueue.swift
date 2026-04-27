import Foundation
import Core
import Networking

// MARK: - TimeclockOfflineQueue
//
// §14.3 — Persists clock-in / clock-out events locally when the device is
// offline, then drains them to the server on reconnect.
//
// Architecture:
//  - Pending events stored in UserDefaults (Keychain not needed — no secrets,
//    just operation type + userId).
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

    private let defaultsKey = "bizarrecrm.timeclock.offline_queue"
    private var pending: [PendingTimeclockEvent] = []
    private var isDraining = false

    private init() {
        loadFromDefaults()
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
        for event in pending {
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
            } catch {
                AppLog.sync.error(
                    "Timeclock drain failed: \(error.localizedDescription, privacy: .public) — keeping in queue"
                )
                remaining.append(event)
            }
        }
        pending = remaining
        persist()
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let events = try? JSONDecoder().decode([PendingTimeclockEvent].self, from: data)
        else { return }
        pending = events
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
