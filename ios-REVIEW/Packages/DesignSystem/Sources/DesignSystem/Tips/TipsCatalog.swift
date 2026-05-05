// DesignSystem/Tips/TipsCatalog.swift
//
// Feature-event-keyed catalog of BrandTip subclasses.
//
// This file is pure data: each struct defines its TipKit events, rules,
// display options, and copy.  No global configuration, no `Tips.configure`,
// no app-shell concerns.  App-shell code imports this module and passes the
// desired tip instance to `TipPresenterView` or the `.brandTip()` modifier.
//
// Feature coverage (§69 milestone events):
//   firstTicketCreated  → FirstTicketTip
//   firstSaleCreated    → FirstSaleTip
//   firstContactAdded   → FirstContactTip
//   firstInvoiceSent    → FirstInvoiceTip
//   firstSmsThreadSent  → FirstSmsThreadTip
//   firstReportViewed   → FirstReportTip
//   kioskModeEnabled    → KioskModeTip
//   roleEdited          → RoleEditorTip
//   auditLogViewed      → AuditLogTip
//   dashboardWidgetAdded → DashboardWidgetTip
//
// §69 In-App Help / Tips

#if canImport(TipKit)
import TipKit

// MARK: - FirstTicketTip

/// Shown the first time the user creates a ticket.
@available(iOS 17, *)
public struct FirstTicketTip: BrandTip {
    public static let firstTicketCreated = Event<TipEventPayload>(
        id: TipParameterKeys.firstTicketCreated
    )

    public var title:   Text   { Text("Ticket Created") }
    public var message: Text?  { Text("Swipe left to archive, long-press for quick actions, or pull down to refresh the list.") }
    public var image:   Image? { Image(systemName: "ticket") }

    public var rules: [Rule] {
        [#Rule(Self.firstTicketCreated) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - FirstSaleTip

/// Shown the first time the user creates a sale.
@available(iOS 17, *)
public struct FirstSaleTip: BrandTip {
    public static let firstSaleCreated = Event<TipEventPayload>(
        id: TipParameterKeys.firstSaleCreated
    )

    public var title:   Text   { Text("First Sale Logged") }
    public var message: Text?  { Text("Great start! Tap the chart icon on the dashboard to track your sales over time.") }
    public var image:   Image? { Image(systemName: "dollarsign.circle") }

    public var rules: [Rule] {
        [#Rule(Self.firstSaleCreated) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - FirstContactTip

/// Shown the first time the user adds a contact.
@available(iOS 17, *)
public struct FirstContactTip: BrandTip {
    public static let firstContactAdded = Event<TipEventPayload>(
        id: TipParameterKeys.firstContactAdded
    )

    public var title:   Text   { Text("Contact Added") }
    public var message: Text?  { Text("Send them an SMS right from BizarreCRM — tap the chat bubble next to their name.") }
    public var image:   Image? { Image(systemName: "person.crop.circle.badge.plus") }

    public var rules: [Rule] {
        [#Rule(Self.firstContactAdded) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - FirstInvoiceTip

/// Shown the first time the user sends an invoice.
@available(iOS 17, *)
public struct FirstInvoiceTip: BrandTip {
    public static let firstInvoiceSent = Event<TipEventPayload>(
        id: TipParameterKeys.firstInvoiceSent
    )

    public var title:   Text   { Text("Invoice Sent") }
    public var message: Text?  { Text("Track payment status here. You'll get a notification when the customer views or pays.") }
    public var image:   Image? { Image(systemName: "doc.text") }

    public var rules: [Rule] {
        [#Rule(Self.firstInvoiceSent) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - FirstSmsThreadTip

/// Shown when the user sends their first SMS thread.
@available(iOS 17, *)
public struct FirstSmsThreadTip: BrandTip {
    public static let firstSmsThreadSent = Event<TipEventPayload>(
        id: TipParameterKeys.firstSmsThreadSent
    )

    public var title:   Text   { Text("SMS Thread Started") }
    public var message: Text?  { Text("Your message is on its way. New replies appear here automatically — no manual refresh needed.") }
    public var image:   Image? { Image(systemName: "bubble.left.and.bubble.right") }

    public var rules: [Rule] {
        [#Rule(Self.firstSmsThreadSent) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - FirstReportTip

/// Shown when the user views a report for the first time.
@available(iOS 17, *)
public struct FirstReportTip: BrandTip {
    public static let firstReportViewed = Event<TipEventPayload>(
        id: TipParameterKeys.firstReportViewed
    )

    public var title:   Text   { Text("Reports") }
    public var message: Text?  { Text("Pinch to zoom on any chart. Tap a data point for the detail breakdown.") }
    public var image:   Image? { Image(systemName: "chart.bar") }

    public var rules: [Rule] {
        [#Rule(Self.firstReportViewed) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - KioskModeTip

/// Shown when the user enables Kiosk Mode.
@available(iOS 17, *)
public struct KioskModeTip: BrandTip {
    public static let kioskModeEnabled = Event<TipEventPayload>(
        id: TipParameterKeys.kioskModeEnabled
    )

    public var title:   Text   { Text("Kiosk Mode Active") }
    public var message: Text?  { Text("Use your manager PIN to exit Kiosk Mode. Set the PIN in Settings → Kiosk.") }
    public var image:   Image? { Image(systemName: "lock.display") }

    public var rules: [Rule] {
        [#Rule(Self.kioskModeEnabled) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - RoleEditorTip

/// Shown the first time a user edits a role.
@available(iOS 17, *)
public struct RoleEditorTip: BrandTip {
    public static let roleEdited = Event<TipEventPayload>(
        id: TipParameterKeys.roleEdited
    )

    public var title:   Text   { Text("Role Permissions") }
    public var message: Text?  { Text("Changes take effect the next time affected users sign in. Roles are scoped per-workspace.") }
    public var image:   Image? { Image(systemName: "person.2.badge.key") }

    public var rules: [Rule] {
        [#Rule(Self.roleEdited) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - AuditLogTip

/// Shown the first time a user opens the Audit Log.
@available(iOS 17, *)
public struct AuditLogTip: BrandTip {
    public static let auditLogViewed = Event<TipEventPayload>(
        id: TipParameterKeys.auditLogViewed
    )

    public var title:   Text   { Text("Audit Log") }
    public var message: Text?  { Text("Every create, update, and delete is recorded here. Tap any entry for a full diff view.") }
    public var image:   Image? { Image(systemName: "list.clipboard") }

    public var rules: [Rule] {
        [#Rule(Self.auditLogViewed) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - DashboardWidgetTip

/// Shown when the user adds their first dashboard widget.
@available(iOS 17, *)
public struct DashboardWidgetTip: BrandTip {
    public static let dashboardWidgetAdded = Event<TipEventPayload>(
        id: TipParameterKeys.dashboardWidgetAdded
    )

    public var title:   Text   { Text("Dashboard Customised") }
    public var message: Text?  { Text("Drag widgets to reorder them. Long-press any widget to resize or remove it.") }
    public var image:   Image? { Image(systemName: "rectangle.3.group") }

    public var rules: [Rule] {
        [#Rule(Self.dashboardWidgetAdded) { $0.donations.count >= 1 }]
    }

    public var options: [any TipOption] { TipDisplayOptions.showOnce }

    public init() {}
}

// MARK: - TipsCatalog namespace

/// Pure-data namespace enumerating all feature-event-keyed tips.
///
/// The app-shell never imports this for global registration.
/// Instead, pass individual tip instances to `TipPresenterView` or
/// the `.brandTip()` view modifier at the relevant screen.
///
/// ```swift
/// // In a TicketDetailView:
/// someButton.brandTip(TipsCatalog.firstTicket)
/// ```
@available(iOS 17, *)
public enum TipsCatalog {
    public static let firstTicket:      FirstTicketTip      = .init()
    public static let firstSale:        FirstSaleTip        = .init()
    public static let firstContact:     FirstContactTip     = .init()
    public static let firstInvoice:     FirstInvoiceTip     = .init()
    public static let firstSmsThread:   FirstSmsThreadTip   = .init()
    public static let firstReport:      FirstReportTip      = .init()
    public static let kioskMode:        KioskModeTip        = .init()
    public static let roleEditor:       RoleEditorTip       = .init()
    public static let auditLog:         AuditLogTip         = .init()
    public static let dashboardWidget:  DashboardWidgetTip  = .init()

    /// All catalog tips as an existential array, useful for iteration in tests.
    public static var all: [any BrandTip] {
        [
            firstTicket,
            firstSale,
            firstContact,
            firstInvoice,
            firstSmsThread,
            firstReport,
            kioskMode,
            roleEditor,
            auditLog,
            dashboardWidget,
        ]
    }
}
#endif // canImport(TipKit)
