import Foundation
import Networking

/// §16.6 — Maps a `Cart` to a `PosTransactionRequest`.
///
/// The server re-prices every inventory line from `retail_price` (POS1) so
/// we do NOT include `unit_price` in the request. We send only
/// `inventory_item_id` + `quantity` + optional `line_discount`.
///
/// Custom lines (`inventoryItemId == nil`) are intentionally excluded from
/// the line-items array — the server's `/pos/transaction` endpoint requires
/// an `inventory_item_id` for every line. Custom lines should map to a
/// special "misc" SKU or be routed through `/invoices` (Phase 4+). We
/// raise `TransactionMapperError.customLineNotSupported` for callers to
/// display a user-friendly message.
public enum PosTransactionMapper {

    public enum MapperError: Error, LocalizedError {
        /// Cart contains a custom/untracked line. Not yet supported by the
        /// `/pos/transaction` endpoint — guide cashier to a workaround.
        case customLineNotSupported(String)

        public var errorDescription: String? {
            switch self {
            case .customLineNotSupported(let name):
                return "Custom line "\(name)" cannot be processed via POS transaction. Convert it to an inventory item or use an invoice instead."
            }
        }
    }

    /// Build a `PosTransactionRequest` from `cart`, ready for the
    /// `POST /api/v1/pos/transaction` endpoint.
    ///
    /// - Parameters:
    ///   - cart: The current POS cart.
    ///   - idempotencyKey: Client-generated UUID string for safe retries.
    /// - Throws: `MapperError.customLineNotSupported` when the cart has
    ///   a free-form line with no `inventoryItemId`.
    /// - Returns: A fully-populated `PosTransactionRequest` without the
    ///   payment fields (caller adds `paymentMethod`/`paymentAmount`).
    public static func request(
        from cart: Cart,
        idempotencyKey: String = UUID().uuidString
    ) throws -> PosTransactionRequest {
        var lineItems: [PosTransactionLineItem] = []

        for item in cart.items {
            guard let invId = item.inventoryItemId else {
                throw MapperError.customLineNotSupported(item.name)
            }
            let lineDiscount: Double? = item.discountCents > 0
                ? Double(item.discountCents) / 100
                : nil
            lineItems.append(PosTransactionLineItem(
                inventoryItemId: Int(invId),
                quantity: item.quantity,
                lineDiscount: lineDiscount
            ))
        }

        let discountDollars: Double? = cart.effectiveDiscountCents > 0
            ? Double(cart.effectiveDiscountCents) / 100
            : nil

        let tipDollars: Double? = cart.tipCents > 0
            ? Double(cart.tipCents) / 100
            : nil

        let customerId: Int? = cart.customer?.id.map { Int($0) }

        return PosTransactionRequest(
            items: lineItems,
            customerId: customerId,
            discount: discountDollars,
            tip: tipDollars,
            notes: nil,
            paymentMethod: nil,   // caller populates
            paymentAmount: nil,   // caller populates
            payments: nil,        // caller populates for split tender
            idempotencyKey: idempotencyKey
        )
    }
}
