import Foundation

// MARK: - NotificationCategoryMapper

/// Maps server-side `type` strings to display categories for filter chips
/// and list section headers. Keeps the mapping logic in one place so
/// `NotificationTypeFilter` (list-chip side) and any analytics/routing
/// can share the same rules.
///
/// This file is intentionally a pure value-type namespace with no side effects.
public enum NotificationCategoryMapper {

    // MARK: - Public API

    /// Returns the `NotificationTypeFilter` bucket for a server notification type string.
    /// Returns `.system` when the type is unknown or nil.
    public static func typeFilter(for serverType: String?) -> NotificationTypeFilter {
        guard let t = serverType?.lowercased() else { return .system }
        for filter in NotificationTypeFilter.allCases {
            if filter.matches(t) { return filter }
        }
        return .system
    }

    /// Human-readable section label for a server type string.
    public static func sectionLabel(for serverType: String?) -> String {
        typeFilter(for: serverType).displayName
    }

    /// SF Symbol name for a server notification type string.
    public static func icon(for serverType: String?) -> String {
        let t = serverType?.lowercased() ?? ""
        if t.contains("ticket")             { return "wrench.and.screwdriver" }
        if t.contains("sms")                { return "message" }
        if t.contains("invoice")
            || t.contains("estimate")       { return "doc.text" }
        if t.contains("payment")
            || t.contains("refund")         { return "creditcard" }
        if t.contains("appoint")            { return "calendar" }
        if t.contains("mention")            { return "at" }
        if t.contains("inventory")
            || t.contains("stock")          { return "shippingbox" }
        if t.contains("security")           { return "lock.shield" }
        if t.contains("backup")             { return "arrow.clockwise.icloud" }
        return "bell"
    }

    /// Returns `true` when the notification type indicates a critical event that
    /// should interrupt quiet hours.
    public static func isCritical(serverType: String?) -> Bool {
        guard let t = serverType?.lowercased() else { return false }
        return t.contains("security") || t.contains("backup.fail")
            || t.contains("out_of_stock") || t.contains("payment.declined")
    }
}
