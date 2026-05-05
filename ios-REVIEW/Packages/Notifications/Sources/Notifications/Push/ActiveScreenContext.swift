import Foundation
import Core

// MARK: - §70.3 Active-screen context — suppress in-app banners for the current source

/// Thread-safe registry of the currently active entity context.
///
/// Feature views call `ActiveScreenContext.shared.setActive(entity:id:)` on
/// `onAppear` and clear it on `onDisappear`.  The toast overlay in
/// `RealtimeUX.wsToastOverlay(…)` calls `shouldShow(notification:)` before
/// displaying a banner — if the user is already looking at the same entity,
/// the banner is suppressed (§70.3).
///
/// ## Usage (in a feature view)
/// ```swift
/// .onAppear {
///     ActiveScreenContext.shared.setActive(entity: "sms_thread", id: threadId)
/// }
/// .onDisappear {
///     ActiveScreenContext.shared.clearActive(entity: "sms_thread", id: threadId)
/// }
/// ```
@MainActor
public final class ActiveScreenContext: Sendable {

    // MARK: - Shared

    public static let shared = ActiveScreenContext()

    // MARK: - State

    /// Keyed by entity type → set of entity IDs currently on screen.
    private var activeEntities: [String: Set<String>] = [:]

    // MARK: - Init

    public init() {}

    // MARK: - Registration

    /// Register that the user is actively viewing `id` for `entity` type.
    public func setActive(entity: String, id: String) {
        var ids = activeEntities[entity, default: Set()]
        ids.insert(id)
        activeEntities[entity] = ids
    }

    /// Remove the entity/id from the active set (called from `onDisappear`).
    public func clearActive(entity: String, id: String) {
        activeEntities[entity]?.remove(id)
        if activeEntities[entity]?.isEmpty == true {
            activeEntities.removeValue(forKey: entity)
        }
    }

    // MARK: - Suppression check

    /// Returns `true` when the user is already looking at the source of the
    /// notification, meaning the in-app banner should be suppressed.
    ///
    /// - Parameters:
    ///   - entityType: The `entity_type` from the APNs payload (e.g. `"sms_thread"`, `"ticket"`).
    ///   - entityId: The `entity_id` from the APNs payload.
    public func isSuppressed(entityType: String, entityId: String) -> Bool {
        activeEntities[entityType]?.contains(entityId) == true
    }

    /// Convenience overload accepting the raw push payload keys.
    public func isSuppressed(payload: [String: Any]) -> Bool {
        guard
            let entityType = payload["entity_type"] as? String,
            let entityId   = payload["entity_id"]   as? String
        else { return false }
        return isSuppressed(entityType: entityType, entityId: entityId)
    }
}

// MARK: - §70.3 Push-collapse deduplicator (same event within 60 s → badge +N)

/// Collapses repeated same-type pushes within a 60-second window into a
/// "+N more" badge update rather than delivering a second alert.
///
/// ## Algorithm
/// - Key = `(categoryID, entityId?)` tuple.
/// - First push within the window: deliver normally, store (key → timestamp, count=1).
/// - Subsequent pushes within 60 s: suppress alert; increment count; post
///   `.notificationBundleUpdated` so the badge layer can show "+N more".
/// - After the window expires the entry is evicted; the next push starts fresh.
public actor PushCollapseWindow {

    // MARK: - Shared

    public static let shared = PushCollapseWindow()

    // MARK: - Constants

    /// Pushes within this many seconds of the first are collapsed.
    public let windowSeconds: TimeInterval

    // MARK: - State

    private struct Entry {
        var firstSeen: Date
        var count: Int
    }

    private var table: [String: Entry] = [:]

    // MARK: - Init

    public init(windowSeconds: TimeInterval = 60) {
        self.windowSeconds = windowSeconds
    }

    // MARK: - Public API

    /// Returns `(shouldDeliver: Bool, collapseCount: Int)`.
    ///
    /// - `shouldDeliver == true` → first in window; show alert normally.
    /// - `shouldDeliver == false` → collapsed; `collapseCount` is total suppressed so far.
    public func receive(categoryID: String, entityId: String?) -> (shouldDeliver: Bool, collapseCount: Int) {
        evictExpired()
        let key = makeKey(categoryID: categoryID, entityId: entityId)
        let now = Date()
        if var entry = table[key] {
            entry.count += 1
            table[key] = entry
            AppLog.sync.debug(
                "PushCollapseWindow: collapsed push key=\(key, privacy: .private) count=\(entry.count)"
            )
            // Post notification so badge layer can update "+N more" display.
            let count = entry.count
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .pushCollapseCountUpdated,
                    object: nil,
                    userInfo: ["key": key, "count": count]
                )
            }
            return (false, entry.count)
        } else {
            table[key] = Entry(firstSeen: now, count: 1)
            return (true, 1)
        }
    }

    /// Reset all entries (e.g. on logout).
    public func reset() {
        table = [:]
    }

    // MARK: - Private

    private func makeKey(categoryID: String, entityId: String?) -> String {
        "\(categoryID)/\(entityId ?? "*")"
    }

    private func evictExpired() {
        let cutoff = Date().timeIntervalSinceReferenceDate - windowSeconds
        table = table.filter { $0.value.firstSeen.timeIntervalSinceReferenceDate >= cutoff }
    }
}

// MARK: - Notification name

public extension Notification.Name {
    /// Posted by `PushCollapseWindow` when a push is collapsed.
    /// `userInfo` contains `"key": String, "count": Int`.
    static let pushCollapseCountUpdated = Notification.Name("com.bizarrecrm.push.collapseCountUpdated")
}
