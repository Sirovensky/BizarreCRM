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
    /// §32 — A payment capture was approved; properties: `tender`, `amount_cents` (int).
    case paymentApproved      = "payment.approved"
    /// §32 — A payment capture failed; properties: `tender`, `reason` (redacted string).
    case paymentFailed        = "payment.failed"

    // MARK: Hardware

    case drawerKicked         = "hardware.drawer.kicked"
    case receiptPrinted       = "hardware.receipt.printed"
    case barcodeScanned       = "hardware.barcode.scanned"
    case printerError         = "hardware.printer.error"
    /// §32 — Printer came online (USB/Bluetooth/network peripheral reconnected).
    case printerOnline        = "hardware.printer.online"
    /// §32 — Printer went offline (disconnected or powered off).
    case printerOffline       = "hardware.printer.offline"

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

    // MARK: Connectivity

    /// §32 — WebSocket transport connected to the tenant push channel.
    /// Properties: `url_host` (string — hostname only, no path/query), `latency_ms`? (int).
    case webSocketConnected   = "ws.connected"
    /// §32 — WebSocket transport disconnected. Properties: `reason`? (string, machine-readable
    /// close-code label e.g. `"going_away"`, `"protocol_error"`), `code`? (int — RFC 6455 code).
    case webSocketDisconnected = "ws.disconnected"

    // MARK: SMS / Communications

    /// §91.14 — fired when `GET /sms/conversations` response fails JSON decode.
    case smsDecodeFailure     = "sms.conversations.decode_failure"

    // MARK: Error / Crash

    case crashDetected        = "crash.detected"
    case errorPresented       = "error.presented"
    /// §32 — Tenant server responded with a 4xx or 5xx status. Properties:
    /// `endpoint` (path string), `status_code` (int), `error_code`? (string),
    /// `request_id`? (string). Never include response body text — may contain PII.
    case serverErrorReceived  = "server.error.received"
    /// §32 — Tenant server responded with 429 Too Many Requests. Properties:
    /// `endpoint` (path string), `status_code` (int = 429),
    /// `retry_after_seconds`? (int).
    case serverRateLimited    = "server.rate_limited"
    /// §32 — Client timed out waiting for a server response. Properties:
    /// `endpoint` (path string), `timeout_seconds` (double).
    case serverTimeout        = "server.timeout"

    // MARK: Sync / Offline

    case syncQueueDrained     = "sync.queue.drained"
    case offlineFallback      = "offline.fallback"
    case syncConflictResolved = "sync.conflict.resolved"
    /// §32.4 — `sync_start` emitted when a domain sync cycle begins.
    case syncStarted          = "sync.started"
    /// §32.4 — `sync_complete { delta_count, duration_ms }`.
    case syncCompleted        = "sync.completed"
    /// §32.4 — `sync_failed { reason }`.
    case syncFailed           = "sync.failed"

    // MARK: POS — sale lifecycle (§32.4)

    /// §32.4 — `pos_sale_complete { total_cents, tender }`.  No customer PII.
    case posSaleComplete      = "pos.sale.complete"
    /// §32.4 — `pos_sale_failed { reason }`.
    case posSaleFailed        = "pos.sale.failed"

    // MARK: Performance (§32.4)

    /// §32.4 — `cold_launch_ms` — milliseconds from process launch to first frame.
    case coldLaunchMs         = "perf.cold_launch_ms"
    /// §32.4 — `first_paint_ms` — milliseconds from scene activation to first meaningful paint.
    case firstPaintMs         = "perf.first_paint_ms"
    /// §32 — Server response time histogram bucket.
    /// Properties: `endpoint` (string), `duration_ms` (int), `bucket` (string),
    /// `status_code` (int).
    case serverResponseTime   = "perf.server_response_time"

    // MARK: Widgets / Live Activities

    case widgetViewed         = "widget.viewed"
    case liveActivityStarted  = "live_activity.started"
    case liveActivityEnded    = "live_activity.ended"
    case featureFirstUse      = "feature.first_use"

    // MARK: Deep-link attribution

    /// §32 — App was opened via a deep link. Properties:
    /// `source` (string — `"push_notification"`, `"universal_link"`, `"url_scheme"`,
    /// `"spotlight"`, `"widget"`, `"siri_shortcut"`, `"qr_code"`, or `"unknown"`),
    /// `screen`? (string — destination screen name, PII-free).
    case deepLinkAttributed   = "deeplink.attributed"

    // MARK: Device health

    /// §32 — App Store / TestFlight signals an app update is available.
    /// Properties: `current_version` (string), `available_version` (string).
    case appUpdateAvailable   = "app.update_available"

    /// §32 — Device free-disk-space crossed the low threshold (< 500 MB).
    /// Properties: `free_bytes` (int), `threshold_bytes` (int).
    case lowDiskSpace         = "device.low_disk_space"

    /// §32 — `NSCache` received a `UIApplication.didReceiveMemoryWarningNotification` and
    /// evicted its contents. Properties: `cache_name` (string), `evicted_count`? (int).
    case nsCacheMemoryPressure = "device.nscache_memory_pressure"

    // MARK: — Category mapping

    public var category: AnalyticsCategory {
        switch self {
        case .appLaunched, .appBackgrounded, .appForegrounded,
             .sessionStarted, .sessionEnded,
             .appUpdateAvailable:
            return .appLifecycle

        case .screenViewed, .tabSwitched, .deepLinkOpened, .deepLinkAttributed:
            return .navigation

        case .loginAttempted, .loginSucceeded, .loginFailed,
             .signedOut, .pinUnlocked, .pinFailed,
             .passkeyUsed, .twoFactorChallenged:
            return .auth

        case .ticketCreated, .ticketStatusChanged, .ticketAssigned, .ticketClosed,
             .customerCreated, .customerMerged, .customerViewed,
             .saleFinalized, .refundIssued, .cardCharged,
             .discountApplied, .checkoutAbandoned,
             .paymentApproved, .paymentFailed,
             .inventoryAdjusted, .lowStockAlertShown,
             .inventoryItemViewed, .stockCountSubmitted,
             .invoiceCreated, .invoiceSent, .invoicePaid,
             .estimateCreated, .estimateApproved,
             .syncQueueDrained, .offlineFallback, .syncConflictResolved,
             .syncStarted, .syncCompleted, .syncFailed,
             .posSaleComplete, .posSaleFailed,
             .coldLaunchMs, .firstPaintMs, .serverResponseTime,
             .widgetViewed, .liveActivityStarted, .liveActivityEnded, .featureFirstUse:
            return .domain

        case .drawerKicked, .receiptPrinted, .barcodeScanned, .printerError,
             .printerOnline, .printerOffline,
             .lowDiskSpace, .nsCacheMemoryPressure:
            return .hardware

        case .webSocketConnected, .webSocketDisconnected:
            return .appLifecycle

        case .campaignSent, .emailOpened:
            return .marketing

        case .surveySubmitted, .surveyDismissed:
            return .survey

        case .settingChanged, .featureFlagToggled,
             .analyticsOptedIn, .analyticsOptedOut:
            return .settings

        case .helpArticleViewed, .supportEmailSent, .bugReportSubmitted:
            return .support

        case .crashDetected, .errorPresented, .smsDecodeFailure,
             .serverErrorReceived, .serverRateLimited, .serverTimeout:
            return .error
        }
    }
}
