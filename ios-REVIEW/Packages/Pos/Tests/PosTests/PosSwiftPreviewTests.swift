// PosSwiftPreviewTests.swift
// Smoke tests — no pixel diff, no snapshot library needed.
//
// Strategy: instantiate each major POS view using the same mock data its
// #Preview block uses, then assert the view body is reachable (no crash).
// This guarantees that (a) every view compiles, (b) inits don't trap, and
// (c) required dependencies can be constructed from test code.
//
// Guarded by #if canImport(UIKit) so the macOS swift build target is
// unaffected (same guard used by the rest of this test bundle).

#if canImport(UIKit)
import Testing
import SwiftUI
import Foundation
@testable import Pos
import Networking    // InventoryListItem, PosTransactionRequest, APIClient, AuthSessionRefresher

// MARK: - Helpers

/// Decode an InventoryListItem from JSON (struct's memberwise init is internal).
private func makeInventoryItem(
    id: Int64 = 1,
    name: String = "iPhone 14 Pro Screen",
    sku: String = "IPH14P-SCR",
    retailPrice: Double = 189.99,
    inStock: Int = 5
) -> InventoryListItem {
    let json = """
    {
      "id": \(id),
      "name": "\(name)",
      "sku": "\(sku)",
      "item_type": "product",
      "upc_code": null,
      "in_stock": \(inStock),
      "reorder_level": 2,
      "cost_price": null,
      "retail_price": \(retailPrice),
      "manufacturer_name": null,
      "device_name": null,
      "supplier_name": null,
      "is_serialized": 0
    }
    """
    return try! JSONDecoder().decode(InventoryListItem.self, from: Data(json.utf8))
}

/// Confirms a view's `body` can be reached without trapping.
/// The real guard is that the init path succeeded before we call `.body`.
@discardableResult
private func bodyIsReachable<V: View>(_ view: V) -> Bool {
    let _ = AnyView(view.body)
    return true
}

// MARK: - Minimal APIClient stub for PosTenderCoordinator

/// Throws on every call — we only need the init to succeed.
private final class StubAPIClient: APIClient, @unchecked Sendable {

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw StubError.notImplemented
    }

    func delete(_ path: String) async throws {
        throw StubError.notImplemented
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw StubError.notImplemented
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}

    enum StubError: Error { case notImplemented }
}

// MARK: - POS View Smoke Tests

@Suite("POS View smoke tests — init + body reachable")
@MainActor
struct PosSwiftPreviewTests {

    // -----------------------------------------------------------------------
    // MARK: PosGateView  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PosGateView — empty state body is reachable")
    func posGateView_emptyState() {
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository()
        )
        let view = PosGateView(vm: vm)
            .environment(\.horizontalSizeClass, .compact)
        #expect(bodyIsReachable(view))
    }

    @Test("PosGateView — with pickups body is reachable")
    func posGateView_withPickups() {
        let pickups: [ReadyPickup] = [
            ReadyPickup(id: 1, orderId: "4829", customerName: "Sarah M.",
                        deviceSummary: "iPhone 14 screen", totalCents: 27400),
            ReadyPickup(id: 2, orderId: "4831", customerName: "Marco D.",
                        deviceSummary: "Samsung S23 battery", totalCents: 14200),
        ]
        let vm = PosGateViewModel(
            customerRepo: PreviewCustomerRepository(),
            ticketsRepo: PreviewGateTicketsRepository(pickups: pickups)
        )
        let view = PosGateView(vm: vm)
            .environment(\.horizontalSizeClass, .compact)
        #expect(bodyIsReachable(view))
    }

    // -----------------------------------------------------------------------
    // MARK: PickupRow  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PickupRow — with device summary body is reachable")
    func pickupRow_withSummary() {
        let pickup = ReadyPickup(
            id: 4829,
            orderId: "4829",
            customerName: "Sarah M.",
            deviceSummary: "iPhone 14 · Screen repair",
            totalCents: 27400
        )
        let view = PickupRow(pickup: pickup, onTap: {}).padding()
        #expect(bodyIsReachable(view))
    }

    @Test("PickupRow — nil deviceSummary body is reachable")
    func pickupRow_nilSummary() {
        let pickup = ReadyPickup(
            id: 4830,
            orderId: "4830",
            customerName: "Alex T.",
            deviceSummary: nil,
            totalCents: 9900
        )
        #expect(bodyIsReachable(PickupRow(pickup: pickup, onTap: {})))
    }

    // -----------------------------------------------------------------------
    // MARK: PosCatalogTile  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PosCatalogTile — not-in-cart body is reachable")
    func catalogTile_notInCart() {
        let item = makeInventoryItem()
        #expect(bodyIsReachable(PosCatalogTile(item: item, isInCart: false, onTap: {})))
    }

    @Test("PosCatalogTile — in-cart badge body is reachable")
    func catalogTile_inCart() {
        let item = makeInventoryItem(id: 2, name: "Labor · Screen", sku: "LAB-SCR",
                                     retailPrice: 60.0)
        #expect(bodyIsReachable(PosCatalogTile(item: item, isInCart: true, onTap: {})))
    }

    // -----------------------------------------------------------------------
    // MARK: PosCartPanel  (2 tests, @testable required — internal type)
    // -----------------------------------------------------------------------

    @Test("PosCartPanel — empty cart body is reachable")
    func cartPanel_emptyCart() {
        let cart = Cart()
        var nilItem: CartItem? = nil
        let view = PosCartPanel(
            cart: cart,
            onCharge: {},
            onOpenDrawer: {},
            editQuantityFor: Binding(get: { nilItem }, set: { nilItem = $0 }),
            editPriceFor: Binding(get: { nilItem }, set: { nilItem = $0 })
        )
        #expect(bodyIsReachable(view))
    }

    @Test("PosCartPanel — populated cart body is reachable")
    func cartPanel_populatedCart() {
        let cart = Cart()
        cart.add(CartItem(name: "iPhone 14 Pro Screen", sku: "IPH14P-S",
                          unitPrice: Decimal(string: "189.00")!))
        cart.add(CartItem(name: "Labor · screen replacement",
                          unitPrice: Decimal(string: "60.00")!))
        var nilItem: CartItem? = nil
        let view = PosCartPanel(
            cart: cart,
            onCharge: {},
            onOpenDrawer: {},
            editQuantityFor: Binding(get: { nilItem }, set: { nilItem = $0 }),
            editPriceFor: Binding(get: { nilItem }, set: { nilItem = $0 })
        )
        #expect(bodyIsReachable(view))
    }

    // -----------------------------------------------------------------------
    // MARK: PosIPadCartPanel  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PosIPadCartPanel — empty cart body is reachable")
    func iPadCartPanel_emptyCart() {
        let cart = Cart()
        #expect(bodyIsReachable(PosIPadCartPanel(cart: cart, onCharge: {})))
    }

    @Test("PosIPadCartPanel — populated cart body is reachable")
    func iPadCartPanel_populated() {
        let cart = Cart()
        cart.add(CartItem(name: "iPhone 14 Pro Screen", sku: "IPH14P-S",
                          unitPrice: Decimal(string: "189.00")!))
        cart.add(CartItem(name: "Labor · screen replacement",
                          unitPrice: Decimal(string: "60.00")!))
        cart.add(CartItem(name: "USB-C 3 ft cable", sku: "USB-C3",
                          unitPrice: Decimal(string: "14.00")!))
        let view = PosIPadCartPanel(cart: cart, onCharge: {}, onEditItem: { _ in })
        #expect(bodyIsReachable(view))
    }

    // -----------------------------------------------------------------------
    // MARK: PosTenderMethodPickerView  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PosTenderMethodPickerView — basic body is reachable")
    func tenderMethodPicker_basic() {
        let coordinator = PosTenderCoordinator(
            totalCents: 12_109,
            baseRequest: PosTransactionRequest(items: []),
            api: StubAPIClient()
        )
        #expect(bodyIsReachable(PosTenderMethodPickerView(coordinator: coordinator)))
    }

    @Test("PosTenderMethodPickerView — with loyalty tier body is reachable")
    func tenderMethodPicker_withLoyalty() {
        let coordinator = PosTenderCoordinator(
            totalCents: 5_000,
            baseRequest: PosTransactionRequest(items: []),
            api: StubAPIClient()
        )
        let view = PosTenderMethodPickerView(
            coordinator: coordinator,
            loyaltyTierLabel: "Gold Member"
        )
        #expect(bodyIsReachable(view))
    }

    // -----------------------------------------------------------------------
    // MARK: PosCashAmountView  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PosCashAmountView — typical amount body is reachable")
    func cashAmountView_typicalAmount() {
        let view = PosCashAmountView(
            dueCents: 12_109,
            onConfirm: { _ in },
            onCancel: {}
        )
        #expect(bodyIsReachable(view))
    }

    @Test("PosCashAmountView — zero amount body is reachable")
    func cashAmountView_zeroAmount() {
        #expect(bodyIsReachable(PosCashAmountView(dueCents: 0, onConfirm: { _ in }, onCancel: {})))
    }

    // -----------------------------------------------------------------------
    // MARK: PosReceiptView  (2 tests)
    // -----------------------------------------------------------------------

    @Test("PosReceiptView — SMS primary with loyalty tier-up body is reachable")
    func receiptView_smsPrimary() {
        let vm = PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 42,
                amountPaidCents: 12_109,
                changeGivenCents: 891,
                methodLabel: "Cash",
                customerPhone: "+15558675309",
                customerEmail: "jane@example.com",
                loyaltyDelta: 127,
                loyaltyTierBefore: "Gold",
                loyaltyTierAfter: "Platinum"
            )
        )
        let view = PosReceiptView(
            vm: vm,
            receiptText: "BizarreCRM Demo\n123 Main St\n\nTotal: $121.09\n\nThank you!",
            paidAt: Date()
        )
        #expect(bodyIsReachable(view))
    }

    @Test("PosReceiptView — print primary no loyalty body is reachable")
    func receiptView_printPrimary() {
        let vm = PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 99,
                amountPaidCents: 5_000,
                methodLabel: "Visa •4242"
            )
        )
        #expect(bodyIsReachable(PosReceiptView(vm: vm, paidAt: Date())))
    }

    // -----------------------------------------------------------------------
    // MARK: PosLoyaltyCelebrationView  (3 tests)
    // -----------------------------------------------------------------------

    @Test("PosLoyaltyCelebrationView — tier-up body is reachable")
    func loyalty_tierUp() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 127,
            tierBefore: "Gold",
            tierAfter: "Platinum",
            tierProgress: 1.0
        )
        #expect(bodyIsReachable(view))
    }

    @Test("PosLoyaltyCelebrationView — same-tier body is reachable")
    func loyalty_sameTier() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 45,
            tierBefore: "Silver",
            tierAfter: "Silver",
            tierProgress: 0.57
        )
        #expect(bodyIsReachable(view))
    }

    @Test("PosLoyaltyCelebrationView — nil tiers body is reachable")
    func loyalty_nilTiers() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 10,
            tierBefore: nil,
            tierAfter: nil,
            tierProgress: 0.3
        )
        #expect(bodyIsReachable(view))
    }
}
#endif  // canImport(UIKit)
