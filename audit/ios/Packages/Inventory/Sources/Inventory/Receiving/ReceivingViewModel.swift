import Foundation
import Observation
import Core
import Networking

// MARK: - List VM

@MainActor
@Observable
public final class ReceivingListViewModel {
    public private(set) var orders: [ReceivingOrder] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    /// nil = all statuses; "ordered" / "partial" etc.
    public var statusFilter: String? = nil

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            orders = try await api.listReceivingOrders(status: statusFilter)
        } catch {
            AppLog.ui.error("ReceivingList load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Detail VM

/// Mutable receiving quantities typed by the operator.
@MainActor
@Observable
public final class ReceivingDetailViewModel {
    public private(set) var order: ReceivingOrder?
    public private(set) var isLoading: Bool = false
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public var showReconciliation: Bool = false
    public private(set) var finalizeResult: [ReconciliationEntry] = []

    /// Operator-entered received quantities, keyed by line-item id.
    public var receivedQty: [Int64: String] = [:]

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let orderId: Int64

    public init(api: APIClient, orderId: Int64) {
        self.api = api
        self.orderId = orderId
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.receivingOrder(id: orderId)
            order = fetched
            // Pre-populate with existing receivedQty from the PO
            for line in fetched.lineItems {
                if receivedQty[line.id] == nil {
                    receivedQty[line.id] = String(line.receivedQty)
                }
            }
        } catch {
            AppLog.ui.error("ReceivingDetail load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Auto-advance: scan a barcode → find line item by SKU → update state.
    /// Returns `true` if the SKU was found in the current order.
    @discardableResult
    public func applyBarcode(_ value: String) -> Bool {
        guard let order else { return false }
        guard let line = order.lineItems.first(where: { $0.sku == value }) else { return false }
        // Increment by 1 (or set to 1 if empty)
        let current = Int(receivedQty[line.id] ?? "0") ?? 0
        receivedQty[line.id] = String(current + 1)
        return true
    }

    /// `true` if any line has a received qty > ordered qty (over-receipt).
    public var hasOverReceipt: Bool {
        guard let order else { return false }
        return order.lineItems.contains { line in
            let received = Int(receivedQty[line.id] ?? "") ?? line.receivedQty
            return received > line.orderedQty
        }
    }

    // MARK: Testing support

    /// Inject an order directly — used by unit tests to bypass network loading.
    internal func _setOrderForTesting(_ receivingOrder: ReceivingOrder) {
        self.order = receivingOrder
        for line in receivingOrder.lineItems {
            if receivedQty[line.id] == nil {
                receivedQty[line.id] = String(line.receivedQty)
            }
        }
    }

    public func finalize() async {
        guard !isSubmitting, let order else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Build items array using purchase_order_item id (not sku) as the server expects.
        let items: [ReceiveLineRequest] = order.lineItems.compactMap { line in
            let qty = Int(receivedQty[line.id] ?? "") ?? line.receivedQty
            // Only send lines where we're actually receiving something.
            guard qty > line.receivedQty else { return nil }
            return ReceiveLineRequest(
                purchaseOrderItemId: line.id,
                quantityReceived: qty - line.receivedQty  // delta, not total
            )
        }

        guard !items.isEmpty else {
            errorMessage = "No quantities entered to receive."
            return
        }

        let req = FinalizeReceivingRequest(items: items)

        do {
            _ = try await api.finalizeReceiving(id: orderId, request: req)
            // Build reconciliation
            finalizeResult = order.lineItems.map { line in
                let received = Int(receivedQty[line.id] ?? "") ?? line.receivedQty
                return ReconciliationEntry(
                    sku: line.sku ?? "",
                    name: line.productName ?? line.sku ?? "Unknown",
                    orderedQty: line.orderedQty,
                    receivedQty: received
                )
            }
            showReconciliation = true
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                // Optimistic completion for offline path
                finalizeResult = order.lineItems.map { line in
                    let received = Int(receivedQty[line.id] ?? "") ?? line.receivedQty
                    return ReconciliationEntry(
                        sku: line.sku ?? "",
                        name: line.productName ?? line.sku ?? "Unknown",
                        orderedQty: line.orderedQty,
                        receivedQty: received
                    )
                }
                // Enqueue offline
                if let payload = try? InventoryOfflineQueue.encode(req) {
                    await InventoryOfflineQueue.enqueue(
                        op: "receiving.finalize",
                        entityServerId: orderId,
                        payload: payload
                    )
                }
                showReconciliation = true
            } else {
                AppLog.ui.error("Receiving finalize failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Reconciliation model

public struct ReconciliationEntry: Sendable, Identifiable {
    public let id: UUID = UUID()
    public let sku: String
    public let name: String
    public let orderedQty: Int
    public let receivedQty: Int

    public var delta: Int { receivedQty - orderedQty }
    public var isOver: Bool { delta > 0 }
    public var isUnder: Bool { delta < 0 }
    public var isExact: Bool { delta == 0 }

    public init(sku: String, name: String, orderedQty: Int, receivedQty: Int) {
        self.sku = sku
        self.name = name
        self.orderedQty = orderedQty
        self.receivedQty = receivedQty
    }
}
