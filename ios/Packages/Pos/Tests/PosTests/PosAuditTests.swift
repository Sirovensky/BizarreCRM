import XCTest
@testable import Pos
import Persistence

/// §16.11 — Tests for PosTenantLimits, ZReportAggregates.from(auditEntries:), and
/// Cart.removeLine auditing logic.
///
/// These are pure unit tests — no DB required.  The audit store integration is
/// covered in PersistenceTests/PosAuditLogStoreTests.swift.
@MainActor
final class PosAuditTests: XCTestCase {

    // MARK: - PosTenantLimits defaults

    func test_defaultLimits_discountPercent() {
        XCTAssertEqual(PosTenantLimits.default.maxCashierDiscountPercent, 10)
    }

    func test_defaultLimits_discountCents() {
        XCTAssertEqual(PosTenantLimits.default.maxCashierDiscountCents, 2000)
    }

    func test_defaultLimits_priceOverrideThreshold() {
        XCTAssertEqual(PosTenantLimits.default.priceOverrideThresholdCents, 5000)
    }

    func test_defaultLimits_voidRequiresManager() {
        XCTAssertTrue(PosTenantLimits.default.voidRequiresManager)
    }

    func test_defaultLimits_noSaleRequiresManager() {
        XCTAssertTrue(PosTenantLimits.default.noSaleRequiresManager)
    }

    func test_defaultLimits_equatable() {
        let a = PosTenantLimits.default
        let b = PosTenantLimits.default
        XCTAssertEqual(a, b)
    }

    func test_limits_codable_roundTrip() throws {
        let limits = PosTenantLimits(
            maxCashierDiscountPercent: 15,
            maxCashierDiscountCents: 3000,
            priceOverrideThresholdCents: 10000,
            voidRequiresManager: false,
            noSaleRequiresManager: false
        )
        let data = try JSONEncoder().encode(limits)
        let decoded = try JSONDecoder().decode(PosTenantLimits.self, from: data)
        XCTAssertEqual(limits, decoded)
    }

    func test_limits_persist_andReload() {
        let limits = PosTenantLimits(
            maxCashierDiscountPercent: 20,
            maxCashierDiscountCents: 5000,
            priceOverrideThresholdCents: 8000,
            voidRequiresManager: false,
            noSaleRequiresManager: true
        )
        PosTenantLimits.persist(limits)
        let loaded = PosTenantLimits.current()
        XCTAssertEqual(loaded.maxCashierDiscountPercent, 20)
        XCTAssertEqual(loaded.maxCashierDiscountCents, 5000)
        XCTAssertEqual(loaded.priceOverrideThresholdCents, 8000)
        XCTAssertFalse(loaded.voidRequiresManager)
        XCTAssertTrue(loaded.noSaleRequiresManager)
    }

    // MARK: - ZReportAggregates.from(auditEntries:)

    func test_zReportFrom_emptyEntries_allCountsZero() {
        let result = ZReportAggregates.from(auditEntries: [])
        XCTAssertEqual(result.voidCount, 0)
        XCTAssertEqual(result.noSaleCount, 0)
        XCTAssertEqual(result.discountOverrideCount, 0)
    }

    func test_zReportFrom_countsVoidLines() {
        let entries = [
            makeEntry(type: "void_line"),
            makeEntry(type: "void_line"),
            makeEntry(type: "no_sale")
        ]
        let result = ZReportAggregates.from(auditEntries: entries)
        XCTAssertEqual(result.voidCount, 2)
        XCTAssertEqual(result.noSaleCount, 1)
        XCTAssertEqual(result.discountOverrideCount, 0)
    }

    func test_zReportFrom_countsDiscountOverrides() {
        let entries = [
            makeEntry(type: "discount_override"),
            makeEntry(type: "discount_override"),
            makeEntry(type: "discount_override"),
            makeEntry(type: "price_override")      // should NOT count as discount override
        ]
        let result = ZReportAggregates.from(auditEntries: entries)
        XCTAssertEqual(result.discountOverrideCount, 3)
    }

    func test_zReportFrom_preservesBaseFinancials() {
        let base = ZReportAggregates(
            salesCents: 100_000,
            taxCents: 8_000,
            tipsCents: 1_500,
            refundCents: 500,
            discountCents: 2_000
        )
        let result = ZReportAggregates.from(auditEntries: [], base: base)
        XCTAssertEqual(result.salesCents, 100_000)
        XCTAssertEqual(result.taxCents, 8_000)
        XCTAssertEqual(result.tipsCents, 1_500)
        XCTAssertEqual(result.refundCents, 500)
        XCTAssertEqual(result.discountCents, 2_000)
    }

    func test_zReportFrom_ignoresDeleteLineInVoidCount() {
        // delete_line is a separate event from void_line; Z-report should not conflate them.
        let entries = [
            makeEntry(type: "delete_line"),
            makeEntry(type: "delete_line"),
            makeEntry(type: "void_line")
        ]
        let result = ZReportAggregates.from(auditEntries: entries)
        XCTAssertEqual(result.voidCount, 1, "delete_line must not count as void_line")
    }

    // MARK: - ZReportAggregates: nil means "not loaded"

    func test_zReportAggregates_empty_hasNilCounts() {
        let agg = ZReportAggregates.empty
        XCTAssertNil(agg.voidCount)
        XCTAssertNil(agg.noSaleCount)
        XCTAssertNil(agg.discountOverrideCount)
    }

    // MARK: - Cart.removeLine audited removal

    func test_removeLine_removesItemFromCart() {
        let cart = Cart()
        let item = CartItem(name: "Test", unitPrice: Decimal(10))
        cart.add(item)
        XCTAssertEqual(cart.lineCount, 1)
        cart.removeLine(id: item.id, reason: "Test void")
        XCTAssertEqual(cart.lineCount, 0)
    }

    func test_removeLine_silentlyIgnoresUnknownId() {
        let cart = Cart()
        let item = CartItem(name: "Real item", unitPrice: Decimal(5))
        cart.add(item)
        // Remove with a random UUID that doesn't exist.
        cart.removeLine(id: UUID(), reason: nil)
        XCTAssertEqual(cart.lineCount, 1, "Unknown id must be a no-op")
    }

    func test_removeLine_withManagerId_removesCorrectItem() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: Decimal(1))
        let b = CartItem(name: "B", unitPrice: Decimal(2))
        cart.add(a)
        cart.add(b)
        cart.removeLine(id: a.id, reason: "Void A", managerId: 42)
        XCTAssertEqual(cart.lineCount, 1)
        XCTAssertEqual(cart.items.first?.name, "B")
    }

    // MARK: - Helpers

    private func makeEntry(type: String) -> PosAuditEntry {
        PosAuditEntry(eventType: type, cashierId: 0)
    }
}
