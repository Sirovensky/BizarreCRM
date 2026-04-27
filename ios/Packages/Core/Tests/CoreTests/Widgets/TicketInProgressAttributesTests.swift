import XCTest
@testable import Core

// MARK: - §24.3 TicketInProgressAttributes tests

final class TicketInProgressAttributesTests: XCTestCase {

    func test_attributes_init() {
        let attrs = TicketInProgressAttributes(
            ticketId: 42,
            orderId: "T-042",
            customerName: "Alice",
            service: "Screen replacement"
        )
        XCTAssertEqual(attrs.ticketId, 42)
        XCTAssertEqual(attrs.orderId, "T-042")
        XCTAssertEqual(attrs.customerName, "Alice")
        XCTAssertEqual(attrs.service, "Screen replacement")
    }

    func test_attributes_nilOptionals() {
        let attrs = TicketInProgressAttributes(
            ticketId: 1,
            orderId: "T-001",
            customerName: nil,
            service: nil
        )
        XCTAssertNil(attrs.customerName)
        XCTAssertNil(attrs.service)
    }

    func test_contentState_init() {
        let state = TicketInProgressAttributes.ContentState(elapsedMinutes: 90)
        XCTAssertEqual(state.elapsedMinutes, 90)
    }

    func test_contentState_codable_roundTrip() throws {
        let state = TicketInProgressAttributes.ContentState(elapsedMinutes: 125)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TicketInProgressAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded.elapsedMinutes, 125)
    }

    func test_contentState_hashable() {
        let a = TicketInProgressAttributes.ContentState(elapsedMinutes: 10)
        let b = TicketInProgressAttributes.ContentState(elapsedMinutes: 10)
        let c = TicketInProgressAttributes.ContentState(elapsedMinutes: 20)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
