import Foundation
import Networking

// MARK: - CustomerHealthSnapshot

/// Combined health + LTV data for a single customer.
public struct CustomerHealthSnapshot: Sendable {
    public let score: CustomerHealthScoreResult
    public let ltv: CustomerLTVResult?
    public let lastInteractionAt: String?

    public init(score: CustomerHealthScoreResult, ltv: CustomerLTVResult?, lastInteractionAt: String?) {
        self.score              = score
        self.ltv                = ltv
        self.lastInteractionAt  = lastInteractionAt
    }
}

// MARK: - CustomerHealthRepository (protocol)

/// Provides health-score and LTV data for a single customer.
///
/// The live implementation fetches from:
///   - `GET /crm/customers/:id/health-score`  (cached score in DB)
///   - `GET /api/v1/customers/:id/analytics`  (LTV + ticket count)
///
/// Both calls are independent and fired in parallel.
/// Falls back to client-side computation when either endpoint is unavailable.
///
/// Cross-package contract: this protocol only depends on `Networking` types.
/// It does NOT import any other `Customers`-package file that §5 authors own.
public protocol CustomerHealthRepository: Sendable {
    /// Fetch (or compute) health snapshot for `customerId`.
    func healthSnapshot(customerId: Int64) async throws -> CustomerHealthSnapshot
    /// Trigger server-side RFM recalculation and return updated snapshot.
    func recalculate(customerId: Int64) async throws -> CustomerHealthSnapshot
}

// MARK: - CustomerHealthRepositoryImpl

/// Live implementation.  Requires only an `APIClient`; no cross-package imports.
public actor CustomerHealthRepositoryImpl: CustomerHealthRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func healthSnapshot(customerId: Int64) async throws -> CustomerHealthSnapshot {
        // Fire detail + health-score + analytics in parallel.
        async let detailTask    = try await api.customer(id: customerId)
        async let analyticsTask = try? await api.customerAnalytics(id: customerId)
        async let healthTask    = try? await api.customerHealthScore(customerId: customerId)

        let detail    = try await detailTask
        let analytics = await analyticsTask
        let health    = await healthTask

        return buildSnapshot(detail: detail, analytics: analytics, health: health)
    }

    public func recalculate(customerId: Int64) async throws -> CustomerHealthSnapshot {
        let result = try await api.recalculateCustomerHealthScore(customerId: customerId)

        // Refresh detail so score fields are up-to-date.
        let detail = try await api.customer(id: customerId)
        let ltv    = try? await api.customerAnalytics(id: customerId)

        let score = CustomerHealthScoreResult(
            value: max(0, min(100, result.score)),
            tier:  CustomerHealthTier(score: max(0, min(100, result.score))),
            label: CustomerHealthLabel(rawValue: result.tier ?? ""),
            recommendation: CustomerHealthScoreResult.recommendation(for: detail),
            components: HealthScoreComponents(
                recencyPoints:   result.recencyPoints ?? 0,
                frequencyPoints: result.frequencyPoints ?? 0,
                monetaryPoints:  result.monetaryPoints ?? 0
            )
        )

        let ltvResult: CustomerLTVResult?
        if let lifetimeValueCents = result.lifetimeValueCents {
            ltvResult = CustomerLTVResult(
                lifetimeDollars: Double(lifetimeValueCents) / 100.0,
                tier: LTVCalculator.tier(forCentsInt64: Int64(lifetimeValueCents)),
                invoiceCount: ltv?.totalTickets ?? 0
            )
        } else if let a = ltv {
            ltvResult = CustomerLTVResult.from(analytics: a)
        } else {
            ltvResult = CustomerLTVResult.from(detail: detail)
        }

        return CustomerHealthSnapshot(
            score: score,
            ltv: ltvResult,
            lastInteractionAt: result.lastInteractionAt
        )
    }

    // MARK: - Private

    private func buildSnapshot(
        detail: CustomerDetail,
        analytics: CustomerAnalytics?,
        health: CustomerHealthScoreResponse?
    ) -> CustomerHealthSnapshot {
        let score: CustomerHealthScoreResult
        if let h = health, let rawScore = h.score {
            let clamped = max(0, min(100, rawScore))
            score = CustomerHealthScoreResult(
                value: clamped,
                tier:  CustomerHealthTier(score: clamped),
                label: h.tier.flatMap { CustomerHealthLabel(rawValue: $0) },
                recommendation: CustomerHealthScoreResult.recommendation(for: detail)
            )
        } else {
            score = CustomerHealthScoreResult.compute(detail: detail)
        }

        let ltv: CustomerLTVResult?
        if let a = analytics {
            ltv = CustomerLTVResult.from(analytics: a)
        } else if let l = health, let cents = l.lifetimeValueCents {
            ltv = CustomerLTVResult(
                lifetimeDollars: Double(cents) / 100.0,
                tier: LTVCalculator.tier(forCentsInt64: Int64(cents)),
                invoiceCount: 0
            )
        } else {
            ltv = CustomerLTVResult.from(detail: detail)
        }

        let lastInteraction = health?.lastInteractionAt ?? detail.lastVisitAt

        return CustomerHealthSnapshot(
            score: score,
            ltv: ltv,
            lastInteractionAt: lastInteraction
        )
    }
}
