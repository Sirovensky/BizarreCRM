import Foundation
import Core
import Persistence

// MARK: - CouponAbuseGuard (§16 — Abuse prevention)
//
// Two layers of local abuse prevention:
//
// 1. Rate-limiting — after `maxAttemptsPerWindow` failed coupon lookups within
//    `windowSeconds` seconds, further attempts are blocked client-side.
//    The block lasts `cooldownSeconds`. This prevents brute-force guessing of
//    coupon codes at the POS.
//
// 2. Audit logging — every invalid attempt is appended to `PosAuditLogStore`
//    with event type `coupon_invalid_attempt`. The server performs its own
//    validation and logging; this is a belt-and-suspenders local record.
//
// Server enforces the authoritative rate-limit and fraud checks. iOS is
// optimistic but stops sending requests when blocked to reduce server load
// and prevent a cashier loop.

// MARK: - CouponAbuseGuard

public actor CouponAbuseGuard {

    // MARK: - Configuration

    /// Maximum failed lookups before a temporary block is imposed.
    public let maxAttemptsPerWindow: Int

    /// Rolling window in seconds over which attempts are counted.
    public let windowSeconds: TimeInterval

    /// How long (seconds) the block lasts after hitting the threshold.
    public let cooldownSeconds: TimeInterval

    // MARK: - State (actor-isolated)

    private var failedAttempts: [(code: String, at: Date)] = []
    private var blockedUntil: Date? = nil

    // MARK: - Shared instance

    public static let shared = CouponAbuseGuard(
        maxAttemptsPerWindow: 5,
        windowSeconds: 60,
        cooldownSeconds: 120
    )

    public init(
        maxAttemptsPerWindow: Int = 5,
        windowSeconds: TimeInterval = 60,
        cooldownSeconds: TimeInterval = 120
    ) {
        self.maxAttemptsPerWindow = maxAttemptsPerWindow
        self.windowSeconds = windowSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    // MARK: - API

    /// Returns `true` when the device is rate-limited (further attempts should not be sent).
    /// Prunes expired entries before checking.
    public func isBlocked(now: Date = .now) -> Bool {
        pruneExpired(now: now)
        if let until = blockedUntil, until > now { return true }
        return false
    }

    /// How many seconds until the block expires. Returns 0 when not blocked.
    public func secondsUntilUnblocked(now: Date = .now) -> TimeInterval {
        guard let until = blockedUntil, until > now else { return 0 }
        return until.timeIntervalSince(now)
    }

    /// Record a failed coupon lookup.
    /// Logs to `PosAuditLogStore` and may impose a block.
    public func recordFailedAttempt(code: String, now: Date = .now) async {
        pruneExpired(now: now)
        failedAttempts.append((code: code, at: now))

        // Audit log — fire-and-forget; never blocks the caller
        let attemptCount = self.failedAttempts.count
        Task.detached {
            try? await PosAuditLogStore.shared.record(
                event: "coupon_invalid_attempt",
                cashierId: 0,
                managerId: nil as Int64?,
                amountCents: nil as Int?,
                context: [
                    "code":        code,
                    "attemptCount": "\(attemptCount)"
                ]
            )
        }

        if failedAttempts.count >= maxAttemptsPerWindow {
            blockedUntil = now.addingTimeInterval(cooldownSeconds)
            AppLog.pos.warning("CouponAbuseGuard: rate-limit imposed after \(self.failedAttempts.count) failures on device")
        }
    }

    /// Reset the guard (e.g. on successful coupon application or shift change).
    public func reset() {
        failedAttempts.removeAll()
        blockedUntil = nil
    }

    // MARK: - Private

    private func pruneExpired(now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        failedAttempts = failedAttempts.filter { $0.at > cutoff }
        if let until = blockedUntil, until <= now {
            blockedUntil = nil
            AppLog.pos.info("CouponAbuseGuard: block expired — device unblocked")
        }
    }
}

// MARK: - AffiliateCode (§16 — Affiliate codes)
//
// An affiliate code ties a coupon code to a staff member (or partner) for
// sales attribution. When the coupon is applied at checkout the cashier's
// name / ID is recorded alongside the sale, enabling commission reporting.
//
// Server stores the mapping; iOS surfaces it in:
//   1. CouponListView — affiliate badge on each row
//   2. Receipt — "Referred by: <name>" line if coupon has affiliate
//   3. Audit log — `affiliate_id` in the context dict

public struct AffiliateCode: Codable, Sendable, Identifiable, Hashable {
    /// Server-assigned id.
    public let id: String
    /// The coupon code this affiliate record is attached to.
    public let couponCode: String
    /// Staff member or partner name shown in reports.
    public let affiliateName: String
    /// Staff member ID (links to `employees` table). `nil` for external partners.
    public let staffId: Int64?
    /// Commission rate (0.0–1.0) — 0.05 = 5 % of referred sale. For reporting only.
    public let commissionRate: Double?
    /// Whether this affiliate code is currently active.
    public let active: Bool

    public init(
        id: String,
        couponCode: String,
        affiliateName: String,
        staffId: Int64? = nil,
        commissionRate: Double? = nil,
        active: Bool = true
    ) {
        self.id             = id
        self.couponCode     = couponCode
        self.affiliateName  = affiliateName
        self.staffId        = staffId
        self.commissionRate = commissionRate
        self.active         = active
    }

    enum CodingKeys: String, CodingKey {
        case id
        case couponCode      = "coupon_code"
        case affiliateName   = "affiliate_name"
        case staffId         = "staff_id"
        case commissionRate  = "commission_rate"
        case active
    }
}

// MARK: - AffiliateCodeRepository

/// Minimal repository for affiliate code CRUD.
/// Server endpoints: `GET /coupons/:code/affiliates`, `POST /coupons/:code/affiliates`.
public protocol AffiliateCodeRepository: Sendable {
    func listAffiliates(forCouponCode code: String) async throws -> [AffiliateCode]
    func createAffiliate(_ affiliate: AffiliateCode) async throws -> AffiliateCode
    func deactivateAffiliate(id: String) async throws
}
