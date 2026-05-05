import Foundation
import Core

// MARK: - Shared App Group reader for widget extension

/// Thin read-only wrapper the widget extension uses to access `WidgetSnapshot`
/// from the App Group UserDefaults suite written by the main app's `WidgetDataStore`.
///
/// The widget extension never calls `WidgetCenter.shared.reloadAllTimelines()` —
/// only the main app does.  This file is compiled into the widget extension target
/// only (not the main app).
enum WidgetSharedStore {
    private static let suiteName = "group.com.bizarrecrm"

    /// The snapshot written by the main app on the last sync, or `nil` if unavailable.
    static var snapshot: WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: "com.bizarrecrm.widget.snapshot")
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Refresh interval (minutes) set by admin in `WidgetSettingsView`.
    static var refreshIntervalMinutes: Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return 15
        }
        let raw = defaults.integer(forKey: "com.bizarrecrm.widget.refreshInterval")
        return (raw > 0) ? raw : 15
    }
}
