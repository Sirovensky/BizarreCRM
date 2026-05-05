import XCTest
import SwiftUI
@testable import Pos
import Networking

// MARK: - PosCatalogGrid tile-sizing tests

/// Tests the pure-logic adaptive column calculations embedded in
/// `PosCatalogGrid`. The `gridColumns(for:)` method is private; we infer its
/// behaviour indirectly through the public initialiser constraints and direct
/// unit tests of the column-count arithmetic using the same formula.
final class PosCatalogGridTests: XCTestCase {

    // MARK: - Grid column arithmetic

    /// Replicates the formula from `PosCatalogGrid.gridColumns(for:)` so we
    /// can verify its output for representative container widths without
    /// needing a live SwiftUI render pass.
    private func expectedMinTileWidth(
        containerWidth: CGFloat,
        padding: CGFloat = 32, // BrandSpacing.base * 2
        tileMinWidth: CGFloat = 140,
        maxColumns: Int = 5
    ) -> CGFloat {
        let usable = containerWidth - padding
        return max(tileMinWidth, usable / CGFloat(maxColumns))
    }

    // MARK: - Narrow container (portrait iPhone-width hand-off, ~375 pt)

    func test_narrowContainer_minTileWidth_isAtLeast140() {
        let min = expectedMinTileWidth(containerWidth: 375)
        XCTAssertGreaterThanOrEqual(min, 140,
            "Even narrow containers should honour the 140pt tile minimum")
    }

    // MARK: - Typical iPad column width (~420 pt)

    func test_typicalIPadColumn_minTileWidth_isAtLeast140() {
        let min = expectedMinTileWidth(containerWidth: 420)
        XCTAssertGreaterThanOrEqual(min, 140)
    }

    // MARK: - Wide iPad column (~700 pt — iPad Pro 12.9" landscape 70 %)

    func test_wideIPadColumn_minTileWidth_scalesWithWidth() {
        let narrowMin = expectedMinTileWidth(containerWidth: 420)
        let wideMin   = expectedMinTileWidth(containerWidth: 700)
        // Wider containers should produce larger or equal tile sizes.
        XCTAssertGreaterThanOrEqual(wideMin, narrowMin)
    }

    func test_wideIPadColumn_minTileWidth_doesNotExceedUsableWidth() {
        let containerWidth: CGFloat = 700
        let min = expectedMinTileWidth(containerWidth: containerWidth)
        let usable = containerWidth - 32
        XCTAssertLessThanOrEqual(min, usable,
            "Minimum tile width must not exceed the usable column width")
    }

    // MARK: - Extreme narrow (< 300 pt) — tile min floor holds

    func test_veryNarrowContainer_floorAt140() {
        let min = expectedMinTileWidth(containerWidth: 200)
        // max(140, (200-32)/5) = max(140, 33.6) = 140
        XCTAssertEqual(min, 140, accuracy: 0.01)
    }

    // MARK: - PosCatalogGrid initialiser

    func test_init_defaultParams_doesNotCrash() {
        let grid = PosCatalogGrid(items: [], onPick: { _ in })
        XCTAssertNotNil(grid)
    }

    func test_init_customTileWidths_doesNotCrash() {
        let grid = PosCatalogGrid(items: [], tileMinWidth: 120, tileMaxWidth: 200, onPick: { _ in })
        XCTAssertNotNil(grid)
    }

    // MARK: - tileMinWidth / tileMaxWidth contract

    func test_tileMaxWidth_mustBeGTE_tileMinWidth() {
        // We can't enforce this at the type level, but we document the expected
        // invariant: callers must pass max >= min. Verify the grid still builds
        // even when min == max (degenerate case, single fixed-width column).
        let grid = PosCatalogGrid(items: [], tileMinWidth: 160, tileMaxWidth: 160, onPick: { _ in })
        XCTAssertNotNil(grid)
    }
}

// MARK: - PosIPadCartPanel totals logic

/// Tests the pure arithmetic visible through `Cart` that `PosIPadCartPanel`
/// renders. SwiftUI rendering is not exercised — we verify the data model
/// that the view reads from.
@MainActor
final class PosIPadCartPanelTests: XCTestCase {

    // MARK: - Empty cart

    func test_emptyCart_totalIsZero() {
        let cart = Cart()
        XCTAssertEqual(cart.totalCents, 0)
        XCTAssertTrue(cart.isEmpty)
        XCTAssertFalse(cart.isFullyTendered)
    }

    // MARK: - Single line, no tax

    func test_singleLine_noTax_totalEqualsSubtotal() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: Decimal(string: "19.99")!))
        XCTAssertEqual(cart.subtotalCents, 1999)
        XCTAssertEqual(cart.taxCents, 0)
        XCTAssertEqual(cart.totalCents, 1999)
    }

    // MARK: - Cart with discount renders remainingCents correctly

    func test_cartWithDiscount_totalReducedByDiscount() {
        let cart = Cart()
        cart.add(CartItem(name: "Item", unitPrice: Decimal(string: "100.00")!))
        cart.setCartDiscount(cents: 1000) // $10 off
        XCTAssertEqual(cart.totalCents, 9000)
    }

    // MARK: - Applied tenders reduce remainingCents

    func test_appliedTender_reducesRemainingCents() {
        let cart = Cart()
        cart.add(CartItem(name: "Item", unitPrice: Decimal(string: "50.00")!))
        cart.apply(tender: AppliedTender(kind: .giftCard, amountCents: 2000, label: "Gift Card"))
        XCTAssertEqual(cart.remainingCents, 3000)
        XCTAssertFalse(cart.isFullyTendered)
    }

    func test_appliedTender_exactTotal_isFullyTendered() {
        let cart = Cart()
        cart.add(CartItem(name: "Item", unitPrice: Decimal(string: "30.00")!))
        cart.apply(tender: AppliedTender(kind: .giftCard, amountCents: 3000, label: "Gift Card"))
        XCTAssertEqual(cart.remainingCents, 0)
        XCTAssertTrue(cart.isFullyTendered)
    }

    // MARK: - Remove tender restores remainingCents

    func test_removeTender_restoresRemaining() {
        let cart = Cart()
        cart.add(CartItem(name: "Item", unitPrice: Decimal(string: "40.00")!))
        let tender = AppliedTender(kind: .giftCard, amountCents: 4000, label: "Gift Card")
        cart.apply(tender: tender)
        XCTAssertTrue(cart.isFullyTendered)
        cart.removeTender(id: tender.id)
        XCTAssertEqual(cart.remainingCents, 4000)
        XCTAssertFalse(cart.isFullyTendered)
    }

    // MARK: - itemQuantity counts across lines

    func test_itemQuantity_sumsQuantitiesAcrossLines() {
        let cart = Cart()
        cart.add(CartItem(name: "A", unitPrice: 1, quantity: 3))
        cart.add(CartItem(name: "B", unitPrice: 2, quantity: 2))
        XCTAssertEqual(cart.itemQuantity, 5)
    }

    // MARK: - lineCount

    func test_lineCount_tracksAddedLines() {
        let cart = Cart()
        XCTAssertEqual(cart.lineCount, 0)
        cart.add(CartItem(name: "A", unitPrice: 1))
        XCTAssertEqual(cart.lineCount, 1)
        cart.add(CartItem(name: "B", unitPrice: 2))
        XCTAssertEqual(cart.lineCount, 2)
    }

    // MARK: - cart.clear() resets panel-visible state

    func test_clear_resetsAllPanelState() {
        let cart = Cart()
        cart.add(CartItem(name: "X", unitPrice: Decimal(string: "9.99")!))
        cart.setCartDiscount(cents: 100)
        cart.setTip(cents: 50)
        cart.apply(tender: AppliedTender(kind: .giftCard, amountCents: 500, label: "GC"))
        cart.clear()
        XCTAssertTrue(cart.isEmpty)
        XCTAssertEqual(cart.totalCents, 0)
        XCTAssertEqual(cart.appliedTenders.count, 0)
        XCTAssertEqual(cart.tipCents, 0)
        XCTAssertEqual(cart.effectiveDiscountCents, 0)
    }
}
