import AppIntents
import Core

// MARK: - §21.9 FocusFilterIntent — iOS 16+ AppIntent that lets iOS Focus
// automatically activate per-mode notification policies in BizarreCRM.
//
// Users add this filter in Settings → Focus → <Mode> → App Filters → BizarreCRM.
// When the selected Focus activates, iOS calls the intent's `perform()` to let
// the app know which mode is active (without requiring the restricted
// `com.apple.developer.focus` entitlement for background monitoring).
//
// Driving focus: suppress non-critical pushes automatically.
// Sleep focus: all pushes suppressed except critical.
// Work focus: tickets + communications + admin categories pass.
// Custom per-tenant focus: multi-location tenants can pick specific categories.

/// Lets users configure BizarreCRM's notification behavior inside an iOS Focus.
///
/// Registered as a `FocusFilterIntent` (iOS 16+) so that when a Focus activates,
/// iOS calls the intent and our app suppresses irrelevant notification categories
/// without needing the `com.apple.developer.focus` entitlement.
@available(iOS 16.0, *)
public struct BizarreCRMFocusFilterIntent: FocusFilterIntent {

    // MARK: - FocusFilterIntent

    public static var title: LocalizedStringResource = "BizarreCRM Notifications"
    public static var description: IntentDescription = IntentDescription(
        "Choose which BizarreCRM notification categories surface during this Focus.",
        categoryName: "Notifications"
    )

    // MARK: - Parameters

    /// The notification mode to apply when this Focus is active.
    @Parameter(
        title: "Notification Mode",
        description: "Which categories appear during this Focus mode.",
        default: FocusNotificationMode.assigned
    )
    public var mode: FocusNotificationMode

    /// Optional: restrict to a specific tenant / location (multi-tenant users).
    @Parameter(
        title: "Tenant (optional)",
        description: "Restrict notifications to a specific tenant when using multiple accounts."
    )
    public var tenantSlug: String?

    // MARK: - Init

    public init() {}

    // MARK: - Perform

    /// Called by iOS when the associated Focus activates.
    /// Persists the chosen mode so `NotificationHandler` can gate banners.
    public func perform() async throws -> some IntentResult {
        // Persist active focus mode into UserDefaults so NotificationHandler
        // can read it synchronously in the main-app process.
        let defaults = UserDefaults(suiteName: "group.com.bizarrecrm") ?? .standard
        defaults.set(mode.rawValue, forKey: "activeFocusNotificationMode")
        if let slug = tenantSlug {
            defaults.set(slug, forKey: "activeFocusTenantSlug")
        } else {
            defaults.removeObject(forKey: "activeFocusTenantSlug")
        }
        AppLog.ui.info("BizarreCRMFocusFilterIntent: activated mode=\(mode.rawValue, privacy: .public)")
        return .result()
    }
}

// MARK: - FocusNotificationMode

/// Options exposed to the user inside the iOS Focus filter picker.
@available(iOS 16.0, *)
public enum FocusNotificationMode: String, AppEnum, Sendable {
    /// Only notifications assigned to the signed-in user.
    case assigned = "assigned"
    /// Tickets + communications (for shop-floor staff).
    case workEssentials = "work_essentials"
    /// Only critical alerts (backup failure, security, out-of-stock, card declined).
    case criticalOnly = "critical_only"
    /// All notifications pass — Focus filter has no effect.
    case all = "all"
    /// Suppress everything (sleep / driving mode).
    case none = "none"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Notification Mode")
    }

    public static var caseDisplayRepresentations: [FocusNotificationMode: DisplayRepresentation] {
        [
            .assigned:      DisplayRepresentation(
                title: "My Assigned Only",
                subtitle: "Tickets, SMS, and actions assigned to you"
            ),
            .workEssentials: DisplayRepresentation(
                title: "Work Essentials",
                subtitle: "Tickets, SMS, payments, appointments"
            ),
            .criticalOnly:  DisplayRepresentation(
                title: "Critical Only",
                subtitle: "Backup failures, security alerts, and out-of-stock warnings"
            ),
            .all:           DisplayRepresentation(
                title: "All Notifications",
                subtitle: "Focus filter has no effect on BizarreCRM"
            ),
            .none:          DisplayRepresentation(
                title: "None",
                subtitle: "Suppress all BizarreCRM notifications during this Focus"
            )
        ]
    }
}

// MARK: - FocusFilterActiveReader

/// Reads the currently-active Focus mode setting persisted by `BizarreCRMFocusFilterIntent`.
/// Called from `NotificationHandler` before presenting a foreground banner.
public enum FocusFilterActiveReader {

    private static let defaults = UserDefaults(suiteName: "group.com.bizarrecrm") ?? .standard
    private static let modeKey  = "activeFocusNotificationMode"
    private static let slugKey  = "activeFocusTenantSlug"

    /// The active `FocusNotificationMode`, or `nil` when no Focus is active.
    @available(iOS 16.0, *)
    public static var activeMode: FocusNotificationMode? {
        guard let raw = defaults.string(forKey: modeKey) else { return nil }
        return FocusNotificationMode(rawValue: raw)
    }

    /// The active tenant slug filter, or `nil` when no slug restriction is set.
    public static var activeTenantSlug: String? {
        defaults.string(forKey: slugKey)
    }

    /// Returns `true` when the notification with the given event type should be
    /// shown given the currently-active Focus filter mode.
    ///
    /// - Parameters:
    ///   - eventType: The server event type (e.g. `"ticket.assigned"`).
    ///   - isCritical: Whether the event is marked critical in `NotificationEvent`.
    @available(iOS 16.0, *)
    public static func shouldShow(eventType: String, isCritical: Bool) -> Bool {
        guard let mode = activeMode else { return true } // No filter active → show.
        switch mode {
        case .all:            return true
        case .none:           return isCritical  // Critical always breaks through.
        case .criticalOnly:   return isCritical
        case .assigned:
            // Show only events directly assigned to the user.
            // Server-side assignment check is ideal; client-side approximation
            // uses the "mine" suffix events.
            let mineEvents: Set<String> = [
                "ticket.assigned",
                "ticket.status_change.mine",
                "sms.inbound",
                "mention.note",
                "appointment.reminder.1h",
                "appointment.reminder.24h"
            ]
            return isCritical || mineEvents.contains(eventType)
        case .workEssentials:
            let workEvents: Set<String> = [
                "ticket.assigned",
                "ticket.status_change.mine",
                "ticket.status_change.any",
                "sms.inbound",
                "invoice.paid",
                "payment.declined",
                "appointment.reminder.1h",
                "appointment.reminder.24h",
                "mention.note",
                "backup.failed",
                "security.event",
                "inventory.out_of_stock"
            ]
            return isCritical || workEvents.contains(eventType)
        }
    }
}
