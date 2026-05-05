import XCTest
@testable import Inventory
import Networking

// MARK: - §22 iPad Polish Tests
//
// Coverage targets:
//   • InventoryTableView sort helpers (InventoryListItem extensions)
//   • InventoryShortcutManifest — no duplicate keys, correct count
//   • InventoryContextMenu copy-SKU logic (via InventoryListItem model)
//   • InventoryThreeColumnView filter-icon helper (indirect via manifest)
//
// These tests are pure-logic / value-type tests that run on any platform.
// They do NOT import SwiftUI, so they compile on Linux/macOS headless CI.

// MARK: - InventoryListItem sort helpers

final class InventoryListItemSortableTests: XCTestCase {

    // MARK: sortableSku

    func test_sortableSku_returnsSku_whenPresent() {
        let item = makeItem(sku: "SKU-001")
        XCTAssertEqual(item.sortableSku, "SKU-001")
    }

    func test_sortableSku_returnsHighSentinel_whenNil() {
        let item = makeItem(sku: nil)
        // Sentinel must sort after any real SKU alphabetically.
        XCTAssertGreaterThan(item.sortableSku, "ZZZ-999")
    }

    func test_sortableSku_returnsHighSentinel_whenEmpty() {
        // An empty string has a sku value, so it IS returned as-is.
        let item = makeItem(sku: "")
        XCTAssertEqual(item.sortableSku, "")
    }

    // MARK: sortableType

    func test_sortableType_returnsType_whenPresent() {
        let item = makeItem(itemType: "product")
        XCTAssertEqual(item.sortableType, "product")
    }

    func test_sortableType_returnsHighSentinel_whenNil() {
        let item = makeItem(itemType: nil)
        XCTAssertGreaterThan(item.sortableType, "ZZZ")
    }

    // MARK: sortableStock

    func test_sortableStock_returnsInStock_whenPresent() {
        let item = makeItem(inStock: 42)
        XCTAssertEqual(item.sortableStock, 42)
    }

    func test_sortableStock_returnsZero_whenNil() {
        let item = makeItem(inStock: nil)
        XCTAssertEqual(item.sortableStock, 0)
    }

    func test_sortableStock_handlesNegative() {
        let item = makeItem(inStock: -5)
        XCTAssertEqual(item.sortableStock, -5)
    }

    // MARK: sortablePrice

    func test_sortablePrice_returnsRetailPrice_whenPresent() {
        let item = makeItem(retailPrice: 9.99)
        XCTAssertEqual(item.sortablePrice, 9.99, accuracy: 0.001)
    }

    func test_sortablePrice_returnsMaxDouble_whenNil() {
        let item = makeItem(retailPrice: nil)
        XCTAssertEqual(item.sortablePrice, Double.greatestFiniteMagnitude)
    }

    // MARK: Sorting correctness

    func test_sortBySku_nilLast() {
        let a = makeItem(id: 1, sku: "AAA")
        let b = makeItem(id: 2, sku: nil)
        let c = makeItem(id: 3, sku: "BBB")
        let sorted = [b, c, a].sorted { $0.sortableSku < $1.sortableSku }
        XCTAssertEqual(sorted.map(\.id), [1, 3, 2])
    }

    func test_sortByStock_ascending() {
        let items = [
            makeItem(id: 1, inStock: 10),
            makeItem(id: 2, inStock: 0),
            makeItem(id: 3, inStock: 5),
        ]
        let sorted = items.sorted { $0.sortableStock < $1.sortableStock }
        XCTAssertEqual(sorted.map(\.id), [2, 3, 1])
    }

    func test_sortByPrice_nilLast() {
        let cheap  = makeItem(id: 1, retailPrice: 1.00)
        let noPrice = makeItem(id: 2, retailPrice: nil)
        let pricey  = makeItem(id: 3, retailPrice: 99.99)
        let sorted = [noPrice, pricey, cheap].sorted { $0.sortablePrice < $1.sortablePrice }
        XCTAssertEqual(sorted.map(\.id), [1, 3, 2])
    }

    func test_sortByName_alphabetical() {
        let items = [
            makeItem(id: 1, name: "Zebra Cable"),
            makeItem(id: 2, name: "Apple Charger"),
            makeItem(id: 3, name: "Mouse Pad"),
        ]
        let sorted = items.sorted { $0.displayName < $1.displayName }
        XCTAssertEqual(sorted.map(\.id), [2, 3, 1])
    }
}

// MARK: - InventoryShortcutManifest

final class InventoryShortcutManifestTests: XCTestCase {

    func test_manifest_noDuplicateKeys() {
        XCTAssertFalse(
            InventoryShortcutManifest.hasDuplicateKeys,
            "Keyboard shortcut keys must be unique"
        )
    }

    func test_manifest_containsNewItem() {
        let found = InventoryShortcutManifest.all.contains {
            $0.key == "N" && $0.modifiers == .command
        }
        XCTAssertTrue(found, "Manifest must include ⌘N — New item")
    }

    func test_manifest_containsAdjustStock() {
        let found = InventoryShortcutManifest.all.contains {
            $0.key == "A" && $0.modifiers == .command
        }
        XCTAssertTrue(found, "Manifest must include ⌘A — Adjust stock")
    }

    func test_manifest_containsLowStock() {
        let found = InventoryShortcutManifest.all.contains {
            $0.key == "L" && $0.modifiers == [.command, .shift]
        }
        XCTAssertTrue(found, "Manifest must include ⌘⇧L — Low stock")
    }

    func test_manifest_containsTableView() {
        let found = InventoryShortcutManifest.all.contains {
            $0.key == "1" && $0.modifiers == [.command, .option]
        }
        XCTAssertTrue(found, "Manifest must include ⌘⌥1 — Table view")
    }

    func test_manifest_containsListView() {
        let found = InventoryShortcutManifest.all.contains {
            $0.key == "2" && $0.modifiers == [.command, .option]
        }
        XCTAssertTrue(found, "Manifest must include ⌘⌥2 — List view")
    }

    func test_manifest_containsArchive() {
        let found = InventoryShortcutManifest.all.contains {
            $0.key == "⌫" && $0.modifiers == .command
        }
        XCTAssertTrue(found, "Manifest must include ⌘⌫ — Archive")
    }

    func test_manifest_minimumCount() {
        // We defined 9 shortcuts. Guard against accidental deletions.
        XCTAssertGreaterThanOrEqual(InventoryShortcutManifest.all.count, 9)
    }

    func test_shortcutModifiers_optionSetComposition() {
        let cs: InventoryShortcut.ShortcutModifiers = [.command, .shift]
        XCTAssertTrue(cs.contains(.command))
        XCTAssertTrue(cs.contains(.shift))
        XCTAssertFalse(cs.contains(.option))
    }
}

// MARK: - InventoryListItem display helpers (used by context menu preview)

final class InventoryListItemDisplayTests: XCTestCase {

    func test_displayName_returnsName_whenNonEmpty() {
        let item = makeItem(name: "Widget Pro")
        XCTAssertEqual(item.displayName, "Widget Pro")
    }

    func test_displayName_returnsUnnamed_whenNil() {
        let item = makeItem(name: nil)
        XCTAssertEqual(item.displayName, "Unnamed")
    }

    func test_displayName_returnsUnnamed_whenEmpty() {
        let item = makeItem(name: "")
        XCTAssertEqual(item.displayName, "Unnamed")
    }

    func test_isLowStock_true_whenStockBelowReorder() {
        let item = makeItem(inStock: 2, reorderLevel: 5)
        XCTAssertTrue(item.isLowStock)
    }

    func test_isLowStock_false_whenStockAboveReorder() {
        let item = makeItem(inStock: 10, reorderLevel: 5)
        XCTAssertFalse(item.isLowStock)
    }

    func test_isLowStock_false_whenReorderLevelZero() {
        let item = makeItem(inStock: 0, reorderLevel: 0)
        XCTAssertFalse(item.isLowStock)
    }

    func test_isLowStock_true_whenEqualToReorderLevel() {
        let item = makeItem(inStock: 5, reorderLevel: 5)
        XCTAssertTrue(item.isLowStock)
    }

    func test_priceCents_roundsCorrectly() {
        let item = makeItem(retailPrice: 9.99)
        XCTAssertEqual(item.priceCents, 999)
    }

    func test_priceCents_nil_whenRetailPriceNil() {
        let item = makeItem(retailPrice: nil)
        XCTAssertNil(item.priceCents)
    }

    func test_priceCents_handlesLargePrice() {
        let item = makeItem(retailPrice: 1_000.00)
        XCTAssertEqual(item.priceCents, 100_000)
    }
}

// MARK: - InventoryShortcut Equatable / value semantics

final class InventoryShortcutValueTests: XCTestCase {

    func test_shortcut_equality_sameKeyAndModifiers() {
        let a = InventoryShortcut(key: "N", modifiers: .command, description: "New item")
        let b = InventoryShortcut(key: "N", modifiers: .command, description: "Different description")
        XCTAssertEqual(a, b)
    }

    func test_shortcut_inequality_differentKey() {
        let a = InventoryShortcut(key: "N", modifiers: .command, description: "New item")
        let b = InventoryShortcut(key: "M", modifiers: .command, description: "New item")
        XCTAssertNotEqual(a, b)
    }

    func test_shortcut_inequality_differentModifiers() {
        let a = InventoryShortcut(key: "N", modifiers: .command, description: "New item")
        let b = InventoryShortcut(key: "N", modifiers: [.command, .shift], description: "New item")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - Helpers

private func makeItem(
    id: Int64 = 1,
    name: String? = "Test Item",
    sku: String? = "SKU-TEST",
    itemType: String? = "product",
    inStock: Int? = 10,
    reorderLevel: Int? = 5,
    retailPrice: Double? = 19.99,
    costPrice: Double? = nil
) -> InventoryListItem {
    // InventoryListItem is Decodable — build via JSON encoding to avoid
    // a memberwise init dependency on the public surface.
    let json: [String: Any?] = [
        "id": id,
        "name": name,
        "sku": sku,
        "item_type": itemType,
        "in_stock": inStock,
        "reorder_level": reorderLevel,
        "retail_price": retailPrice,
        "cost_price": costPrice,
        "upc_code": nil,
        "manufacturer_name": nil,
        "device_name": nil,
        "supplier_name": nil,
        "is_serialized": nil,
    ]
    let cleaned: [String: Any] = json.compactMapValues { $0 }
    let data = try! JSONSerialization.data(withJSONObject: cleaned)
    return try! JSONDecoder().decode(InventoryListItem.self, from: data)
}
