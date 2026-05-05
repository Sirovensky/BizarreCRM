import Foundation

/// §40 — Store credit balance read, mapped to:
///   - `GET /api/v1/refunds/credits/:customerId`
///
/// Server returns `{ balance: Decimal (dollars), transactions: [...] }`.
/// The POS only needs the balance to decide whether to show the "Apply
/// store credit" section in the gift-card sheet — history is rendered on
/// the customer detail screen, not at checkout. We intentionally drop the
/// transactions array on this read so the request stays cheap.
///
/// As with `GiftCardsEndpoints`, money crosses this boundary as `Decimal`
/// and leaves as integer cents. The cart never sees a dollar amount.

/// Raw server shape (dollars).
struct StoreCreditRow: Decodable, Sendable {
    let balance: Decimal?
}

/// Cart-side projection. Cents-only, carries the customer id so tender
/// rows can reference back without a second lookup.
public struct StoreCreditBalance: Sendable, Equatable {
    public let customerId: Int64
    public let balanceCents: Int

    public init(customerId: Int64, balanceCents: Int) {
        self.customerId = customerId
        self.balanceCents = balanceCents
    }
}

public extension APIClient {
    /// Fetch the store-credit balance for `customerId`. Returns a
    /// zero-balance value when the server has no row — the caller then
    /// decides whether to hide the section.
    func getStoreCreditBalance(customerId: Int64) async throws -> StoreCreditBalance {
        let row = try await get(
            "/api/v1/refunds/credits/\(customerId)",
            as: StoreCreditRow.self
        )
        return StoreCreditBalance(
            customerId: customerId,
            balanceCents: GiftCard.dollarsToCents(row.balance ?? 0)
        )
    }
}
