import XCTest
@testable import Invoices
import Networking

// §7.1 InvoiceCSVExporter tests

final class InvoiceCSVExporterTests: XCTestCase {

    private func makeSummary(id: Int64, status: String, total: Double, customerName: String) -> InvoiceSummary {
        let json = """
        {
            "id": \(id),
            "order_id": "INV-\(id)",
            "first_name": "\(customerName)",
            "last_name": "",
            "status": "\(status)",
            "total": \(total),
            "amount_paid": 0,
            "amount_due": \(total),
            "created_at": "2026-04-01"
        }
        """
        return try! JSONDecoder().decode(InvoiceSummary.self, from: json.data(using: .utf8)!)
    }

    func test_csv_producesHeader() {
        let csv = InvoiceCSVExporter.csv(from: [])
        let text = String(data: csv, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("ID,Customer,Total,Paid,Due,Status,Issued,DueOn"))
    }

    func test_csv_oneRow_correct() {
        let inv = makeSummary(id: 1, status: "paid", total: 100.0, customerName: "Alice Smith")
        let csv = InvoiceCSVExporter.csv(from: [inv])
        let text = String(data: csv, encoding: .utf8)!
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("INV-1"))
        XCTAssertTrue(lines[1].contains("100.00"))
        XCTAssertTrue(lines[1].contains("paid"))
    }

    func test_csv_specialCharsEscaped() {
        // Customer name with comma
        let json = """
        {
            "id": 2,
            "order_id": "INV-2",
            "first_name": "Smith, Jr.",
            "last_name": "",
            "status": "unpaid",
            "total": 50.0,
            "amount_paid": 0,
            "amount_due": 50.0,
            "created_at": "2026-04-01"
        }
        """
        let inv = try! JSONDecoder().decode(InvoiceSummary.self, from: json.data(using: .utf8)!)
        let csv = InvoiceCSVExporter.csv(from: [inv])
        let text = String(data: csv, encoding: .utf8)!
        // The name should be quoted
        XCTAssertTrue(text.contains("\"Smith, Jr.\""))
    }

    func test_csv_emptyList_onlyHeader() {
        let csv = InvoiceCSVExporter.csv(from: [])
        let text = String(data: csv, encoding: .utf8)!
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(text.components(separatedBy: "\n").count, 1)
    }

    func test_csv_multipleRows() {
        let invoices = (1...5).map { i in
            makeSummary(id: Int64(i), status: "paid", total: Double(i) * 10, customerName: "Customer\(i)")
        }
        let csv = InvoiceCSVExporter.csv(from: invoices)
        let text = String(data: csv, encoding: .utf8)!
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6) // header + 5 rows
    }
}
