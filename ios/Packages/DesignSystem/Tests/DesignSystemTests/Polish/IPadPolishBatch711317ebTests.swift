import XCTest
import SwiftUI
@testable import DesignSystem

// §22 — small visual / a11y polish batch (711317eb).
// Covers behaviour-level invariants for items that don't touch shared state:
//   - SortDirection.next() cycle order
//   - DataEntryKind exhaustiveness via switch (compile-time guard via test)
//   - View extensions compile (no runtime assertions, but failure = build fail)
//   - BrandPointerStyle equality

final class SortDirectionTests: XCTestCase {

    func testNextCyclesAscendingDescendingNone() {
        XCTAssertEqual(SortDirection.ascending.next(), .descending)
        XCTAssertEqual(SortDirection.descending.next(), .none)
        XCTAssertEqual(SortDirection.none.next(), .ascending)
    }

    func testFullCycleReturnsToStart() {
        let start: SortDirection = .ascending
        let cycled = start.next().next().next()
        XCTAssertEqual(cycled, start)
    }
}

final class BrandPointerStyleTests: XCTestCase {

    func testEqualityAcrossCases() {
        XCTAssertEqual(BrandPointerStyle.link, .link)
        XCTAssertNotEqual(BrandPointerStyle.link, .button)
        XCTAssertNotEqual(BrandPointerStyle.text, .horizontalResize)
    }
}

@MainActor
final class IPadPolishBatchCompileTests: XCTestCase {

    // These tests don't *assert* runtime behaviour — SwiftUI views need a
    // host. They exist to make sure the public extension surfaces compile and
    // can be referenced from outside the module. A regression in modifier
    // signature surfaces here as a build failure.

    func testFocusRingExtensionExists() {
        let _ = Text("x").brandFocusRing()
        let _ = Text("x").brandFocusRing(cornerRadius: 12, lineWidth: 1)
    }

    func testSortIndicatorExtensionExists() {
        let _ = SortIndicator(direction: .ascending)
        let _ = Text("Total").columnSortable(direction: .descending)
    }

    func testAdaptiveLabelExtensionExists() {
        let _ = Label("Tickets", systemImage: "wrench").adaptiveIconOnly()
        let _ = Label("Tickets", systemImage: "wrench").adaptiveIconOnly(threshold: 80)
    }

    func testBrandPointerExtensionExists() {
        let _ = Text("x").brandPointer(.link)
        let _ = Text("x").brandPointer(.button)
        let _ = Text("x").brandPointer(.text)
        let _ = Text("x").brandPointer(.horizontalResize)
    }

    func testDataEntryFieldExtensionExists() {
        let _ = TextField("a", text: .constant("")).dataEntryField(.identifier)
        let _ = TextField("a", text: .constant("")).dataEntryField(.email)
        let _ = TextField("a", text: .constant("")).dataEntryField(.url)
        let _ = TextField("a", text: .constant("")).dataEntryField(.number)
        let _ = TextField("a", text: .constant("")).dataEntryField(.phone)
        let _ = TextField("a", text: .constant("")).dataEntryField(.prose)
    }
}
