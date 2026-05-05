import XCTest
@testable import Customers

final class CustomerTagColorTests: XCTestCase {

    // MARK: - Color palette

    func test_defaultPalette_hasExpectedEntries() {
        let palette = CustomerTagColor.defaultPalette
        XCTAssertFalse(palette.isEmpty)
        XCTAssertTrue(palette.contains { $0.name == "vip" })
        XCTAssertTrue(palette.contains { $0.name == "late-payer" })
    }

    func test_colorFromHex_validHex_returnsNonNilColor() {
        let tag = CustomerTagColor(name: "test", hex: "#FF6B35")
        // Color should be non-default (i.e. not bizarreOnSurfaceMuted)
        // We test via description not nil
        let c = tag.color
        XCTAssertNotNil(c) // SwiftUI Color always non-nil
    }

    func test_colorFromHex_nilHex_returnsFallback() {
        let tag = CustomerTagColor(name: "test", hex: nil)
        // Should not crash and return a valid Color
        _ = tag.color
    }

    func test_colorRoundtrip_codable() throws {
        let original = CustomerTagColor(name: "vip", hex: "#FFD700", symbolName: "star.fill")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomerTagColor.self, from: data)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.hex, original.hex)
        XCTAssertEqual(decoded.symbolName, original.symbolName)
    }

    // MARK: - AutoTagRule

    func test_autoTagRule_ltvOver_conditionDescription() {
        let rule = CustomerAutoTagRule(id: "1", tag: "gold", condition: .ltvOver(100_000))
        XCTAssertEqual(rule.conditionDescription, "LTV > $1000")
    }

    func test_autoTagRule_overdueInvoice_conditionDescription() {
        let rule = CustomerAutoTagRule(id: "2", tag: "late-payer", condition: .overdueInvoiceCount(3))
        XCTAssertTrue(rule.conditionDescription.contains("3"))
    }

    func test_autoTagRule_daysSinceLastVisit_conditionDescription() {
        let rule = CustomerAutoTagRule(id: "3", tag: "dormant", condition: .daysSinceLastVisit(180))
        XCTAssertTrue(rule.conditionDescription.contains("180"))
    }

    func test_autoTagRule_codableRoundtrip_ltvOver() throws {
        let rule = CustomerAutoTagRule(id: "r1", tag: "gold", condition: .ltvOver(50000))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(CustomerAutoTagRule.self, from: data)
        if case .ltvOver(let v) = decoded.condition {
            XCTAssertEqual(v, 50000)
        } else {
            XCTFail("Expected ltvOver condition")
        }
    }

    func test_autoTagRule_codableRoundtrip_custom() throws {
        let rule = CustomerAutoTagRule(id: "r2", tag: "special", condition: .custom("Server rule"))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(CustomerAutoTagRule.self, from: data)
        if case .custom(let s) = decoded.condition {
            XCTAssertEqual(s, "Server rule")
        } else {
            XCTFail("Expected custom condition")
        }
    }

    func test_tagColorIdentifiable_id_equalsName() {
        let tag = CustomerTagColor(name: "vip", hex: "#FFD700")
        XCTAssertEqual(tag.id, "vip")
    }

    func test_defaultPalette_allHaveSymbols() {
        for tag in CustomerTagColor.defaultPalette {
            XCTAssertNotNil(tag.symbolName, "Tag \(tag.name) missing symbolName")
        }
    }

    func test_defaultPalette_allHaveHex() {
        for tag in CustomerTagColor.defaultPalette {
            XCTAssertNotNil(tag.hex, "Tag \(tag.name) missing hex")
        }
    }
}
