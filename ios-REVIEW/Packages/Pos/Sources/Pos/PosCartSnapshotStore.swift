import Foundation
import Core

// MARK: - CartSnapshot

/// Serialisable cart snapshot written to UserDefaults on every mutation.
/// Carries a `savedAt` timestamp so stale snapshots (> 24h) are discarded on restore.
///
/// TODO(Phase 3): migrate storage backend from UserDefaults to GRDB.
public struct CartSnapshot: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let id: String          // UUID string
        public let inventoryItemId: Int64?
        public let name: String
        public let sku: String?
        public let quantity: Int
        public let unitPriceCents: Int // Decimal → Int cents for lossless Codable
        public let taxRateBps: Int?    // basis points; nil = no tax
        public let discountCents: Int
        public let notes: String?
    }

    public struct Customer: Codable, Sendable {
        public let id: Int64?
        public let displayName: String
        public let email: String?
        public let phone: String?
    }

    public let items: [Item]
    public let customer: Customer?
    public let cartDiscountCents: Int
    public let cartDiscountPercent: Double?
    public let tipCents: Int
    public let feesCents: Int
    public let feesLabel: String?
    public let savedAt: Date

    public init(
        items: [Item],
        customer: Customer?,
        cartDiscountCents: Int,
        cartDiscountPercent: Double?,
        tipCents: Int,
        feesCents: Int,
        feesLabel: String?,
        savedAt: Date = Date()
    ) {
        self.items = items
        self.customer = customer
        self.cartDiscountCents = cartDiscountCents
        self.cartDiscountPercent = cartDiscountPercent
        self.tipCents = tipCents
        self.feesCents = feesCents
        self.feesLabel = feesLabel
        self.savedAt = savedAt
    }

    /// Snapshots older than 24 h are considered expired and must not be restored.
    public var isExpired: Bool {
        Date().timeIntervalSince(savedAt) > 24 * 60 * 60
    }
}

// MARK: - PosCartSnapshotStore

/// Actor that persists a `CartSnapshot` in `UserDefaults` under the
/// key `"pos_cart_snapshot"`. Reads and writes are isolated to the actor
/// executor, satisfying Swift 6 strict-concurrency rules.
///
/// MVP notes
/// - `UserDefaults` is synchronous; the actor isolation ensures no data races.
/// - Snapshots older than 24 h are silently discarded on `load()`.
/// - Phase 3 will migrate the backing store to GRDB; the actor boundary makes
///   that a one-file change with no API surface impact.
public actor PosCartSnapshotStore {
    public static let shared = PosCartSnapshotStore()

    private let defaults: UserDefaults
    private let key = "pos_cart_snapshot"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// Persist `snapshot` to UserDefaults. Overwrites any existing snapshot.
    public func save(_ snapshot: CartSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: key)
        } catch {
            AppLog.pos.error("PosCartSnapshotStore.save failed: \(error, privacy: .public)")
        }
    }

    /// Load the most recent snapshot. Returns `nil` if none exists or if the
    /// snapshot is older than 24 h (expired). Expired snapshots are pruned
    /// automatically so they don't accumulate.
    public func load() -> CartSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let snapshot = try decoder.decode(CartSnapshot.self, from: data)
            if snapshot.isExpired {
                AppLog.pos.info("PosCartSnapshotStore: snapshot expired, discarding")
                defaults.removeObject(forKey: key)
                return nil
            }
            return snapshot
        } catch {
            AppLog.pos.error("PosCartSnapshotStore.load failed: \(error, privacy: .public)")
            defaults.removeObject(forKey: key)   // corrupt data — purge it
            return nil
        }
    }

    /// Delete the stored snapshot. Call after a successful checkout or cart clear.
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Cart ↔ CartSnapshot conversion helpers

extension CartSnapshot {
    /// Build a snapshot from the live `Cart` object.
    @MainActor
    public static func from(cart: Cart, sessionId: Int64? = nil) -> CartSnapshot {
        let items = cart.items.map { item in
            let unitPriceCents = CartMath.toCents(item.unitPrice)
            let taxRateBps: Int? = item.taxRate.map { rate in
                // Decimal → basis points (e.g. 0.08 → 800)
                CartMath.toCents(rate * 100)    // cents of percent = bps
            }
            return CartSnapshot.Item(
                id: item.id.uuidString,
                inventoryItemId: item.inventoryItemId,
                name: item.name,
                sku: item.sku,
                quantity: item.quantity,
                unitPriceCents: unitPriceCents,
                taxRateBps: taxRateBps,
                discountCents: item.discountCents,
                notes: item.notes
            )
        }

        let customer = cart.customer.map { c in
            CartSnapshot.Customer(
                id: c.id,
                displayName: c.displayName,
                email: c.email,
                phone: c.phone
            )
        }

        return CartSnapshot(
            items: items,
            customer: customer,
            cartDiscountCents: cart.cartDiscountCents,
            cartDiscountPercent: cart.cartDiscountPercent,
            tipCents: cart.tipCents,
            feesCents: cart.feesCents,
            feesLabel: cart.feesLabel
        )
    }

    /// Restore snapshot state back onto `cart`. Replaces all mutable fields.
    @MainActor
    public func restore(into cart: Cart) {
        cart.clear()

        let cartItems = items.compactMap { raw -> CartItem? in
            guard let uuid = UUID(uuidString: raw.id) else { return nil }
            let unitPrice = Decimal(raw.unitPriceCents) / 100
            let taxRate: Decimal? = raw.taxRateBps.map { bps in
                Decimal(bps) / 10_000   // bps → rate (800 bps = 0.08)
            }
            return CartItem(
                id: uuid,
                inventoryItemId: raw.inventoryItemId,
                name: raw.name,
                sku: raw.sku,
                quantity: raw.quantity,
                unitPrice: unitPrice,
                taxRate: taxRate,
                discountCents: raw.discountCents,
                notes: raw.notes
            )
        }

        for item in cartItems { cart.add(item) }

        if let c = customer {
            cart.attach(customer: PosCustomer(
                id: c.id,
                displayName: c.displayName,
                email: c.email,
                phone: c.phone
            ))
        }

        if let pct = cartDiscountPercent {
            cart.setCartDiscountPercent(pct)
        } else {
            cart.setCartDiscount(cents: cartDiscountCents)
        }

        cart.setTip(cents: tipCents)
        cart.setFees(cents: feesCents, label: feesLabel)
    }
}
