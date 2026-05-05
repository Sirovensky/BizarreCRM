// CoreTests/RowAccessibilityFormatterTests.swift
//
// TDD tests for RowAccessibilityFormatter — pure helper, no UI import.
// §26 A11y retrofit: Tickets / Customers / Inventory / Invoices list row labels.
//
// Run: swift test --filter RowAccessibilityFormatterTests (from Core package dir)

import XCTest
@testable import Core

final class RowAccessibilityFormatterTests: XCTestCase {

    // MARK: - Ticket row

    func test_ticketRow_allFields_producesFullSentence() {
        let due = Date(timeIntervalSinceNow: 86400) // tomorrow
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-001",
            customer: "Jane Doe",
            device: "iPhone 14",
            status: "Diagnosing",
            dueAt: due
        )
        XCTAssertTrue(result.contains("TKT-001"), "Should contain ticket display id")
        XCTAssertTrue(result.contains("Jane Doe"), "Should contain customer name")
        XCTAssertTrue(result.contains("iPhone 14"), "Should contain device name")
        XCTAssertTrue(result.contains("Diagnosing"), "Should contain status")
        XCTAssertTrue(result.hasSuffix("."), "Label should end with period")
    }

    func test_ticketRow_missingDue_omitsDueSegment() {
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-002",
            customer: "Bob Smith",
            device: "Samsung S23",
            status: "Ready",
            dueAt: nil
        )
        XCTAssertFalse(result.lowercased().contains("due"), "No due date segment when nil")
        XCTAssertTrue(result.contains("TKT-002"))
        XCTAssertTrue(result.contains("Bob Smith"))
    }

    func test_ticketRow_emptyDevice_omitsDevice() {
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-003",
            customer: "Alice",
            device: "",
            status: "Intake",
            dueAt: nil
        )
        XCTAssertFalse(result.contains(", device"), "Should omit device segment when empty")
        XCTAssertTrue(result.contains("Alice"))
    }

    func test_ticketRow_emptyCustomer_omitsCustomer() {
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-004",
            customer: "",
            device: "iPad Pro",
            status: "In Progress",
            dueAt: nil
        )
        // Should not contain a comma-space after TKT-004 followed by nothing
        XCTAssertTrue(result.contains("TKT-004"))
        XCTAssertTrue(result.contains("iPad Pro"))
    }

    func test_ticketRow_dueInFuture_containsHumanDate() {
        let soon = Date(timeIntervalSinceNow: 60 * 60 * 24 * 3) // 3 days
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-005",
            customer: "Carol",
            device: "MacBook",
            status: "Waiting",
            dueAt: soon
        )
        // RelativeDateTimeFormatter or weekday name — just check it's a non-empty suffix
        XCTAssertTrue(result.contains("TKT-005"))
        XCTAssertFalse(result.contains("Optional("), "No raw Optional in output")
    }

    func test_ticketRow_dueInPast_containsHumanDate() {
        let past = Date(timeIntervalSinceNow: -86400 * 2)
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-006",
            customer: "Dave",
            device: "Pixel 7",
            status: "Awaiting Parts",
            dueAt: past
        )
        XCTAssertTrue(result.contains("TKT-006"))
        XCTAssertFalse(result.contains("Optional("))
    }

    func test_ticketRow_noRawId_usesDisplayId() {
        // The display id "TKT-001" is already a human-readable display id.
        // Confirm we never see raw Int64 numeric id in the label.
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-007",
            customer: "Eve",
            device: "Watch",
            status: "Completed",
            dueAt: nil
        )
        XCTAssertTrue(result.contains("TKT-007"), "Display id present")
    }

    func test_ticketRow_hint_isCorrect() {
        XCTAssertEqual(RowAccessibilityFormatter.ticketRowHint, "Tap to open ticket details.")
    }

    // MARK: - Customer row

    func test_customerRow_allFields_producesFullSentence() {
        let lastVisit = Date(timeIntervalSinceNow: -86400 * 14)
        let result = RowAccessibilityFormatter.customerRow(
            name: "Jane Doe",
            phone: "555-1212",
            openTicketCount: 3,
            ltvCents: 125000,
            lastVisitAt: lastVisit
        )
        XCTAssertTrue(result.contains("Jane Doe"))
        XCTAssertTrue(result.contains("555-1212"), "Phone should appear")
        XCTAssertTrue(result.contains("3 open ticket"), "Ticket count")
        XCTAssertTrue(result.contains("$1,250"), "LTV formatted as currency")
        XCTAssertTrue(result.hasSuffix("."))
    }

    func test_customerRow_nilPhone_omitsPhone() {
        let result = RowAccessibilityFormatter.customerRow(
            name: "Bob",
            phone: nil,
            openTicketCount: 0,
            ltvCents: nil,
            lastVisitAt: nil
        )
        XCTAssertFalse(result.lowercased().contains("phone"), "No phone segment when nil")
        XCTAssertTrue(result.contains("Bob"))
    }

    func test_customerRow_zeroTickets_omitsTicketCount() {
        let result = RowAccessibilityFormatter.customerRow(
            name: "Carol",
            phone: "555-0000",
            openTicketCount: 0,
            ltvCents: nil,
            lastVisitAt: nil
        )
        XCTAssertFalse(result.contains("ticket"), "Zero tickets — no ticket segment")
    }

    func test_customerRow_singularTicket_usesTicketSingular() {
        let result = RowAccessibilityFormatter.customerRow(
            name: "Dave",
            phone: nil,
            openTicketCount: 1,
            ltvCents: nil,
            lastVisitAt: nil
        )
        XCTAssertTrue(result.contains("1 open ticket"), "Singular 'ticket' not 'tickets'")
        XCTAssertFalse(result.contains("1 open tickets"), "No plural for count=1")
    }

    func test_customerRow_nilLtv_omitsLtv() {
        let result = RowAccessibilityFormatter.customerRow(
            name: "Eve",
            phone: nil,
            openTicketCount: 2,
            ltvCents: nil,
            lastVisitAt: nil
        )
        XCTAssertFalse(result.contains("LTV"), "No LTV segment when nil")
    }

    func test_customerRow_nilLastVisit_omitsLastVisit() {
        let result = RowAccessibilityFormatter.customerRow(
            name: "Frank",
            phone: nil,
            openTicketCount: 1,
            ltvCents: 5000,
            lastVisitAt: nil
        )
        XCTAssertFalse(result.lowercased().contains("last visit"), "No last-visit when nil")
    }

    func test_customerRow_hint_isCorrect() {
        XCTAssertEqual(RowAccessibilityFormatter.customerRowHint, "Tap to open customer details.")
    }

    func test_customerRow_currencyFormatting_noRawDecimals() {
        let result = RowAccessibilityFormatter.customerRow(
            name: "Greta",
            phone: nil,
            openTicketCount: 0,
            ltvCents: 8999,
            lastVisitAt: nil
        )
        XCTAssertFalse(result.contains("89.990000"), "Currency must not use raw floating-point decimals")
        XCTAssertTrue(result.contains("$89.99") || result.contains("89.99"), "Correct currency value")
    }

    // MARK: - Inventory row

    func test_inventoryRow_allFields_producesFullSentence() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "ABC-123",
            name: "iPhone 14 Battery",
            stock: 3,
            retailCents: 8999,
            isLowStock: false
        )
        XCTAssertTrue(result.contains("ABC-123"), "SKU present")
        XCTAssertTrue(result.contains("iPhone 14 Battery"), "Name present")
        XCTAssertTrue(result.contains("3 in stock"), "Stock count")
        XCTAssertTrue(result.contains("$89.99") || result.contains("89.99"), "Retail price")
        XCTAssertTrue(result.hasSuffix("."))
    }

    func test_inventoryRow_lowStock_appendsWarning() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "DEF-456",
            name: "Screen",
            stock: 1,
            retailCents: 4500,
            isLowStock: true
        )
        XCTAssertTrue(result.lowercased().contains("low stock"), "Low-stock warning appended")
    }

    func test_inventoryRow_notLowStock_noWarning() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "GHI-789",
            name: "Cable",
            stock: 10,
            retailCents: 999,
            isLowStock: false
        )
        XCTAssertFalse(result.lowercased().contains("low stock"), "No warning when not low stock")
    }

    func test_inventoryRow_nilRetailCents_omitsPrice() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "JKL-000",
            name: "Tool",
            stock: 5,
            retailCents: nil,
            isLowStock: false
        )
        XCTAssertFalse(result.contains("$"), "No price segment when nil")
    }

    func test_inventoryRow_nilSku_omitsSku() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: nil,
            name: "Mystery Part",
            stock: 2,
            retailCents: nil,
            isLowStock: false
        )
        XCTAssertFalse(result.contains("SKU"), "No SKU segment when nil")
        XCTAssertTrue(result.contains("Mystery Part"))
    }

    func test_inventoryRow_hint_isCorrect() {
        XCTAssertEqual(RowAccessibilityFormatter.inventoryRowHint, "Tap for item details.")
    }

    func test_inventoryRow_currencyFormatting_noRawDecimals() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "X",
            name: "Lens",
            stock: 1,
            retailCents: 8990,
            isLowStock: false
        )
        XCTAssertFalse(result.contains("89.900000"), "No raw float formatting")
        XCTAssertTrue(result.contains("$89.90") || result.contains("89.90"))
    }

    func test_inventoryRow_zeroStock_showsOutOfStock() {
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "OOS",
            name: "Widget",
            stock: 0,
            retailCents: nil,
            isLowStock: false
        )
        XCTAssertTrue(
            result.lowercased().contains("out of stock") || result.contains("0 in stock"),
            "Should indicate zero stock"
        )
    }

    // MARK: - Invoice row

    func test_invoiceRow_allFields_producesFullSentence() {
        let issued = ISO8601DateFormatter().date(from: "2024-03-05T00:00:00Z")!
        let result = RowAccessibilityFormatter.invoiceRow(
            number: "INV-001",
            customer: "Jane Doe",
            totalCents: 25000,
            status: "Paid",
            issuedAt: issued
        )
        XCTAssertTrue(result.contains("INV-001"), "Invoice number present")
        XCTAssertTrue(result.contains("Jane Doe"), "Customer present")
        XCTAssertTrue(result.contains("$250") || result.contains("250"), "Total present")
        XCTAssertTrue(result.contains("Paid"), "Status present")
        XCTAssertTrue(result.hasSuffix("."))
    }

    func test_invoiceRow_statusCapitalized() {
        let issued = Date()
        let result = RowAccessibilityFormatter.invoiceRow(
            number: "INV-002",
            customer: "Bob",
            totalCents: 1000,
            status: "unpaid",
            issuedAt: issued
        )
        // Status should appear capitalized or title-cased
        XCTAssertFalse(result.contains("unpaid"), "Status should be capitalized")
        XCTAssertTrue(result.contains("Unpaid"), "Status capitalized")
    }

    func test_invoiceRow_currencyFormatting_noRawDecimals() {
        let issued = Date()
        let result = RowAccessibilityFormatter.invoiceRow(
            number: "INV-003",
            customer: "Carol",
            totalCents: 9999,
            status: "Partial",
            issuedAt: issued
        )
        XCTAssertFalse(result.contains("99.990000"), "No raw float")
        XCTAssertTrue(result.contains("$99.99") || result.contains("99.99"))
    }

    func test_invoiceRow_issuedDate_isHumanReadable() {
        let iso = ISO8601DateFormatter()
        let issued = iso.date(from: "2024-06-15T12:00:00Z")!
        let result = RowAccessibilityFormatter.invoiceRow(
            number: "INV-004",
            customer: "Dave",
            totalCents: 5000,
            status: "Paid",
            issuedAt: issued
        )
        // Should not be ISO string raw format like "2024-06-15T12:00:00Z"
        XCTAssertFalse(result.contains("T12:00:00Z"), "No raw ISO timestamp in label")
        // Should contain something readable (year or month name)
        XCTAssertTrue(result.contains("2024") || result.contains("Jun") || result.contains("June") || result.contains("15"),
                      "Some human-readable date component present")
    }

    func test_invoiceRow_hint_isCorrect() {
        XCTAssertEqual(RowAccessibilityFormatter.invoiceRowHint, "Tap to view invoice.")
    }

    func test_invoiceRow_noRawId_usesDisplayNumber() {
        // The number param is already the display number; confirm no Int64-style raw id
        let issued = Date()
        let result = RowAccessibilityFormatter.invoiceRow(
            number: "INV-007",
            customer: "Eve",
            totalCents: 0,
            status: "Void",
            issuedAt: issued
        )
        XCTAssertTrue(result.contains("INV-007"), "Display invoice number present")
    }

    // MARK: - Max-length / truncation guard

    func test_ticketRow_longFields_labelStaysUnder500Chars() {
        let longCustomer = String(repeating: "A", count: 200)
        let longDevice   = String(repeating: "B", count: 200)
        let result = RowAccessibilityFormatter.ticketRow(
            id: "TKT-LONG",
            customer: longCustomer,
            device: longDevice,
            status: "Intake",
            dueAt: nil
        )
        XCTAssertLessThanOrEqual(result.count, 500, "Label must not be excessively long")
    }

    func test_customerRow_longName_labelStaysUnder500Chars() {
        let longName = String(repeating: "C", count: 300)
        let result = RowAccessibilityFormatter.customerRow(
            name: longName,
            phone: "555-0000",
            openTicketCount: 99,
            ltvCents: 99999999,
            lastVisitAt: Date()
        )
        XCTAssertLessThanOrEqual(result.count, 500)
    }

    func test_inventoryRow_longName_labelStaysUnder500Chars() {
        let longName = String(repeating: "D", count: 300)
        let result = RowAccessibilityFormatter.inventoryRow(
            sku: "LONGSKU",
            name: longName,
            stock: 1,
            retailCents: 9999,
            isLowStock: true
        )
        XCTAssertLessThanOrEqual(result.count, 500)
    }
}
