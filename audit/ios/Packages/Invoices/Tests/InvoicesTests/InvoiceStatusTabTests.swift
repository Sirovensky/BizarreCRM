import XCTest
@testable import Invoices
import Networking

// §7.1 InvoiceStatusTab tests

final class InvoiceStatusTabTests: XCTestCase {

    func test_allCases_count_is6() {
        XCTAssertEqual(InvoiceStatusTab.allCases.count, 6)
    }

    func test_all_maps_to_legacyFilter_all() {
        XCTAssertEqual(InvoiceStatusTab.all.legacyFilter, .all)
    }

    func test_paid_maps_to_legacyFilter_paid() {
        XCTAssertEqual(InvoiceStatusTab.paid.legacyFilter, .paid)
    }

    func test_unpaid_maps_to_legacyFilter_unpaid() {
        XCTAssertEqual(InvoiceStatusTab.unpaid.legacyFilter, .unpaid)
    }

    func test_partial_maps_to_legacyFilter_partial() {
        XCTAssertEqual(InvoiceStatusTab.partial.legacyFilter, .partial)
    }

    func test_overdue_maps_to_legacyFilter_overdue() {
        XCTAssertEqual(InvoiceStatusTab.overdue.legacyFilter, .overdue)
    }

    func test_void_maps_to_serverStatus_void() {
        XCTAssertEqual(InvoiceStatusTab.void_.serverStatus, "void")
    }

    func test_all_serverStatus_is_nil() {
        XCTAssertNil(InvoiceStatusTab.all.serverStatus)
    }

    func test_displayNames_are_nonempty() {
        for tab in InvoiceStatusTab.allCases {
            XCTAssertFalse(tab.displayName.isEmpty, "displayName is empty for \(tab)")
        }
    }

    func test_ids_are_unique() {
        let ids = InvoiceStatusTab.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}

// §7.1 InvoiceSortOption tests

final class InvoiceSortOptionTests: XCTestCase {

    func test_allCases_count_is7() {
        XCTAssertEqual(InvoiceSortOption.allCases.count, 7)
    }

    func test_dateDesc_queryItems() {
        let items = InvoiceSortOption.dateDesc.queryItems
        XCTAssertEqual(items.first?.name, "sort")
        XCTAssertEqual(items.first?.value, "date_desc")
    }

    func test_displayNames_are_nonempty() {
        for opt in InvoiceSortOption.allCases {
            XCTAssertFalse(opt.displayName.isEmpty, "displayName empty for \(opt)")
        }
    }

    func test_ids_are_unique() {
        let ids = InvoiceSortOption.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
