import XCTest
@testable import Search

/// §22 — Unit tests for `SearchScope` and `SearchScopeCounts`.
final class SearchScopeTests: XCTestCase {

    // MARK: - SearchScope.allCases

    func test_allCases_containsSixScopes() {
        XCTAssertEqual(SearchScope.allCases.count, 6)
    }

    func test_allCases_includesExpectedMembers() {
        let expected: Set<SearchScope> = [.all, .customers, .tickets, .inventory, .invoices, .notes]
        XCTAssertEqual(Set(SearchScope.allCases), expected)
    }

    // MARK: - displayName

    func test_displayName_all() {
        XCTAssertEqual(SearchScope.all.displayName, "All")
    }

    func test_displayName_customers() {
        XCTAssertEqual(SearchScope.customers.displayName, "Customers")
    }

    func test_displayName_tickets() {
        XCTAssertEqual(SearchScope.tickets.displayName, "Tickets")
    }

    func test_displayName_inventory() {
        XCTAssertEqual(SearchScope.inventory.displayName, "Inventory")
    }

    func test_displayName_invoices() {
        XCTAssertEqual(SearchScope.invoices.displayName, "Invoices")
    }

    func test_displayName_notes() {
        XCTAssertEqual(SearchScope.notes.displayName, "Notes")
    }

    // MARK: - systemImage

    func test_systemImage_allIsSearchIcon() {
        XCTAssertEqual(SearchScope.all.systemImage, "magnifyingglass")
    }

    func test_systemImage_nonEmpty() {
        for scope in SearchScope.allCases {
            XCTAssertFalse(scope.systemImage.isEmpty, "\(scope) must have a system image")
        }
    }

    // MARK: - shortcutDigit

    func test_shortcutDigit_allIsNil() {
        XCTAssertNil(SearchScope.all.shortcutDigit)
    }

    func test_shortcutDigit_customersIs1() {
        XCTAssertEqual(SearchScope.customers.shortcutDigit, 1)
    }

    func test_shortcutDigit_ticketsIs2() {
        XCTAssertEqual(SearchScope.tickets.shortcutDigit, 2)
    }

    func test_shortcutDigit_inventoryIs3() {
        XCTAssertEqual(SearchScope.inventory.shortcutDigit, 3)
    }

    func test_shortcutDigit_invoicesIs4() {
        XCTAssertEqual(SearchScope.invoices.shortcutDigit, 4)
    }

    func test_shortcutDigit_notesIs5() {
        XCTAssertEqual(SearchScope.notes.shortcutDigit, 5)
    }

    func test_shortcutDigits_areUnique() {
        let digits = SearchScope.allCases.compactMap { $0.shortcutDigit }
        XCTAssertEqual(digits.count, Set(digits).count, "Shortcut digits must be unique")
    }

    // MARK: - entityFilter

    func test_entityFilter_allIsNil() {
        XCTAssertNil(SearchScope.all.entityFilter)
    }

    func test_entityFilter_customersIsMapped() {
        XCTAssertEqual(SearchScope.customers.entityFilter, .customers)
    }

    func test_entityFilter_ticketsIsMapped() {
        XCTAssertEqual(SearchScope.tickets.entityFilter, .tickets)
    }

    func test_entityFilter_inventoryIsMapped() {
        XCTAssertEqual(SearchScope.inventory.entityFilter, .inventory)
    }

    func test_entityFilter_invoicesIsMapped() {
        XCTAssertEqual(SearchScope.invoices.entityFilter, .invoices)
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip() throws {
        for scope in SearchScope.allCases {
            let data = try JSONEncoder().encode(scope)
            let decoded = try JSONDecoder().decode(SearchScope.self, from: data)
            XCTAssertEqual(decoded, scope, "\(scope) should survive codable round-trip")
        }
    }

    // MARK: - Hashable

    func test_hashable_equalScopesHaveEqualHash() {
        XCTAssertEqual(SearchScope.customers.hashValue, SearchScope.customers.hashValue)
    }
}
