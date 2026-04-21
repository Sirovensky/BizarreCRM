import Foundation

// §71 Privacy-first analytics event catalog

// MARK: — AnalyticsCategory

/// Top-level grouping for analytics events.
public enum AnalyticsCategory: String, Codable, Sendable, CaseIterable {
    case appLifecycle
    case navigation
    case auth
    case domain
    case hardware
    case marketing
    case survey
    case settings
    case support
    case error
}

// MARK: — AnalyticsEvent

/// Exhaustive catalog of analytics events emitted by BizarreCRM iOS.
///
/// - Raw values use dot-notation (e.g. `"app.launched"`).
/// - No PII is captured automatically; callers are responsible for scrubbing
///   property values via `AnalyticsRedactor` before passing them to `Analytics.track`.
public enum AnalyticsEvent: String, Codable, Sendable, CaseIterable {

    // MARK: App lifecycle

    case appLaunched          = "app.launched"
    case appBackgrounded      = "app.backgrounded"
    case appForegrounded      = "app.foregrounded"
    case sessionStarted       = "session.started"
    case sessionEnded         = "session.ended"

    // MARK: Navigation

    case screenViewed         = "screen.viewed"
    case tabSwitched          = "tab.switched"
    case deepLinkOpened       = "deeplink.opened"

    // MARK: Authentication

    case loginAttempted       = "auth.login.attempted"
    case loginSucceeded       = "auth.login.succeeded"
    case loginFailed          = "auth.login.failed"
    case signedOut            = "auth.signed_out"
    case pinUnlocked          = "auth.pin.unlocked"
    case pinFailed            = "auth.pin.failed"
    case passkeyUsed          = "auth.passkey.used"
    case twoFactorChallenged  = "auth.2fa.challenged"

    // MARK: Tickets

    case ticketCreated        = "ticket.created"
    case ticketStatusChanged  = "ticket.status.changed"
    case ticketAssigned       = "ticket.assigned"
    case ticketClosed         = "ticket.closed"

    // MARK: Customers

    case customerCreated      = "customer.created"
    case customerMerged       = "customer.merged"
    case customerViewed       = "customer.viewed"

    // MARK: POS / Checkout

    case saleFinalized        = "pos.sale.finalized"
    case refundIssued         = "pos.refund.issued"
    case cardCharged          = "pos.card.charged"
    case discountApplied      = "pos.discount.applied"
    case checkoutAbandoned    = "pos.checkout.abandoned"

    // MARK: Hardware

    case drawerKicked         = "hardware.drawer.kicked"
    case receiptPrinted       = "hardware.receipt.printed"
    case barcodeScanned       = "hardware.barcode.scanned"
    case printerError         = "hardware.printer.error"

    // MARK: Inventory

    case inventoryAdjusted    = "inventory.adjusted"
    case lowStockAlertShown   = "inventory.lowstock.shown"
    case inventoryItemViewed  = "inventory.item.viewed"
    case stockCountSubmitted  = "inventory.count.submitted"

    // MARK: Invoices / Estimates

    case invoiceCreated       = "invoice.created"
    case invoiceSent          = "invoice.sent"
    case invoicePaid          = "invoice.paid"
    case estimateCreated      = "estimate.created"
    case estimateApproved     = "estimate.approved"

    // MARK: Marketing

    case campaignSent         = "marketing.campaign.sent"
    case emailOpened          = "marketing.email.opened"

    // MARK: Survey

    case surveySubmitted      = "survey.submitted"
    case surveyDismissed      = "survey.dismissed"

    // MARK: Settings

    case settingChanged       = "settings.changed"
    case featureFlagToggled   = "settings.featureflag.toggled"
    case analyticsOptedIn     = "settings.analytics.opted_in"
    case analyticsOptedOut    = "settings.analytics.opted_out"

    // MARK: Help / Support

    case helpArticleViewed    = "help.article.viewed"
    case supportEmailSent     = "help.support.email.sent"
    case bugReportSubmitted   = "help.bugreport.submitted"

    // MARK: Error / Crash

    case crashDetected        = "crash.detected"
    case errorPresented       = "error.presented"

    // MARK: Sync / Offline

    case syncQueueDrained     = "sync.queue.drained"
    case offlineFallback      = "offline.fallback"
    case syncConflictResolved = "sync.conflict.resolved"

    // MARK: Widgets / Live Activities

    case widgetViewed         = "widget.viewed"
    case liveActivityStarted  = "live_activity.started"
    case liveActivityEnded    = "live_activity.ended"
    case featureFirstUse      = "feature.first_use"

    // MARK: — Category mapping

    public var category: AnalyticsCategory {
        switch self {
        case .appLaunched, .appBackgrounded, .appForegrounded,
             .sessionStarted, .sessionEnded:
            return .appLifecycle

        case .screenViewed, .tabSwitched, .deepLinkOpened:
            return .navigation

        case .loginAttempted, .loginSucceeded, .loginFailed,
             .signedOut, .pinUnlocked, .pinFailed,
             .passkeyUsed, .twoFactorChallenged:
            return .auth

        case .ticketCreated, .ticketStatusChanged, .ticketAssigned, .ticketClosed,
             .customerCreated, .customerMerged, .customerViewed,
             .saleFinalized, .refundIssued, .cardCharged,
             .discountApplied, .checkoutAbandoned,
             .inventoryAdjusted, .lowStockAlertShown,
             .inventoryItemViewed, .stockCountSubmitted,
             .invoiceCreated, .invoiceSent, .invoicePaid,
             .estimateCreated, .estimateApproved,
             .syncQueueDrained, .offlineFallback, .syncConflictResolved,
             .widgetViewed, .liveActivityStarted, .liveActivityEnded, .featureFirstUse:
            return .domain

        case .drawerKicked, .receiptPrinted, .barcodeScanned, .printerError:
            return .hardware

        case .campaignSent, .emailOpened:
            return .marketing

        case .surveySubmitted, .surveyDismissed:
            return .survey

        case .settingChanged, .featureFlagToggled,
             .analyticsOptedIn, .analyticsOptedOut:
            return .settings

        case .helpArticleViewed, .supportEmailSent, .bugReportSubmitted:
            return .support

        case .crashDetected, .errorPresented:
            return .error
        }
    }
}
