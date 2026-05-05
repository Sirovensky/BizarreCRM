import Foundation

// MARK: - HandoffEligibility

/// Rules that determine whether a `DeepLinkDestination` may be advertised
/// via `NSUserActivity` Handoff.
///
/// ## Eligible screens
/// - Ticket detail
/// - Customer detail
/// - Invoice detail
/// - Estimate detail
///
/// ## Excluded screens
/// - Auth flows (magic link) — token is single-use and device-specific
/// - POS screens — cart state is local; continuing on another device would
///   produce a stale or empty cart
/// - Settings & audit logs — administrative; session-scoped
/// - Timeclock — user-specific punch-in state; not transferable
/// - SMS threads — message drafts live locally (see `DraftStore`)
/// - Search — ephemeral; the user can re-type the query
/// - Dashboard, notifications, reports — no unique record identity
/// - Leads & appointments — not in the primary Handoff surface (may be
///   promoted in a future wave)
/// - Inventory — SKU detail is read-only reference; low Handoff value
///
/// Thread-safe: stateless enum.
public enum HandoffEligibility {

    // MARK: - Public API

    /// Returns `true` when `destination` may be surfaced via Handoff.
    public static func isEligible(_ destination: DeepLinkDestination) -> Bool {
        HandoffActivityType(destination: destination) != nil
    }

    /// Returns the `HandoffActivityType` for `destination`, or `nil` when
    /// the destination is not Handoff-eligible.
    public static func activityType(
        for destination: DeepLinkDestination
    ) -> HandoffActivityType? {
        HandoffActivityType(destination: destination)
    }

    // MARK: - Rejection reasons (for diagnostics / logging)

    /// A human-readable explanation of why `destination` is not eligible
    /// for Handoff.  Returns `nil` when the destination *is* eligible.
    public static func rejectionReason(
        for destination: DeepLinkDestination
    ) -> String? {
        guard !isEligible(destination) else { return nil }

        switch destination {
        case .magicLink:
            return "Auth tokens are single-use and must not be transferred"
        case .posRoot, .posNewCart, .posReturn:
            return "POS cart state is local and cannot be continued on another device"
        case .settings, .auditLogs:
            return "Administrative settings are session-scoped"
        case .timeclock:
            return "Timeclock punch state is user-specific and not transferable"
        case .smsThread:
            return "SMS draft state is stored locally via DraftStore"
        case .search:
            return "Search queries are ephemeral"
        case .dashboard, .notifications, .reports:
            return "Destination has no unique record identity suitable for Handoff"
        case .lead, .appointment:
            return "Not included in the current Handoff surface (future wave)"
        case .inventory:
            return "Inventory SKU detail is read-only reference with low Handoff value"
        case .ticket, .customer, .invoice, .estimate:
            // Should not reach here — these are eligible.
            return nil
        case .resetPassword, .setupInvite:
            return "Auth flows are single-use and must not be transferred via Handoff"
        }
    }
}
