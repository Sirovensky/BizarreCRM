import Foundation

// §32.5 Crash recovery pipeline — Settings keys
// Phase 11

/// UserDefaults keys for crash reporting opt-in toggle.
public enum CrashReportingDefaults {
    /// `Bool` key. `true` = admin has opted in to automatic crash reporting.
    public static let enabledKey = "com.bizarrecrm.crashReporting.enabled"
}
