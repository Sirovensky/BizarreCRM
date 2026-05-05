import Foundation
import Networking

/// §16.5 — Maps a `Cart` into a `PosTransactionRequest` for `POST /pos/transaction`.
///
/// Responsibilities:
/// - Convert per-line quantity + inventoryItemId into `PosTransactionLineItem`
/// - Throw `MapperError.customLineNotSupported` for lines without an
///   inventory_item_id (the server requires one for every POS line).
/// - Convert cents → dollars for discount and tip.
/// - Attach customer_id and idempotency key.
public enum PosTransactionMapper {

    public enum MapperError: Error, LocalizedError, Sendable {
        /// A cart item with no inventory backing was in the cart. The server
        /// cannot price it (POS1), so we must block the sale and prompt the
        /// cashier to replace it with a catalogued item or use a custom quote.
        case customLineNotSupported(String)
    }

    /// Build a `PosTransactionRequest` from the current cart state.
    ///
    /// - Parameters:
    ///   - cart: The live cart (must be called on `@MainActor`).
    ///   - paymentMethod: API value for the selected tender (e.g. `"cash"`).
    ///   - paymentAmountCents: How much the customer is paying, in cents.
    ///   - idempotencyKey: UUID string for server-side deduplication.
    /// - Throws: `MapperError.customLineNotSupported` if any cart item has
    ///   `inventoryItemId == nil`.
    @MainActor
    public static func request(
        from cart: Cart,
        paymentMethod: String,
        paymentAmountCents: Int,
        idempotencyKey: String
    ) throws -> PosTransactionRequest {
        let lines: [PosTransactionLineItem] = try cart.items.map { item in
            guard let invId = item.inventoryItemId else {
                throw MapperError.customLineNotSupported(
                    "\"\(item.name)\" is a custom line item and cannot be processed through the POS terminal. Remove it or convert it to a catalogue product."
                )
            }
            let lineDiscountDollars: Double? = item.discountCents > 0
                ? Double(item.discountCents) / 100.0
                : nil
            return PosTransactionLineItem(
                inventoryItemId: Int(invId),
                quantity: item.quantity,
                lineDiscount: lineDiscountDollars
            )
        }

        let discountDollars: Double? = cart.effectiveDiscountCents > 0
            ? Double(cart.effectiveDiscountCents) / 100.0
            : nil

        let tipDollars: Double? = cart.tipCents > 0
            ? Double(cart.tipCents) / 100.0
            : nil

        let paymentDollars = Double(paymentAmountCents) / 100.0

        return PosTransactionRequest(
            items: lines,
            customerId: cart.customer?.id.map(Int.init),
            discount: discountDollars,
            tip: tipDollars,
            paymentMethod: paymentMethod,
            paymentAmount: paymentDollars,
            idempotencyKey: idempotencyKey
        )
    }
}
