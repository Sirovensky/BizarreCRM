import Foundation

// MARK: - MembershipStatus

/// §38 — Lifecycle state of a customer membership.
public enum MembershipStatus: String, Codable, Sendable, CaseIterable {
    /// Paid and active; perks apply at checkout.
    case active
    /// Temporarily paused; perks suspended.
    case paused
    /// Terminated; no perks, no billing.
    case cancelled
    /// Server created but awaiting first payment confirmation.
    case pending
    /// Expired and within grace period (7 days default).
    case gracePeriod = "grace_period"
    /// Past grace period; benefits suspended until reactivation.
    case expired

    public var displayName: String {
        switch self {
        case .active:       return "Active"
        case .paused:       return "Paused"
        case .cancelled:    return "Cancelled"
        case .pending:      return "Pending"
        case .gracePeriod:  return "Grace Period"
        case .expired:      return "Expired"
        }
    }

    /// `true` when perks should apply at POS checkout.
    public var perksActive: Bool {
        switch self {
        case .active, .gracePeriod: return true
        case .paused, .cancelled, .pending, .expired: return false
        }
    }
}

// MARK: - Membership

/// §38 — Customer subscription to a `MembershipPlan`.
///
/// Immutable value type. Updates are modelled as new values
/// (copy-and-mutate pattern enforced by the struct boundary).
///
/// Server contract: `GET /memberships/:id` → `Membership`.
public struct Membership: Codable, Sendable, Identifiable, Equatable {

    public let id: String
    public let customerId: String
    public let planId: String
    public let status: MembershipStatus
    public let startDate: Date
    public let endDate: Date?
    public let autoRenew: Bool
    public let nextBillingAt: Date?

    public init(
        id: String,
        customerId: String,
        planId: String,
        status: MembershipStatus,
        startDate: Date,
        endDate: Date? = nil,
        autoRenew: Bool = true,
        nextBillingAt: Date? = nil
    ) {
        self.id = id
        self.customerId = customerId
        self.planId = planId
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.autoRenew = autoRenew
        self.nextBillingAt = nextBillingAt
    }

    // MARK: - Derived copy helpers (immutable updates)

    public func withStatus(_ newStatus: MembershipStatus) -> Membership {
        Membership(
            id: id,
            customerId: customerId,
            planId: planId,
            status: newStatus,
            startDate: startDate,
            endDate: endDate,
            autoRenew: autoRenew,
            nextBillingAt: nextBillingAt
        )
    }

    public func withAutoRenew(_ value: Bool) -> Membership {
        Membership(
            id: id,
            customerId: customerId,
            planId: planId,
            status: status,
            startDate: startDate,
            endDate: endDate,
            autoRenew: value,
            nextBillingAt: nextBillingAt
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case customerId    = "customer_id"
        case planId        = "plan_id"
        case status
        case startDate     = "start_date"
        case endDate       = "end_date"
        case autoRenew     = "auto_renew"
        case nextBillingAt = "next_billing_at"
    }
}
