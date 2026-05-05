import Foundation
import Networking

// MARK: - §41.7 Expiry policy

/// Tenant-level default expiry applied when creating a payment link.
/// The `never` case means the link never expires (server stores `null`
/// for `expires_at`).
public enum PaymentLinkExpiryPolicy: String, Codable, Sendable, CaseIterable, Equatable {
    case sevenDays   = "7d"
    case fourteenDays = "14d"
    case thirtyDays  = "30d"
    case never       = "never"

    /// Human-readable label shown in the admin picker.
    public var label: String {
        switch self {
        case .sevenDays:    return "7 days"
        case .fourteenDays: return "14 days"
        case .thirtyDays:   return "30 days"
        case .never:        return "Never expires"
        }
    }

    /// Number of days, or `nil` for "never".
    public var days: Int? {
        switch self {
        case .sevenDays:    return 7
        case .fourteenDays: return 14
        case .thirtyDays:   return 30
        case .never:        return nil
        }
    }

    /// Produces an ISO-8601 expiry timestamp from `referenceDate` (UTC),
    /// or `nil` when the policy is `.never`.
    public func expiresAt(from referenceDate: Date = Date()) -> String? {
        guard let d = days else { return nil }
        let future = referenceDate.addingTimeInterval(Double(d) * 86_400)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: future)
    }

    /// Expired-link message shown on the public pay page (for reference in
    /// the iOS app's expired-state banner).
    public static let expiredMessage = "This link has expired. Please contact the shop for a new one."
}

// MARK: - Tenant expiry policy DTO

public struct TenantExpiryPolicyDTO: Codable, Sendable {
    public let defaultExpiryPolicy: PaymentLinkExpiryPolicy

    enum CodingKeys: String, CodingKey {
        case defaultExpiryPolicy = "default_expiry_policy"
    }

    public init(defaultExpiryPolicy: PaymentLinkExpiryPolicy) {
        self.defaultExpiryPolicy = defaultExpiryPolicy
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /settings/payment-link-expiry` — fetch tenant default.
    func getExpiryPolicy() async throws -> TenantExpiryPolicyDTO {
        try await get("/api/v1/settings/payment-link-expiry", as: TenantExpiryPolicyDTO.self)
    }

    /// `PATCH /settings/payment-link-expiry` — update tenant default.
    func setExpiryPolicy(_ policy: PaymentLinkExpiryPolicy) async throws -> TenantExpiryPolicyDTO {
        let body = TenantExpiryPolicyDTO(defaultExpiryPolicy: policy)
        return try await patch(
            "/api/v1/settings/payment-link-expiry",
            body: body,
            as: TenantExpiryPolicyDTO.self
        )
    }
}
