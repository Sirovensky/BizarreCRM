import XCTest
@testable import Pos

/// §16.7 — Tests for `ReceiptModelStore`.
final class ReceiptModelStoreTests: XCTestCase {

    // Each test creates a fresh actor; UserDefaults key is namespaced per test
    // by writing directly to the instance. Since the store uses a fixed key we
    // reset via `UserDefaults.standard.removeObject(forKey:)` in setUp/tearDown.

    private static let key = "com.bizarrecrm.pos.receiptModels"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    func test_save_and_load_roundTrip() async throws {
        let store = ReceiptModelStore.shared
        let model = ReceiptModelStore.StoredReceiptModel(
            invoiceId: 42,
            receiptNumber: "R-001",
            amountPaidCents: 1000,
            methodLabel: "Cash"
        )
        await store.save(model)
        let loaded = await store.load(invoiceId: 42)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.invoiceId, 42)
        XCTAssertEqual(loaded?.amountPaidCents, 1000)
    }

    func test_save_overwrites_duplicate_invoiceId() async throws {
        let store = ReceiptModelStore.shared
        let first = ReceiptModelStore.StoredReceiptModel(
            invoiceId: 99,
            receiptNumber: "R-001",
            amountPaidCents: 500,
            methodLabel: "Cash"
        )
        let second = ReceiptModelStore.StoredReceiptModel(
            invoiceId: 99,
            receiptNumber: "R-001",
            amountPaidCents: 750,
            methodLabel: "Card"
        )
        await store.save(first)
        await store.save(second)
        let all = await store.allNewestFirst()
        XCTAssertEqual(all.count, 1, "Duplicate invoiceId should be overwritten")
        XCTAssertEqual(all.first?.amountPaidCents, 750)
    }

    func test_load_missing_returns_nil() async throws {
        let store = ReceiptModelStore.shared
        let result = await store.load(invoiceId: 999)
        XCTAssertNil(result)
    }

    func test_allNewestFirst_includes_multiple() async throws {
        let store = ReceiptModelStore.shared
        for i in 1...5 {
            let m = ReceiptModelStore.StoredReceiptModel(
                invoiceId: Int64(i),
                receiptNumber: "R-\(i)",
                amountPaidCents: i * 100,
                methodLabel: "Cash"
            )
            await store.save(m)
        }
        let all = await store.allNewestFirst()
        XCTAssertEqual(all.count, 5)
    }
}
