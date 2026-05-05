import XCTest
import SwiftUI
@testable import DesignSystem

// MARK: - ArrowKeyRowSelectionModifier unit tests

private struct Item: Identifiable {
    let id: String
    let name: String
}

final class ArrowKeyRowSelectionTests: XCTestCase {

    // MARK: - Helpers

    private let items = [
        Item(id: "a", name: "Alpha"),
        Item(id: "b", name: "Beta"),
        Item(id: "c", name: "Gamma"),
    ]

    // MARK: - Tests

    func testModifierInstantiates() {
        var sel: String? = nil
        let binding = Binding(get: { sel }, set: { sel = $0 })
        let modifier = ArrowKeyRowSelectionModifier(items: items, selectedId: binding)
        let _: any ViewModifier = modifier
        XCTAssertTrue(true)
    }

    func testViewExtensionInstantiates() {
        var sel: String? = nil
        let binding = Binding(get: { sel }, set: { sel = $0 })
        let view = List { Text("Row") }
            .arrowKeyRowSelection(items: items, selectedId: binding)
        let _: some View = view
        XCTAssertTrue(true)
    }

    func testEmptyItemsDoNotCrash() {
        var sel: String? = nil
        let binding = Binding(get: { sel }, set: { sel = $0 })
        let empty: [Item] = []
        let modifier = ArrowKeyRowSelectionModifier(items: empty, selectedId: binding)
        // Just instantiate — no crash
        let _: any ViewModifier = modifier
        XCTAssertNil(sel)
    }
}
