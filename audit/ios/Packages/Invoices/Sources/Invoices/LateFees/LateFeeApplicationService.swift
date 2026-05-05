import Foundation
#if canImport(Networking)
import Networking
#endif

// §7.12 / §7 line 1277 — Auto-apply late fee to overdue invoice.
//
// Pure decision helper + thin POST wrapper. View-models call
// `LateFeeApplicationService.shouldApply(invoice:asOf:policy:)` to decide
// whether the invoice is past grace and the fee has not yet been applied,
// then `applyIfNeeded` to POST.
//
// Server endpoint: POST /api/v1/invoices/:id/apply-late-fee
//   Body: { fee_cents }
//   Server is the source of truth: it dedupes (idempotent on invoice + day).

// MARK: - Pure decision helper

/// Whether the invoice is currently overdue beyond its grace window AND a
/// computed fee > 0 should be applied. Pure — fully testable.
public enum LateFeeApplicationService {

    /// Result of evaluating an invoice for auto-application.
    public struct Decision: Sendable, Equatable {
        public let shouldApply: Bool
        public let computedFeeCents: Cents
        public let reason: String

        public init(shouldApply: Bool, computedFeeCents: Cents, reason: String) {
            self.shouldApply = shouldApply
            self.computedFeeCents = computedFeeCents
            self.reason = reason
        }
    }

    /// Evaluates whether a late fee should be auto-applied right now.
    ///
    /// - Parameters:
    ///   - invoice: balance + due date.
    ///   - asOf: evaluation date.
    ///   - policy: tenant late-fee policy.
    ///   - alreadyAppliedCents: amount already applied for this billing cycle.
    /// - Returns: `Decision` with `shouldApply=false` when in grace, balance ≤ 0,
    ///   no policy configured, or the computed fee equals what's already applied.
    public static func evaluate(
        invoice: InvoiceForFeeCalc,
        asOf: Date,
        policy: LateFeePolicy,
        alreadyAppliedCents: Cents = 0,
        calendar: Calendar = .current
    ) -> Decision {
        guard invoice.balanceCents > 0 else {
            return Decision(shouldApply: false, computedFeeCents: 0, reason: "Balance is zero.")
        }
        guard invoice.dueDate != nil else {
            return Decision(shouldApply: false, computedFeeCents: 0, reason: "No due date.")
        }
        let fee = LateFeeCalculator.compute(invoice: invoice, asOf: asOf, policy: policy, calendar: calendar)
        guard fee > 0 else {
            return Decision(shouldApply: false, computedFeeCents: 0, reason: "Within grace period.")
        }
        let delta = fee - alreadyAppliedCents
        guard delta > 0 else {
            return Decision(shouldApply: false, computedFeeCents: fee, reason: "Fee already applied.")
        }
        return Decision(shouldApply: true, computedFeeCents: delta, reason: "Overdue past grace.")
    }
}

// MARK: - Network DTOs

public struct ApplyLateFeeRequest: Encodable, Sendable {
    public let feeCents: Cents

    public init(feeCents: Cents) { self.feeCents = feeCents }

    enum CodingKeys: String, CodingKey {
        case feeCents = "fee_cents"
    }
}

public struct ApplyLateFeeResponse: Decodable, Sendable {
    public let success: Bool?
    public let appliedCents: Cents?
    public let newBalanceCents: Cents?

    enum CodingKeys: String, CodingKey {
        case success
        case appliedCents = "applied_cents"
        case newBalanceCents = "new_balance_cents"
    }
}

#if canImport(Networking)
public extension APIClient {
    /// `POST /api/v1/invoices/:id/apply-late-fee`
    /// Server-side dedupes by invoice + day; safe to retry.
    func applyLateFee(invoiceId: Int64, body: ApplyLateFeeRequest) async throws -> ApplyLateFeeResponse {
        try await post(
            "/api/v1/invoices/\(invoiceId)/apply-late-fee",
            body: body,
            as: ApplyLateFeeResponse.self
        )
    }
}
#endif
