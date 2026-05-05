import XCTest
import Networking
@testable import Pos

/// Tests for the held-cart save/restore round-trip at the payload level.
///
/// No network calls. Verifies that `CreateHeldCartRequest` is built correctly
/// from a `Cart`, and that a `PosHeldCartRow.cartJson` can be deserialised
/// back into a `CartSnapshot` and restored into a fresh `Cart`.
///
/// `@MainActor` is required because `Cart`, `CartSnapshot.from(cart:)` and
/// `CartSnapshot.restore(into:)` are all `@MainActor`-isolated.
@MainActor
final class HeldCartEndpointTests: XCTestCase {

    // MARK: - CreateHeldCartRequest encoding

    func test_createRequest_cartJsonIsValidJSON() throws {
        let cart = makeCart()
        let snapshot = CartSnapshot.from(cart: cart)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let jsonString = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(jsonString.isEmpty)

        // Verify it's parseable JSON.
        let parsed = try JSONSerialization.jsonObject(with: Data(jsonString.utf8))
        XCTAssertNotNil(parsed)
    }

    func test_createRequest_setsLabel() throws {
        let cart = makeCart()
        let snapshot = CartSnapshot.from(cart: cart)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cartJson = String(decoding: try encoder.encode(snapshot), as: UTF8.self)

        let request = CreateHeldCartRequest(
            cartJson: cartJson,
            label: "Table 7",
            customerId: 42,
            totalCents: cart.totalCents
        )
        XCTAssertEqual(request.label, "Table 7")
        XCTAssertEqual(request.customerId, 42)
        XCTAssertEqual(request.totalCents, cart.totalCents)
    }

    func test_createRequest_nilLabel_whenNoteIsEmpty() throws {
        let cart = makeCart()
        let snapshot = CartSnapshot.from(cart: cart)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cartJson = String(decoding: try encoder.encode(snapshot), as: UTF8.self)

        let request = CreateHeldCartRequest(cartJson: cartJson, label: nil)
        XCTAssertNil(request.label)
    }

    // MARK: - PosHeldCartRow JSON round-trip

    func test_cartJson_restoresIntoCart() throws {
        let original = makeCart(items: [
            (id: 1, name: "Case",   qty: 2, price: Decimal(string: "15.00")!),
            (id: 2, name: "Screen", qty: 1, price: Decimal(string: "89.99")!),
        ])

        // Serialise.
        let snapshot = CartSnapshot.from(cart: original)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cartJson = String(decoding: try encoder.encode(snapshot), as: UTF8.self)

        // Restore.
        let restored = Cart()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(cartJson.utf8)
        let decodedSnapshot = try decoder.decode(CartSnapshot.self, from: data)
        decodedSnapshot.restore(into: restored)

        XCTAssertEqual(restored.lineCount, 2)
        XCTAssertEqual(restored.items[0].name, "Case")
        XCTAssertEqual(restored.items[0].quantity, 2)
        XCTAssertEqual(restored.items[1].name, "Screen")
        // Totals must match the original (before any discount/tip).
        XCTAssertEqual(restored.subtotalCents, original.subtotalCents)
    }

    func test_cartJson_corruptFallback_doesNotCrash() {
        // Simulate a held-cart row whose cart_json is corrupt.
        let row = PosHeldCartRow(
            id: 1,
            userId: 10,
            cartJson: "THIS IS NOT JSON",
            createdAt: "2026-04-23T00:00:00.000Z"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Decoding must fail gracefully (not crash the app).
        let result = try? decoder.decode(CartSnapshot.self, from: Data(row.cartJson.utf8))
        XCTAssertNil(result)
    }

    // MARK: - PosHeldCartRow displayLabel

    func test_displayLabel_usesLabelWhenPresent() {
        let row = PosHeldCartRow(id: 5, userId: 1, cartJson: "{}", label: "Rush order", createdAt: "2026-01-01T00:00:00Z")
        XCTAssertEqual(row.displayLabel, "Rush order")
    }

    func test_displayLabel_fallbackToHoldId() {
        let row = PosHeldCartRow(id: 42, userId: 1, cartJson: "{}", label: nil, createdAt: "2026-01-01T00:00:00Z")
        XCTAssertEqual(row.displayLabel, "Hold #42")
    }

    func test_ownerName_combinesFirstAndLast() {
        let row = PosHeldCartRow(
            id: 1, userId: 1, cartJson: "{}",
            createdAt: "2026-01-01T00:00:00Z",
            ownerFirstName: "Jane",
            ownerLastName: "Smith"
        )
        XCTAssertEqual(row.ownerName, "Jane Smith")
    }

    func test_ownerName_nilWhenBothAbsent() {
        let row = PosHeldCartRow(id: 1, userId: 1, cartJson: "{}", createdAt: "2026-01-01T00:00:00Z")
        XCTAssertNil(row.ownerName)
    }

    // MARK: - Helpers

    private func makeCart(
        items: [(id: Int64, name: String, qty: Int, price: Decimal)]? = nil
    ) -> Cart {
        let cart = Cart()
        let rows = items ?? [(id: 1, name: "Widget", qty: 1, price: Decimal(string: "9.99")!)]
        for row in rows {
            cart.add(CartItem(
                inventoryItemId: row.id,
                name: row.name,
                quantity: row.qty,
                unitPrice: row.price
            ))
        }
        return cart
    }
}
