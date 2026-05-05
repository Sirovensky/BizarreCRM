import XCTest
@testable import Customers
@testable import Networking

// MARK: - CustomersThreeColumnViewModelTests
//
// Tests covering the filtering logic that `CustomersThreeColumnView` applies
// via `CustomerFilter.matches(_:)` on top of `CustomerListViewModel`.
// We test the composition: given a set of CustomerSummary values and an
// active filter, does the in-memory filter produce the correct subset?

final class CustomersThreeColumnViewModelTests: XCTestCase {

    // MARK: - Filter composition

    func test_filteredList_allFilterReturnsAllCustomers() {
        let customers = makeCustomers(count: 5)
        let result = customers.filter { CustomerFilter.all.matches($0) }
        XCTAssertEqual(result.count, 5)
    }

    func test_filteredList_vipFilterReturnsOnlyHighTicketCustomers() {
        let customers = [
            makeCustomer(id: 1, ticketCount: 0),
            makeCustomer(id: 2, ticketCount: 3),
            makeCustomer(id: 3, ticketCount: 5),
            makeCustomer(id: 4, ticketCount: 7),
        ]
        let vip = customers.filter { CustomerFilter.vip.matches($0) }
        XCTAssertEqual(vip.map(\.id).sorted(), [3, 4])
    }

    func test_filteredList_atRiskFilterReturnsNoContactNoTickets() {
        let customers = [
            makeCustomer(id: 1, email: nil, mobile: nil, ticketCount: 0),
            makeCustomer(id: 2, email: "x@example.com", ticketCount: 0),
            makeCustomer(id: 3, email: nil, mobile: nil, ticketCount: 2),
        ]
        let atRisk = customers.filter { CustomerFilter.atRisk.matches($0) }
        XCTAssertEqual(atRisk.map(\.id), [1])
    }

    func test_filteredList_searchTextNarrowsResult() {
        let customers = [
            makeCustomer(id: 1, firstName: "Alice"),
            makeCustomer(id: 2, firstName: "Bob"),
            makeCustomer(id: 3, firstName: "Alice", lastName: "B"),
        ]
        let q = "alice"
        let result = customers.filter {
            $0.displayName.lowercased().contains(q)
        }
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.map(\.id).contains(1))
        XCTAssertTrue(result.map(\.id).contains(3))
    }

    func test_filteredList_searchByEmail() {
        let customers = [
            makeCustomer(id: 1, email: "alice@example.com"),
            makeCustomer(id: 2, email: "bob@example.com"),
        ]
        let q = "alice"
        let result = customers.filter { $0.email?.lowercased().contains(q) == true }
        XCTAssertEqual(result.map(\.id), [1])
    }

    func test_filteredList_searchByPhone() {
        let customers = [
            makeCustomer(id: 1, phone: "555-1234"),
            makeCustomer(id: 2, phone: "555-9999"),
        ]
        let q = "1234"
        let result = customers.filter { $0.phone?.contains(q) == true }
        XCTAssertEqual(result.map(\.id), [1])
    }

    func test_filteredList_emptyQueryReturnsAllCustomers() {
        let customers = makeCustomers(count: 4)
        let q = ""
        let result = q.isEmpty ? customers : customers.filter { $0.displayName.contains(q) }
        XCTAssertEqual(result.count, 4)
    }

    // MARK: - Filter applied after vip

    func test_vipAndSearchCombined() {
        let customers = [
            makeCustomer(id: 1, firstName: "Alice", ticketCount: 5),
            makeCustomer(id: 2, firstName: "Bob", ticketCount: 5),
            makeCustomer(id: 3, firstName: "Alice", ticketCount: 1),
        ]
        let filtered = customers.filter { CustomerFilter.vip.matches($0) }
        let q = "alice"
        let result = filtered.filter { $0.displayName.lowercased().contains(q) }
        XCTAssertEqual(result.map(\.id), [1])
    }

    // MARK: - Helpers

    private func makeCustomers(count: Int) -> [CustomerSummary] {
        (1...count).map { makeCustomer(id: Int64($0), firstName: "User\($0)") }
    }

    private func makeCustomer(
        id: Int64 = 1,
        firstName: String? = "Test",
        lastName: String? = "User",
        email: String? = "test@example.com",
        phone: String? = nil,
        mobile: String? = "555-0000",
        organization: String? = nil,
        ticketCount: Int? = nil,
        createdAt: String? = nil
    ) -> CustomerSummary {
        var parts: [String] = ["\"id\": \(id)"]
        if let v = firstName    { parts.append("\"first_name\": \"\(v)\"") }
        if let v = lastName     { parts.append("\"last_name\": \"\(v)\"") }
        if let v = email        { parts.append("\"email\": \"\(v)\"") }
        if let v = phone        { parts.append("\"phone\": \"\(v)\"") }
        if let v = mobile       { parts.append("\"mobile\": \"\(v)\"") }
        if let v = organization { parts.append("\"organization\": \"\(v)\"") }
        if let v = ticketCount  { parts.append("\"ticket_count\": \(v)") }
        if let v = createdAt    { parts.append("\"created_at\": \"\(v)\"") }
        let json = ("{ " + parts.joined(separator: ", ") + " }").data(using: .utf8)!
        return try! JSONDecoder().decode(CustomerSummary.self, from: json)
    }
}
