import SwiftUI

// §32.4 — Screen-view + action-tap analytics event taxonomy
// §32 — Screen-view duration histogram buckets
//
// Provides two SwiftUI conveniences:
//   • `.trackScreenView(name:)` — records `screen.viewed` with duration_ms.
//   • `Analytics.trackAction(_:screen:entityId:)` — records `action_tap`.
//
// All calls go through the existing `Analytics.track()` entry point and
// therefore through `SinkDispatcher` → `AnalyticsRedactor` → tenant server.
// No PII passes through these helpers; screen names and action identifiers are
// developer-supplied string literals, not user data.

// MARK: - ScreenDurationBucket

/// §32 — Histogram buckets for screen-view duration.
///
/// Durations are classified into labelled buckets so the server can build a
/// histogram without retaining precise timing (which could act as a
/// quasi-identifier when combined with session data).
///
/// Bucket boundaries (ms):
/// - `flash`    < 500 ms  — user immediately dismissed / navigated back
/// - `glance`   500–2 999 ms  — quick glance
/// - `engaged`  3 000–14 999 ms — normal interaction
/// - `deep`     15 000–59 999 ms — deep reading / filling a form
/// - `marathon` ≥ 60 000 ms — left screen open / background
public enum ScreenDurationBucket: String, Sendable {
    case flash    = "flash"     // < 500 ms
    case glance   = "glance"    // 500–2 999 ms
    case engaged  = "engaged"   // 3 000–14 999 ms
    case deep     = "deep"      // 15 000–59 999 ms
    case marathon = "marathon"  // ≥ 60 000 ms

    /// Classify a raw duration in milliseconds into the appropriate bucket.
    public static func classify(_ durationMs: Int) -> ScreenDurationBucket {
        switch durationMs {
        case ..<500:    return .flash
        case ..<3_000:  return .glance
        case ..<15_000: return .engaged
        case ..<60_000: return .deep
        default:        return .marathon
        }
    }
}

// MARK: - ScreenViewModifier

/// §32.4 — Records `screen.viewed` with `duration_ms` and `duration_bucket`
/// when the view appears/disappears. Attach once per screen-level view.
///
/// The `duration_bucket` property is a histogram label (see `ScreenDurationBucket`)
/// that lets the server aggregate viewing patterns without retaining raw timing.
///
/// ```swift
/// TicketListView()
///     .trackScreenView(name: "tickets.list")
/// ```
public struct ScreenViewModifier: ViewModifier {
    let screenName: String
    @State private var appearTime: Date?

    public init(screenName: String) {
        self.screenName = screenName
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                appearTime = Date()
                Analytics.track(.screenViewed, properties: [
                    "screen": .string(screenName)
                ])
            }
            .onDisappear {
                let durationMs: Int
                if let start = appearTime {
                    durationMs = Int(Date().timeIntervalSince(start) * 1_000)
                } else {
                    durationMs = 0
                }
                let bucket = ScreenDurationBucket.classify(durationMs)
                Analytics.track(.screenViewed, properties: [
                    "screen": .string(screenName),
                    "duration_ms": .int(durationMs),
                    "duration_bucket": .string(bucket.rawValue),
                    "event_subtype": .string("disappear")
                ])
                appearTime = nil
            }
    }
}

// MARK: - View extension

public extension View {
    /// §32.4 — Track `screen.viewed` analytics event with duration for this screen.
    ///
    /// - Parameter name: dot-notation screen identifier, e.g. `"tickets.list"`,
    ///   `"pos.checkout"`, `"customers.detail"`. Never include PII.
    func trackScreenView(name: String) -> some View {
        modifier(ScreenViewModifier(screenName: name))
    }
}

// MARK: - Action + mutation helpers

public extension Analytics {

    /// §32.4 — `action_tap { screen, action, entity_id? }`.
    ///
    /// - Parameters:
    ///   - actionName: Identifies the tapped element, e.g. `"create_ticket"`, `"print_receipt"`.
    ///   - screen: Screen that hosted the action.
    ///   - entityId: Hashed entity identifier (never raw ID from DB). Pass `nil` if N/A.
    static func trackAction(
        _ actionName: String,
        screen: String,
        entityId: String? = nil
    ) {
        var props: [String: AnalyticsValue] = [
            "screen": .string(screen),
            "action": .string(actionName)
        ]
        if let entityId {
            props["entity_id_hash"] = .string(String(entityId.hashValue, radix: 16))
        }
        track(.screenViewed, properties: props)   // reuse event; server groups by props
    }

    /// §32.4 — `mutation_start`.
    static func trackMutationStart(_ entity: String, screen: String) {
        track(.screenViewed, properties: [
            "event_subtype": .string("mutation_start"),
            "entity": .string(entity),
            "screen": .string(screen)
        ])
    }

    /// §32.4 — `mutation_complete { duration_ms }`.
    static func trackMutationComplete(_ entity: String, screen: String, durationMs: Int) {
        track(.screenViewed, properties: [
            "event_subtype": .string("mutation_complete"),
            "entity": .string(entity),
            "screen": .string(screen),
            "duration_ms": .int(durationMs)
        ])
    }

    /// §32.4 — `mutation_failed { reason }`.
    static func trackMutationFailed(_ entity: String, screen: String, reason: String) {
        track(.screenViewed, properties: [
            "event_subtype": .string("mutation_failed"),
            "entity": .string(entity),
            "screen": .string(screen),
            "reason": .string(reason)
        ])
    }

    // MARK: — §32.4 Sync event helpers

    /// §32.4 — `sync_start`.
    static func trackSyncStarted(entity: String) {
        track(.syncStarted, properties: ["entity": .string(entity)])
    }

    /// §32.4 — `sync_complete { delta_count, duration_ms }`.
    static func trackSyncCompleted(entity: String, deltaCount: Int, durationMs: Int) {
        track(.syncCompleted, properties: [
            "entity": .string(entity),
            "delta_count": .int(deltaCount),
            "duration_ms": .int(durationMs)
        ])
    }

    /// §32.4 — `sync_failed { reason }`.
    static func trackSyncFailed(entity: String, reason: String) {
        track(.syncFailed, properties: [
            "entity": .string(entity),
            "reason": .string(reason)
        ])
    }

    // MARK: — §32.4 POS event helpers

    /// §32.4 — `pos_sale_complete { total_cents, tender }`.
    /// - Parameters:
    ///   - totalCents: Integer total in cents — numeric, no PII.
    ///   - tender: Payment method enum string, e.g. `"card"`, `"cash"`, `"gift_card"`.
    static func trackPosSaleComplete(totalCents: Int, tender: String) {
        track(.posSaleComplete, properties: [
            "total_cents": .int(totalCents),
            "tender": .string(tender)
        ])
    }

    /// §32.4 — `pos_sale_failed { reason }`.
    static func trackPosSaleFailed(reason: String) {
        track(.posSaleFailed, properties: ["reason": .string(reason)])
    }

    // MARK: — §32.4 Performance event helpers

    /// §32.4 — `cold_launch_ms`.
    static func trackColdLaunch(durationMs: Int) {
        track(.coldLaunchMs, properties: ["duration_ms": .int(durationMs)])
    }

    /// §32.4 — `first_paint_ms`.
    static func trackFirstPaint(durationMs: Int) {
        track(.firstPaintMs, properties: ["duration_ms": .int(durationMs)])
    }

    // MARK: — §32.4 Auth event helpers

    /// §32.4 — `auth.login.succeeded { method }`.
    ///
    /// - Parameter method: Authentication method used, e.g. `"password"`,
    ///   `"passkey"`, `"pin"`, `"2fa_totp"`. Never include the credential value.
    static func trackLoginSuccess(method: String) {
        track(.loginSucceeded, properties: ["method": .string(method)])
    }

    /// §32.4 — `auth.login.failed { method, reason }`.
    ///
    /// - Parameters:
    ///   - method: Authentication method attempted (same values as `trackLoginSuccess`).
    ///   - reason: Failure category — `"bad_credentials"`, `"account_locked"`,
    ///     `"mfa_required"`, `"server_error"`. No PII.
    static func trackLoginFailed(method: String, reason: String) {
        track(.loginFailed, properties: [
            "method": .string(method),
            "reason": .string(reason)
        ])
    }

    // MARK: — §32.4 Domain entity event helpers

    /// §32.4 — `customer.created { source }`.
    ///
    /// - Parameter source: Where creation originated, e.g. `"pos_checkout"`,
    ///   `"crm_list"`, `"import"`, `"api"`. No PII.
    static func trackCustomerCreated(source: String) {
        track(.customerCreated, properties: ["source": .string(source)])
    }

    /// §32.4 — `ticket.created { priority, channel }`.
    ///
    /// - Parameters:
    ///   - priority: Ticket priority string, e.g. `"low"`, `"normal"`, `"high"`, `"urgent"`.
    ///   - channel: Creation channel, e.g. `"manual"`, `"email"`, `"sms"`, `"api"`.
    static func trackTicketCreated(priority: String, channel: String) {
        track(.ticketCreated, properties: [
            "priority": .string(priority),
            "channel": .string(channel)
        ])
    }

    /// §32.4 — `pos.refund.issued { total_cents, reason }`.
    ///
    /// - Parameters:
    ///   - totalCents: Refund amount in cents — numeric, no PII.
    ///   - reason: Refund reason category, e.g. `"defective"`, `"customer_request"`,
    ///     `"wrong_item"`. Free-form text is NOT accepted here; callers must map
    ///     to an enum string before passing.
    static func trackRefundIssued(totalCents: Int, reason: String) {
        track(.refundIssued, properties: [
            "total_cents": .int(totalCents),
            "reason": .string(reason)
        ])
    }
}
