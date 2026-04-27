#if canImport(UIKit)
import XCTest
@testable import Customers
import Networking

// MARK: - §5.6 CustomerCSVExporter tests

final class CustomerCSVExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeCustomer(
        id: Int64,
        firstName: String?,
        lastName: String?,
        email: String? = nil,
        phone: String? = nil,
        organization: String? = nil,
        city: String? = nil,
        state: String? = nil,
        ticketCount: Int? = nil
    ) throws -> CustomerSummary {
        var dict: [String: Any] = ["id": id]
        if let v = firstName { dict["first_name"] = v }
        if let v = lastName { dict["last_name"] = v }
        if let v = email { dict["email"] = v }
        if let v = phone { dict["phone"] = v }
        if let v = organization { dict["organization"] = v }
        if let v = city { dict["city"] = v }
        if let v = state { dict["state"] = v }
        if let v = ticketCount { dict["ticket_count"] = v }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(CustomerSummary.self, from: data)
    }

    // MARK: - Basic export

    func test_export_emptyList_returnsNonNilURL() throws {
        let url = CustomerCSVExporter.export([])
        XCTAssertNotNil(url)
    }

    func test_export_emptyList_hasOnlyHeader() throws {
        guard let url = CustomerCSVExporter.export([]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("ID,Name,Email,Phone,Organization,City,State,Tickets"))
        // Header line only — trim trailing newline and check single line
        let lines = contents.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1)
    }

    func test_export_oneCustomer_hasHeaderPlusOneRow() throws {
        let c = try makeCustomer(id: 1, firstName: "Ada", lastName: "Lovelace", email: "ada@example.com")
        guard let url = CustomerCSVExporter.export([c]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("Ada Lovelace"))
        XCTAssertTrue(lines[1].contains("ada@example.com"))
    }

    func test_export_rowContainsIdFirst() throws {
        let c = try makeCustomer(id: 42, firstName: "Grace", lastName: "Hopper")
        guard let url = CustomerCSVExporter.export([c]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let dataLine = contents.trimmingCharacters(in: .newlines).components(separatedBy: "\n")[1]
        XCTAssertTrue(dataLine.hasPrefix("42,"))
    }

    // MARK: - RFC-4180 escaping

    func test_export_commaInField_quotesField() throws {
        let c = try makeCustomer(id: 1, firstName: "Smith", lastName: nil, organization: "Acme, Inc")
        guard let url = CustomerCSVExporter.export([c]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"Acme, Inc\""),
                      "Field with comma should be quoted. Got:\n\(contents)")
    }

    func test_export_quoteInField_doubleQuotes() throws {
        let c = try makeCustomer(id: 1, firstName: "O\"Brien", lastName: nil)
        guard let url = CustomerCSVExporter.export([c]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        // The name contains a quote, so both the containing quotes and the escaped
        // inner quote must appear
        XCTAssertTrue(contents.contains("\"\""),
                      "Embedded quote should be escaped to double-quote. Got:\n\(contents)")
    }

    // MARK: - Ticket count

    func test_export_ticketCount_appearsInRow() throws {
        let c = try makeCustomer(id: 5, firstName: "Test", lastName: nil, ticketCount: 7)
        guard let url = CustomerCSVExporter.export([c]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains(",7") || contents.contains(",7\n"),
                      "Ticket count 7 should appear in row. Got:\n\(contents)")
    }

    func test_export_noTicketCount_hasEmptyColumn() throws {
        let c = try makeCustomer(id: 6, firstName: "Test", lastName: nil, ticketCount: nil)
        guard let url = CustomerCSVExporter.export([c]) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let dataLine = contents.trimmingCharacters(in: .newlines).components(separatedBy: "\n")[1]
        // Last column is empty — line ends with comma (empty field) or just ends
        XCTAssertTrue(dataLine.hasSuffix(","), "Missing ticket count should produce trailing comma. Got: \(dataLine)")
    }

    // MARK: - Multi-row

    func test_export_multipleCustomers_correctLineCount() throws {
        let customers = try (1...5).map { i in
            try makeCustomer(id: Int64(i), firstName: "Customer\(i)", lastName: nil)
        }
        guard let url = CustomerCSVExporter.export(customers) else {
            return XCTFail("Expected non-nil URL")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 6, "5 customers + 1 header = 6 lines")
    }

    // MARK: - File persistence

    func test_export_returnsCSVExtensionURL() throws {
        guard let url = CustomerCSVExporter.export([]) else {
            return XCTFail("Expected non-nil URL")
        }
        XCTAssertEqual(url.pathExtension, "csv")
    }

    func test_export_fileExistsAtReturnedURL() throws {
        guard let url = CustomerCSVExporter.export([]) else {
            return XCTFail("Expected non-nil URL")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
#endif
