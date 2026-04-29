import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App-Group UserDefaults key for the serialized `WidgetSnapshot`.
private let kSnapshotKey = "com.bizarrecrm.widget.snapshot"

/// App-Group UserDefaults key for the widget refresh interval (in minutes).
private let kRefreshIntervalKey = "com.bizarrecrm.widget.refreshInterval"

/// App-Group UserDefaults key for the "Live Activities enabled" flag.
private let kLiveActivitiesEnabledKey = "com.bizarrecrm.widget.liveActivitiesEnabled"

/// Writes widget data into the shared App Group UserDefaults
/// (`group.com.bizarrecrm`) and triggers a WidgetCenter timeline reload.
///
/// - Important: This actor must be called from the **main app process only**.
///   The widget extension reads the same UserDefaults suite but never writes.
///
/// App Group entitlement required in `BizarreCRM.entitlements`:
/// ```xml
/// <key>com.apple.security.application-groups</key>
/// <array>
///   <string>group.com.bizarrecrm</string>
/// </array>
/// ```
public actor WidgetDataStore {

    // MARK: - Types

    public enum Error: Swift.Error, Sendable {
        case appGroupUnavailable
        case encodingFailed(Swift.Error)
    }

    /// Supported refresh intervals (minutes).
    public enum RefreshInterval: Int, CaseIterable, Sendable {
        case fiveMinutes = 5
        case fifteenMinutes = 15
        case thirtyMinutes = 30
    }

    // MARK: - Properties

    private let suiteName: String
    private let defaults: UserDefaults

    // MARK: - Init

    /// - Parameter suiteName: App Group identifier. Defaults to `group.com.bizarrecrm`.
    public init(suiteName: String = "group.com.bizarrecrm") throws {
        guard let ud = UserDefaults(suiteName: suiteName) else {
            throw Error.appGroupUnavailable
        }
        self.suiteName = suiteName
        self.defaults = ud
    }

    // MARK: - Write

    /// Encode and persist `snapshot` to the shared App Group defaults,
    /// then request a full widget timeline reload.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            throw Error.encodingFailed(error)
        }
        defaults.set(data, forKey: kSnapshotKey)
        reloadAllTimelines()
    }

    // MARK: - Read

    /// Decode and return the last persisted `WidgetSnapshot`, or `nil` if none exists.
    public func read() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: kSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Settings

    /// Refresh interval preference written by `WidgetSettingsView`.
    public var refreshInterval: RefreshInterval {
        let raw = defaults.integer(forKey: kRefreshIntervalKey)
        return RefreshInterval(rawValue: raw) ?? .fifteenMinutes
    }

    /// Persist a new refresh interval.
    public func set(refreshInterval: RefreshInterval) {
        defaults.set(refreshInterval.rawValue, forKey: kRefreshIntervalKey)
    }

    /// Whether Live Activities are enabled (user preference from `WidgetSettingsView`).
    public var liveActivitiesEnabled: Bool {
        defaults.bool(forKey: kLiveActivitiesEnabledKey)
    }

    /// Persist the Live Activities enabled flag.
    public func set(liveActivitiesEnabled enabled: Bool) {
        defaults.set(enabled, forKey: kLiveActivitiesEnabledKey)
    }

    // MARK: - Scheduled refresh

    /// Keys used to persist scheduled-refresh state.
    private static let kNextScheduledRefreshKey = "com.bizarrecrm.widget.nextScheduledRefresh"

    /// Compute and store the next scheduled refresh date based on the current
    /// `refreshInterval`, then request a timeline reload from WidgetKit.
    ///
    /// Call this after `write(_:)` completes to update the stored schedule, or
    /// call it standalone when a background push notification arrives indicating
    /// new data is available (`content-available: 1`).
    ///
    /// The stored date is purely informational (e.g. for a `WidgetSettingsView`
    /// "Next refresh: 3:15 PM" label) — WidgetKit enforces its own rate limits
    /// via `Timeline.policy`.
    public func scheduleNextRefresh() {
        let intervalSeconds = TimeInterval(refreshInterval.rawValue * 60)
        let next = Date(timeIntervalSinceNow: intervalSeconds)
        defaults.set(next, forKey: Self.kNextScheduledRefreshKey)
        reloadAllTimelines()
    }

    /// The stored date of the next scheduled widget refresh, or `nil` if not set.
    public var nextScheduledRefresh: Date? {
        defaults.object(forKey: Self.kNextScheduledRefreshKey) as? Date
    }

    /// Reload only the specified widget kinds instead of all timelines.
    /// Use this for targeted reloads when only specific data changed.
    public func reload(kinds: [String]) {
        #if canImport(WidgetKit)
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        #endif
    }

    // MARK: - Background push-triggered refresh

    /// Call from `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
    /// when a silent push with `content-available: 1` arrives and `aps.category` is
    /// `"WIDGET_REFRESH"`. Writes the provided snapshot and reschedules the timeline.
    ///
    /// - Returns: The written snapshot so callers can confirm success.
    @discardableResult
    public func handleBackgroundRefreshPush(_ snapshot: WidgetSnapshot) throws -> WidgetSnapshot {
        try write(snapshot)
        scheduleNextRefresh()
        return snapshot
    }

    // MARK: - Private helpers

    private func reloadAllTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
