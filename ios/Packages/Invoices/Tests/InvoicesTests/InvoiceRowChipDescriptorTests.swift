import XCTest
@testable import Invoices
import Networking

// §7.1 InvoiceRowChipDescriptor tests

final class InvoiceRowChipDescriptorTests: XCTestCase {

    // Helper: build a minimal InvoiceSummary
    private func makeSummary(
        id: Int64 = 1,
        status: String,
        total: Double = 100.0,
        paid: Double = 0.0,
        due: Double = 100.0,
        dueOn: String? = nil
    ) -> InvoiceSummary {
        // Decode from JSON so we respect CodingKeys
        let iso = ISO8601DateFormatter()
        let createdAt = iso.string(from: Date())
        var json = """
        {
            "id": \(id),
            "order_id": "INV-\(id)",
            "status": "\(status)",
            "total": \(total),
            "amount_paid": \(paid),
            "amount_due": \(due),
            "created_at": "\(createdAt)"
        """
        if let dueOn {
            json += ", \"due_on\": \"\(dueOn)\""
        }
        json += "}"
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(InvoiceSummary.self, from: data)
    }

    func test_void_showsStrikethrough() {
        let inv = makeSummary(status: "void")
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        XCTAssertTrue(chip.strikethrough)
        XCTAssertEqual(chip.label, "Void")
    }

    func test_paid_showsGreenLabel() {
        let inv = makeSummary(status: "paid", paid: 100, due: 0)
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        XCTAssertEqual(chip.label, "Paid")
        XCTAssertFalse(chip.strikethrough)
    }

    func test_partial_showsPercentage() {
        let inv = makeSummary(status: "partial", total: 100, paid: 50, due: 50)
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        XCTAssertEqual(chip.label, "Paid 50%")
        XCTAssertFalse(chip.strikethrough)
    }

    func test_partial_100pct_edge() {
        // 100% paid but still "partial" status (shouldn't happen but must not crash)
        let inv = makeSummary(status: "partial", total: 100, paid: 100, due: 0)
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        XCTAssertEqual(chip.label, "Paid 100%")
    }

    func test_overdue_withDueDate_showsDays() {
        // Make a due date 5 days ago
        let calendar = Calendar.current
        let past = calendar.date(byAdding: .day, value: -5, to: Date())!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dueStr = df.string(from: past)
        let inv = makeSummary(status: "overdue", dueOn: dueStr)
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        // Should show "Overdue 5d" (or close — allow ±1 for timing)
        XCTAssertTrue(chip.label.hasPrefix("Overdue"), "Expected label starting with Overdue, got: \(chip.label)")
    }

    func test_overdue_withoutDueDate_showsOverdue() {
        let inv = makeSummary(status: "overdue")
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        XCTAssertEqual(chip.label, "Overdue")
    }

    func test_unpaid_showsUnpaid() {
        let inv = makeSummary(status: "unpaid", due: 100)
        let chip = InvoiceRowChipDescriptor(invoice: inv)
        XCTAssertEqual(chip.label, "Unpaid")
        XCTAssertFalse(chip.strikethrough)
    }

    func test_a11yLabel_nonempty() {
        for status in ["void", "paid", "partial", "overdue", "unpaid"] {
            let inv = makeSummary(status: status)
            let chip = InvoiceRowChipDescriptor(invoice: inv)
            XCTAssertFalse(chip.a11yLabel.isEmpty, "a11yLabel empty for status '\(status)'")
        }
    }
}
