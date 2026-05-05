import Foundation
import Observation
import Core
import Networking
import Persistence
import Sync

// MARK: - CheckoutState

/// The outcome state of a checkout attempt when the device is offline.
public enum CheckoutState: Equatable, Sendable {
    case idle
    case offlinePending   // Sale enqueued; will auto-sync on reconnect
    case submitting
    case error(String)
}

// MARK: - CartViewModel

/// Wraps `Cart` with offline-aware checkout logic.
///
/// **Responsibilities:**
/// 1. Offline checkout: if `Reachability.shared.isOnline == false`, serialise
///    the current `Cart` into a `SyncOp` and enqueue via `SyncManager`.
/// 2. Cart persistence: on every call to `saveSnapshot()` / `clearSnapshot()`
///    the current cart state is persisted to / removed from `PosCartSnapshotStore`.
/// 3. Restore last cart on app launch by calling `restoreSnapshotIfAvailable()`.
///
/// **Not a replacement for `Cart`:** `Cart` remains the source of truth for
/// in-memory state; `CartViewModel` adds the persistence and offline-queue
/// integration layer on top.
///
/// Wire in `PosView`:
/// ```swift
/// @State private var cartVM = CartViewModel()
/// // Pass cartVM.cart to subviews; call cartVM.checkout(cart:session:api:)
/// ```
@MainActor
@Observable
public final class CartViewModel {
    /// Human-facing toast message for the current screen.
    public private(set) var toastMessage: String? = nil
    /// Current offline-checkout state, drives the UI badge.
    public private(set) var checkoutState: CheckoutState = .idle

    public init() {}

    // MARK: - Offline-aware checkout

    /// Attempt to check out the given cart.
    ///
    /// - If online: show the post-sale flow as today (the caller's responsibility).
    /// - If offline: serialise cart + enqueue a `pos.sale.finalize` SyncOp;
    ///   mark `checkoutState` as `.offlinePending`; show a toast.
    ///
    /// Returns `true` when the call was handled offline (caller should NOT
    /// open the post-sale sheet). Returns `false` when online — caller
    /// proceeds with the normal charge flow.
    @discardableResult
    public func checkoutIfOffline(
        cart: Cart,
        cashSession: CashSessionRecord?,
        idempotencyKey: String = UUID().uuidString
    ) async -> Bool {
        guard !Reachability.shared.isOnline else {
            checkoutState = .idle
            return false   // Online path — caller handles charge
        }

        await enqueueOfflineSale(cart: cart, cashSession: cashSession, idempotencyKey: idempotencyKey)
        return true
    }

    // MARK: - Cart snapshot persistence

    /// Persist current cart state so it survives app kills.
    /// Call from every mutation point that changes the cart materially.
    public func saveSnapshot(cart: Cart, cashSessionId: Int64? = nil) async {
        let snapshot = CartSnapshot.from(cart: cart, sessionId: cashSessionId)
        await PosCartSnapshotStore.shared.save(snapshot)
    }

    /// Restore the last saved snapshot into `cart` if one exists and is fresh (< 24h).
    public func restoreSnapshotIfAvailable(into cart: Cart) async {
        guard let snapshot = await PosCartSnapshotStore.shared.load() else { return }
        snapshot.restore(into: cart)
        AppLog.pos.info("CartViewModel: restored cart snapshot (\(snapshot.items.count, privacy: .public) items)")
    }

    /// Delete the persisted snapshot after a successful checkout or explicit cart clear.
    public func clearSnapshot() async {
        await PosCartSnapshotStore.shared.clear()
    }

    // MARK: - Private helpers

    private func enqueueOfflineSale(
        cart: Cart,
        cashSession: CashSessionRecord?,
        idempotencyKey: String
    ) async {
        checkoutState = .submitting
        defer {
            // Toast auto-clears in 3 s; state stays as offlinePending for the indicator.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                toastMessage = nil
            }
        }

        let payloadResult = Result { try buildSalePayload(cart: cart, cashSession: cashSession, idempotencyKey: idempotencyKey) }
        switch payloadResult {
        case .failure(let error):
            checkoutState = .error(error.localizedDescription)
            toastMessage = "Could not queue sale: \(error.localizedDescription)"
            return

        case .success(let payload):
            let op = SyncOp(
                op: "sale.finalize",
                entity: "pos",
                payload: payload,
                idempotencyKey: idempotencyKey
            )
            await SyncManager.shared.enqueue(op)
            checkoutState = .offlinePending
            toastMessage = "Sale queued — will sync when online"
            AppLog.pos.info("CartViewModel: offline sale enqueued (key=\(idempotencyKey, privacy: .private))")
        }
    }

    private func buildSalePayload(
        cart: Cart,
        cashSession: CashSessionRecord?,
        idempotencyKey: String
    ) throws -> Data {
        let lines = cart.items.map { item -> PosSaleLinePayload in
            let unitPriceCents = CartMath.toCents(item.unitPrice)
            let taxRateBps = item.taxRate.map { CartMath.toCents($0 * 100) }
            return PosSaleLinePayload(
                inventoryItemId: item.inventoryItemId,
                name: item.name,
                sku: item.sku,
                quantity: item.quantity,
                unitPriceCents: unitPriceCents,
                taxRateBps: taxRateBps,
                discountCents: item.discountCents,
                subtotalCents: item.lineSubtotalCents,
                notes: item.notes
            )
        }

        let salePayload = PosSalePayload(
            items: lines,
            customerId: cart.customer?.id,
            subtotalCents: cart.subtotalCents,
            discountCents: cart.effectiveDiscountCents,
            taxCents: cart.taxCents,
            tipCents: cart.tipCents,
            feesCents: cart.feesCents,
            feesLabel: cart.feesLabel,
            totalCents: cart.totalCents,
            cashSessionId: cashSession?.id,
            idempotencyKey: idempotencyKey
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(salePayload)
    }
}
