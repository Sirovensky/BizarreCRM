import XCTest
@testable import Customers
@testable import Networking

// MARK: - CustomerFilterTests
//
// Unit tests for `CustomerFilter.matches(_:)` and filter enumeration.

final class CustomerFilterTests: XCTestCase {

    // MARK: - Helpers

    private func makeSummary(
        id: Int64 = 1,
        firstName: String? = "Alice",
        lastName: String? = "Smith",
        email: String? = "alice@example.com",
        phone: String? = nil,
        mobile: String? = "555-0100",
        organization: String? = nil,
        ticketCount: Int? = nil,
        createdAt: String? = nil
    ) -> CustomerSummary {
        var parts: [String] = ["\"id\": \(id)"]
        if let v = firstName  { parts.append("\"first_name\": \"\(v)\"") }
        if let v = lastName   { parts.append("\"last_name\": \"\(v)\"") }
        if let v = email      { parts.append("\"email\": \"\(v)\"") }
        if let v = phone      { parts.append("\"phone\": \"\(v)\"") }
        if let v = mobile     { parts.append("\"mobile\": \"\(v)\"") }
        if let v = organization { parts.append("\"organization\": \"\(v)\"") }
        if let v = ticketCount { parts.append("\"ticket_count\": \(v)") }
        if let v = createdAt  { parts.append("\"created_at\": \"\(v)\"") }
        let json = ("{ " + parts.joined(separator: ", ") + " }").data(using: .utf8)!
        return try! JSONDecoder().decode(CustomerSummary.self, from: json)
    }

    // MARK: - .all

    func test_all_matchesEveryCustomer() {
        let customers = [
            makeSummary(id: 1),
            makeSummary(id: 2, ticketCount: 10),
            makeSummary(id: 3, ticketCount: 0, mobile: nil, email: nil),
        ]
        for c in customers {
            XCTAssertTrue(CustomerFilter.all.matches(c), "All filter must match id=\(c.id)")
        }
    }

    // MARK: - .recent

    func test_recent_matchesCustomerCreatedWithinLast30Days() {
        let recentDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10 * 86_400))
        let c = makeSummary(createdAt: recentDate)
        XCTAssertTrue(CustomerFilter.recent.matches(c))
    }

    func test_recent_doesNotMatchCustomerCreatedOver30DaysAgo() {
        let oldDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-40 * 86_400))
        let c = makeSummary(createdAt: oldDate)
        XCTAssertFalse(CustomerFilter.recent.matches(c))
    }

    func test_recent_doesNotMatchCustomerWithNilCreatedAt() {
        let c = makeSummary(createdAt: nil)
        XCTAssertFalse(CustomerFilter.recent.matches(c))
    }

    func test_recent_matchesCustomerCreatedExactly30DaysAgo() {
        // 30 days should still count as recent (boundary inclusive)
        let borderDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86_400 + 60))
        let c = makeSummary(createdAt: borderDate)
        XCTAssertTrue(CustomerFilter.recent.matches(c))
    }

    // MARK: - .vip

    func test_vip_matchesCustomerWith5OrMoreTickets() {
        let c = makeSummary(ticketCount: 5)
        XCTAssertTrue(CustomerFilter.vip.matches(c))
    }

    func test_vip_matchesCustomerWith10Tickets() {
        let c = makeSummary(ticketCount: 10)
        XCTAssertTrue(CustomerFilter.vip.matches(c))
    }

    func test_vip_doesNotMatchCustomerWith4Tickets() {
        let c = makeSummary(ticketCount: 4)
        XCTAssertFalse(CustomerFilter.vip.matches(c))
    }

    func test_vip_doesNotMatchCustomerWithNilTicketCount() {
        let c = makeSummary(ticketCount: nil)
        XCTAssertFalse(CustomerFilter.vip.matches(c))
    }

    func test_vip_doesNotMatchCustomerWith0Tickets() {
        let c = makeSummary(ticketCount: 0)
        XCTAssertFalse(CustomerFilter.vip.matches(c))
    }

    // MARK: - .atRisk

    func test_atRisk_matchesCustomerWithZeroTicketsAndNoContactLine() {
        let c = makeSummary(email: nil, phone: nil, mobile: nil, organization: nil, ticketCount: 0)
        XCTAssertTrue(CustomerFilter.atRisk.matches(c))
    }

    func test_atRisk_doesNotMatchCustomerWithTickets() {
        let c = makeSummary(email: nil, phone: nil, mobile: nil, organization: nil, ticketCount: 2)
        XCTAssertFalse(CustomerFilter.atRisk.matches(c))
    }

    func test_atRisk_doesNotMatchCustomerWithContactLine() {
        // Has email so contactLine is non-nil
        let c = makeSummary(email: "test@example.com", ticketCount: 0)
        XCTAssertFalse(CustomerFilter.atRisk.matches(c))
    }

    // MARK: - Metadata

    func test_allCasesContainsExpectedFilters() {
        let expected: Set<CustomerFilter> = [.all, .recent, .vip, .atRisk]
        XCTAssertEqual(Set(CustomerFilter.allCases), expected)
    }

    func test_eachFilterHasSystemImage() {
        for filter in CustomerFilter.allCases {
            XCTAssertFalse(filter.systemImage.isEmpty, "\(filter) must have a systemImage")
        }
    }

    func test_eachFilterHasAccessibilityLabel() {
        for filter in CustomerFilter.allCases {
            XCTAssertFalse(filter.accessibilityLabel.isEmpty, "\(filter) must have an accessibilityLabel")
        }
    }

    func test_filterRawValuesMatchExpectedStrings() {
        XCTAssertEqual(CustomerFilter.all.rawValue, "All")
        XCTAssertEqual(CustomerFilter.recent.rawValue, "Recent")
        XCTAssertEqual(CustomerFilter.vip.rawValue, "VIP")
        XCTAssertEqual(CustomerFilter.atRisk.rawValue, "At Risk")
    }
}
