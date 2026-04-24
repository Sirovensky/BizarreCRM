// DesignSystem/Tips/TipDisplayRules.swift
//
// Factory helpers for common TipKit eligibility rules.
//
// TipKit `#Rule` macros are always written at the tip struct's declaration
// site (the macro expands into property wrappers bound to the enclosing type),
// so we cannot manufacture `Rule` values generically.
//
// This file therefore provides:
//   • `TipDisplayThreshold` — typed constants used as the threshold values
//     inside `#Rule(...)` expressions, keeping magic numbers out of tip bodies.
//   • `TipDisplayOptions` — typed helpers that produce `TipOption` arrays for
//     the most common display-frequency patterns.
//   • `TipParameterKeys` — string constants that guard against typos in Event IDs.
//
// Usage in a tip struct:
// ```swift
// @available(iOS 17, *)
// struct FirstTicketTip: BrandTip {
//     static let firstTicketCreated = Event<TipEventPayload>(
//         id: TipParameterKeys.firstTicketCreated
//     )
//     var rules: [Rule] {
//         [#Rule(Self.firstTicketCreated) {
//             $0.donations.count >= TipDisplayThreshold.afterFirstEvent
//         }]
//     }
//     var options: [any TipOption] { TipDisplayOptions.showOnce }
//     var title:   Text   { Text("Your first ticket") }
//     var message: Text?  { Text("Tip body here.") }
//     var image:   Image? { Image(systemName: "ticket") }
//     public init() {}
// }
// ```
//
// §69 In-App Help / Tips

#if canImport(TipKit)
import TipKit

// MARK: - TipDisplayThreshold

/// Integer thresholds used inside `#Rule(...)` event donation counts.
///
/// Keeping these as named constants ensures all tips agree on what
/// "show after first event", "show after three launches", etc. means.
public enum TipDisplayThreshold {
    /// Show after the triggering event is donated at least once.
    public static let afterFirstEvent: Int = 1
    /// Show after the triggering event is donated at least three times.
    public static let afterThreeLaunches: Int = 3
    /// Show after the triggering event is donated at least five times.
    public static let afterFiveLaunches: Int = 5
}

// MARK: - TipDisplayOptions

/// Pre-built `TipOption` arrays for the most common display-frequency patterns.
///
/// Pass the chosen array directly to the `var options` property of a `BrandTip`:
/// ```swift
/// var options: [any TipOption] { TipDisplayOptions.showOnce }
/// ```
@available(iOS 17, *)
public enum TipDisplayOptions {
    /// Display the tip at most once, ever.
    public static var showOnce: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    /// Display the tip at most twice (e.g. once on phone, once on iPad).
    public static var showTwice: [any TipOption] {
        [Tips.MaxDisplayCount(2)]
    }

    /// Display the tip up to three times, with no frequency constraint.
    public static var showThreeTimes: [any TipOption] {
        [Tips.MaxDisplayCount(3)]
    }

    /// Display the tip immediately when eligible (bypasses the daily-frequency cap).
    /// Use sparingly — prefer `showOnce` for most tips.
    public static var showImmediately: [any TipOption] {
        [Tips.MaxDisplayCount(1)]
    }
}

// MARK: - TipParameterKeys

/// String constants for TipKit `Event` IDs.
///
/// Using constants rather than inline string literals prevents silent mismatches
/// between the tip that defines an event and external code that donates to it.
public enum TipParameterKeys {
    // Lifecycle events
    public static let appLaunchedForCommandPalette = "app_launched_for_command_palette"
    public static let appLaunchedForPullRefresh    = "app_launched_for_pull_refresh"

    // Feature-discovery events
    public static let ticketsListViewed  = "tickets_list_viewed"
    public static let listRowViewed      = "list_row_viewed_for_context_menu"
    public static let skuFieldViewed     = "sku_field_viewed"

    // Business-event milestones
    public static let firstTicketCreated = "first_ticket_created"
    public static let firstSaleCreated   = "first_sale_created"
    public static let firstContactAdded  = "first_contact_added"
    public static let firstInvoiceSent   = "first_invoice_sent"
    public static let firstSmsThreadSent = "first_sms_thread_sent"
    public static let firstReportViewed  = "first_report_viewed"
    public static let kioskModeEnabled   = "kiosk_mode_enabled"
    public static let roleEdited         = "role_edited"
    public static let auditLogViewed     = "audit_log_viewed"
    public static let dashboardWidgetAdded = "dashboard_widget_added"
}
#endif // canImport(TipKit)
