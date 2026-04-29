import SwiftUI

// §32.4 — Screen-view + action-tap analytics event taxonomy
//
// Provides two SwiftUI conveniences:
//   • `.trackScreenView(name:)` — records `screen.viewed` with duration_ms.
//   • `Analytics.trackAction(_:screen:entityId:)` — records `action_tap`.
//
// All calls go through the existing `Analytics.track()` entry point and
// therefore through `SinkDispatcher` → `AnalyticsRedactor` → tenant server.
// No PII passes through these helpers; screen names and action identifiers are
// developer-supplied string literals, not user data.

// MARK: - ScreenViewModifier

/// §32.4 — Records `screen.viewed` with `duration_ms` when the view
/// appears/disappears. Attach once per screen-level view.
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
                Analytics.track(.screenViewed, properties: [
                    "screen": .string(screenName),
                    "duration_ms": .int(durationMs),
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
}
