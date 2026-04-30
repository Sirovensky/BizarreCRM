import Foundation
import Core

// MARK: - §70 Historical push notification store (last 100 pushes for audit)

/// A single historical push record.
public struct RecentPushRecord: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    /// ISO-8601 timestamp of receipt.
    public let receivedAt: Date
    /// APNs category identifier.
    public let categoryID: String
    /// Notification title as delivered.
    public let title: String
    /// Notification body as delivered.
    public let body: String
    /// Entity ID extracted from the push payload (ticket ID, invoice ID, etc.)
    public let entityID: String?
    /// `event_type` field from payload, e.g. `"ticket.assigned"`.
    public let eventType: String?

    public init(
        id: UUID = UUID(),
        receivedAt: Date = Date(),
        categoryID: String,
        title: String,
        body: String,
        entityID: String? = nil,
        eventType: String? = nil
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.categoryID = categoryID
        self.title = title
        self.body = body
        self.entityID = entityID
        self.eventType = eventType
    }
}

// MARK: - RecentPushStore

/// Persists the last `maxCount` push records in `UserDefaults`.
///
/// Called from `NotificationHandler.userNotificationCenter(_:didReceive:...)`
/// so every tapped or delivered push is logged before routing the action.
///
/// Cap: 100 entries.  Oldest entries are evicted when the cap is exceeded.
public actor RecentPushStore {

    // MARK: - Shared

    nonisolated(unsafe) public static let shared = RecentPushStore()

    // MARK: - Constants

    public static let maxCount = 100
    private static let udKey = "com.bizarrecrm.push.recentHistory"

    // MARK: - State

    private var records: [RecentPushRecord] = []
    private var loaded = false
    private let defaults: UserDefaults

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Append a new record.  Evicts oldest when over cap.
    public func append(_ record: RecentPushRecord) {
        ensureLoaded()
        records.insert(record, at: 0)
        if records.count > Self.maxCount {
            records = Array(records.prefix(Self.maxCount))
        }
        persist()
    }

    /// Convenience: build a record from raw APNs `userInfo` and notification content.
    public func record(
        title: String,
        body: String,
        categoryID: String,
        userInfo: [AnyHashable: Any]
    ) {
        let entityID = userInfo["entityId"] as? String ?? userInfo["entity_id"] as? String
        let eventType = userInfo["event_type"] as? String
        let rec = RecentPushRecord(
            receivedAt: Date(),
            categoryID: categoryID,
            title: title,
            body: body,
            entityID: entityID,
            eventType: eventType
        )
        append(rec)
    }

    /// Return all stored records (newest first).
    public func all() -> [RecentPushRecord] {
        ensureLoaded()
        return records
    }

    /// Clear all stored records.
    public func clearAll() {
        records = []
        defaults.removeObject(forKey: Self.udKey)
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = defaults.data(forKey: Self.udKey),
              let decoded = try? JSONDecoder().decode([RecentPushRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.udKey)
    }
}
