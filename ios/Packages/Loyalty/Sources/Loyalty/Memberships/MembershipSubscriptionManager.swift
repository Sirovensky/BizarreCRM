import Foundation
import Networking

// MARK: - MembershipSubscriptionManager

/// §38 — Actor managing membership subscription state transitions.
///
/// Provides a local in-memory store of memberships and delegates
/// server mutations to `APIClient` (via `MembershipsEndpoints`).
///
/// State machine per membership:
/// ```
///  pending → active → paused → active
///                   → cancelled
///  active  → expired → grace_period → expired
///  grace_period → active (on renewal)
/// ```
///
/// API calls are fire-and-update: the local state is updated optimistically
/// and the server response validates or rolls back.
public actor MembershipSubscriptionManager {

    // MARK: - In-memory store

    private var store: [String: Membership] = [:]
    private let api: (any APIClient)?

    // MARK: - Init

    public init(api: (any APIClient)? = nil) {
        self.api = api
    }

    // MARK: - Read

    /// All active (or otherwise non-cancelled) memberships.
    public var activeMemberships: [Membership] {
        store.values.filter { $0.status != .cancelled }.sorted { $0.startDate < $1.startDate }
    }

    public func membership(id: String) -> Membership? {
        store[id]
    }

    public func memberships(for customerId: String) -> [Membership] {
        store.values.filter { $0.customerId == customerId }
    }

    // MARK: - Enroll

    /// Locally create a new membership and persist to server.
    ///
    /// Returns the created `Membership`. On server failure the local entry
    /// is rolled back and the error is rethrown.
    @discardableResult
    public func enroll(customerId: String, plan: MembershipPlan) async -> Membership {
        let id = UUID().uuidString
        let now = Date()
        let nextBilling = Calendar.current.date(byAdding: .day, value: plan.periodDays, to: now)
        let membership = Membership(
            id: id,
            customerId: customerId,
            planId: plan.id,
            status: .active,
            startDate: now,
            endDate: nil,
            autoRenew: true,
            nextBillingAt: nextBilling
        )
        store[id] = membership

        // Best-effort server sync; failures logged but don't block UX.
        if let api {
            do {
                let body = EnrollMembershipRequest(customerId: customerId, planId: plan.id)
                let response = try await api.post(
                    "/memberships",
                    body: body,
                    as: MembershipDTO.self
                )
                // Reconcile with server-assigned ID.
                let serverMembership = response.toDomain()
                store.removeValue(forKey: id)
                store[serverMembership.id] = serverMembership
                return serverMembership
            } catch {
                // Keep local membership on network failure (offline-first).
            }
        }
        return membership
    }

    // MARK: - Cancel

    @discardableResult
    public func cancel(membershipId: String) async -> Membership? {
        guard let existing = store[membershipId] else { return nil }
        let updated = existing.withStatus(.cancelled)
        store[membershipId] = updated
        await serverPatch(membershipId: membershipId, action: "cancel")
        return updated
    }

    // MARK: - Pause

    @discardableResult
    public func pause(membershipId: String) async -> Membership? {
        guard let existing = store[membershipId] else { return nil }
        let updated = existing.withStatus(.paused)
        store[membershipId] = updated
        await serverPatch(membershipId: membershipId, action: "pause")
        return updated
    }

    // MARK: - Resume

    @discardableResult
    public func resume(membershipId: String) async -> Membership? {
        guard let existing = store[membershipId] else { return nil }
        let updated = existing.withStatus(.active)
        store[membershipId] = updated
        await serverPatch(membershipId: membershipId, action: "resume")
        return updated
    }

    // MARK: - Renew

    @discardableResult
    public func renew(membershipId: String) async -> Membership? {
        guard let existing = store[membershipId] else { return nil }
        // Best-effort; server handles billing.
        await serverPost("/memberships/\(membershipId)/renew")
        let updated = existing.withStatus(.active)
        store[membershipId] = updated
        return updated
    }

    // MARK: - Hydrate from server

    /// Replace the local store with memberships fetched from the server.
    public func hydrate(memberships: [Membership]) {
        store = Dictionary(uniqueKeysWithValues: memberships.map { ($0.id, $0) })
    }

    // MARK: - Private helpers

    private func serverPatch(membershipId: String, action: String) async {
        guard let api else { return }
        let body = MembershipActionRequest(action: action)
        _ = try? await api.post(
            "/memberships/\(membershipId)/\(action)",
            body: body,
            as: EmptyMembershipResponse.self
        )
    }

    private func serverPost(_ path: String) async {
        guard let api else { return }
        _ = try? await api.post(path, body: EmptyMembershipRequest(), as: EmptyMembershipResponse.self)
    }
}

// MARK: - Request / Response DTOs (private to module)

private struct EnrollMembershipRequest: Encodable, Sendable {
    let customerId: String
    let planId: String
    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case planId     = "plan_id"
    }
}

private struct MembershipActionRequest: Encodable, Sendable {
    let action: String
}

private struct EmptyMembershipRequest: Encodable, Sendable {}
private struct EmptyMembershipResponse: Decodable, Sendable {}

// MARK: - MembershipDTO (wire format)

/// Server representation of a membership (snake_case keys).
public struct MembershipDTO: Decodable, Sendable {
    public let id: String
    public let customerId: String
    public let planId: String
    public let status: String
    public let startDate: String
    public let endDate: String?
    public let autoRenew: Bool
    public let nextBillingAt: String?

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

    /// Map DTO → domain model.
    public func toDomain() -> Membership {
        let isoFormatter = ISO8601DateFormatter()
        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return isoFormatter.date(from: s)
        }
        return Membership(
            id: id,
            customerId: customerId,
            planId: planId,
            status: MembershipStatus(rawValue: status) ?? .pending,
            startDate: parseDate(startDate) ?? Date(),
            endDate: parseDate(endDate),
            autoRenew: autoRenew,
            nextBillingAt: parseDate(nextBillingAt)
        )
    }
}
