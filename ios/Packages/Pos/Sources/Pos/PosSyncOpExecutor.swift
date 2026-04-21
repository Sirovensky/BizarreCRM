import Foundation
import Core
import Networking
import Persistence
import Sync

// MARK: - POS sale payload types

/// Payload for `pos.sale.finalize` sync ops.
public struct PosSalePayload: Codable, Sendable {
    public let items: [PosSaleLinePayload]
    public let customerId: Int64?
    public let subtotalCents: Int
    public let discountCents: Int
    public let taxCents: Int
    public let tipCents: Int
    public let feesCents: Int
    public let feesLabel: String?
    public let totalCents: Int
    public let cashSessionId: Int64?
    public let idempotencyKey: String

    public init(
        items: [PosSaleLinePayload],
        customerId: Int64?,
        subtotalCents: Int,
        discountCents: Int,
        taxCents: Int,
        tipCents: Int,
        feesCents: Int,
        feesLabel: String?,
        totalCents: Int,
        cashSessionId: Int64?,
        idempotencyKey: String
    ) {
        self.items = items
        self.customerId = customerId
        self.subtotalCents = subtotalCents
        self.discountCents = discountCents
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.feesCents = feesCents
        self.feesLabel = feesLabel
        self.totalCents = totalCents
        self.cashSessionId = cashSessionId
        self.idempotencyKey = idempotencyKey
    }
}

public struct PosSaleLinePayload: Codable, Sendable {
    public let inventoryItemId: Int64?
    public let name: String
    public let sku: String?
    public let quantity: Int
    public let unitPriceCents: Int
    /// Basis points (e.g. 800 = 8%). nil means no tax.
    public let taxRateBps: Int?
    public let discountCents: Int
    public let subtotalCents: Int
    public let notes: String?

    public init(
        inventoryItemId: Int64?,
        name: String,
        sku: String?,
        quantity: Int,
        unitPriceCents: Int,
        taxRateBps: Int?,
        discountCents: Int,
        subtotalCents: Int,
        notes: String?
    ) {
        self.inventoryItemId = inventoryItemId
        self.name = name
        self.sku = sku
        self.quantity = quantity
        self.unitPriceCents = unitPriceCents
        self.taxRateBps = taxRateBps
        self.discountCents = discountCents
        self.subtotalCents = subtotalCents
        self.notes = notes
    }
}

/// Payload for `pos.return.create` sync ops.
public struct PosReturnPayload: Codable, Sendable {
    public let originalInvoiceId: Int64?
    public let items: [PosReturnLinePayload]
    public let reasonCode: String?
    public let notes: String?

    public init(
        originalInvoiceId: Int64?,
        items: [PosReturnLinePayload],
        reasonCode: String?,
        notes: String?
    ) {
        self.originalInvoiceId = originalInvoiceId
        self.items = items
        self.reasonCode = reasonCode
        self.notes = notes
    }
}

public struct PosReturnLinePayload: Codable, Sendable {
    public let inventoryItemId: Int64?
    public let name: String
    public let quantity: Int
    public let refundCents: Int

    public init(inventoryItemId: Int64?, name: String, quantity: Int, refundCents: Int) {
        self.inventoryItemId = inventoryItemId
        self.name = name
        self.quantity = quantity
        self.refundCents = refundCents
    }
}

/// Payload for `pos.cash.opening` sync ops.
public struct CashOpeningPayload: Codable, Sendable {
    public let cashierId: Int64
    public let openingFloatCents: Int
    public let openedAt: Date

    public init(cashierId: Int64, openingFloatCents: Int, openedAt: Date) {
        self.cashierId = cashierId
        self.openingFloatCents = openingFloatCents
        self.openedAt = openedAt
    }
}

// MARK: - Sentinel decodable used when only success/failure matters

private struct EmptyResponse: Decodable, Sendable {}

// MARK: - PosSyncOpExecutor

/// Concrete `SyncOpExecutor` for the POS domain. Dispatches `pos.sale.finalize`,
/// `pos.return.create`, and `pos.cash.opening` to the server. Unknown op kinds
/// throw `AppError.syncDeadLetter` so the drain loop moves them to DLQ.
///
/// 409 on `pos.sale.finalize` means "items already sold by another terminal" —
/// non-retriable: executor throws `AppError.conflict` and the drain loop dead-
/// letters the op without further retries.
///
/// Wire in `AppServices.swift`:
/// ```swift
/// let posExecutor = PosSyncOpExecutor(api: apiClient)
/// SyncManager.shared.executor = posExecutor
/// ```
public final class PosSyncOpExecutor: SyncOpExecutor {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func execute(_ record: SyncQueueRecord) async throws {
        let kind = record.kind ?? "\(record.entity ?? "unknown").\(record.op ?? "unknown")"
        let payloadData = Data(record.payload.utf8)

        switch kind {
        case "pos.sale.finalize":
            let body = try decodedPayload(PosSalePayload.self, from: payloadData, kind: kind)
            try await finalizeSale(body)

        case "pos.return.create":
            let body = try decodedPayload(PosReturnPayload.self, from: payloadData, kind: kind)
            _ = try await api.post("/pos/returns", body: body, as: EmptyResponse.self)

        case "pos.cash.opening":
            let body = try decodedPayload(CashOpeningPayload.self, from: payloadData, kind: kind)
            _ = try await api.post("/pos/cash/sessions/open", body: body, as: EmptyResponse.self)

        default:
            throw AppError.syncDeadLetter(
                queueId: record.idempotencyKey ?? "?",
                reason: "Unknown POS op kind: \(kind)"
            )
        }
    }

    // MARK: - Private helpers

    private func decodedPayload<T: Decodable>(_ type: T.Type, from data: Data, kind: String) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            throw AppError.decoding(type: kind, underlying: error)
        }
    }

    /// POST /pos/sale/finalize. A 409 means items were already sold by another
    /// terminal — catch and rethrow as `AppError.conflict` so the drain loop
    /// dead-letters the op without retrying (per §16.12 conflict path).
    private func finalizeSale(_ body: PosSalePayload) async throws {
        do {
            _ = try await api.post("/pos/sale/finalize", body: body, as: EmptyResponse.self)
        } catch APITransportError.httpStatus(409, let message) {
            throw AppError.conflict(reason: message ?? "Cart items already sold by another terminal.")
        }
    }
}
