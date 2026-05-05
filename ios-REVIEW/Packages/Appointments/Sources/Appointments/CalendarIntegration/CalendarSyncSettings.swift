import Foundation

// MARK: - CalendarSyncSettings

/// Persists the user's opt-in for EventKit calendar write-through.
///
/// Stored in `UserDefaults` under the shared App Group suite so the widget
/// extension can read the same value. Falls back to standard defaults when
/// the suite is unavailable (unit tests, macOS Catalyst).
///
/// Usage:
/// ```swift
/// // Read
/// if CalendarSyncSettings.isEnabled { … }
/// // Write
/// CalendarSyncSettings.isEnabled = true
/// ```
public enum CalendarSyncSettings: Sendable {

    private static let key = "com.bizarrecrm.calendarSyncEnabled"
    private static let suiteName = "group.com.bizarrecrm"

    private static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// `true` if the user has opted in to EventKit calendar write-through.
    /// Defaults to `false` (opt-in, never silent).
    public static var isEnabled: Bool {
        get { store.bool(forKey: key) }
        set { store.set(newValue, forKey: key) }
    }

    /// Resets the setting to its default (`false`). Useful in tests.
    public static func reset() {
        store.removeObject(forKey: key)
    }
}
