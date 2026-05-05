import XCTest
@testable import Dashboard
import Networking

// MARK: - §3.6 Activity Feed tests

final class ActivityFeedTests: XCTestCase {

    // MARK: - ActivityEvent decoding

    func test_activityEvent_decoding() throws {
        let json = """
        {
            "id": 42,
            "entityType": "ticket",
            "entityId": 7,
            "title": "Ticket #T-42 updated",
            "subtitle": "Status changed to In Progress",
            "actorName": "Alice",
            "occurredAt": "2026-04-25T14:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(ActivityEvent.self, from: json)

        XCTAssertEqual(event.id, 42)
        XCTAssertEqual(event.entityType, "ticket")
        XCTAssertEqual(event.entityId, 7)
        XCTAssertEqual(event.title, "Ticket #T-42 updated")
        XCTAssertEqual(event.subtitle, "Status changed to In Progress")
        XCTAssertEqual(event.actorName, "Alice")
        XCTAssertEqual(event.occurredAt, "2026-04-25T14:30:00Z")
    }

    func test_activityEvent_decoding_withNilOptionals() throws {
        let json = """
        {
            "id": 1,
            "entityType": "payment",
            "title": "Payment received",
            "occurredAt": "2026-04-25T09:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(ActivityEvent.self, from: json)

        XCTAssertNil(event.entityId)
        XCTAssertNil(event.subtitle)
        XCTAssertNil(event.actorName)
    }

    func test_activityEvent_identifiable() {
        let e1 = ActivityEvent(id: 1, entityType: "ticket", title: "A", occurredAt: "2026-01-01T00:00:00Z")
        let e2 = ActivityEvent(id: 2, entityType: "sms",    title: "B", occurredAt: "2026-01-01T00:00:00Z")
        XCTAssertNotEqual(e1.id, e2.id)
    }

    // MARK: - ActivityFeedViewModel state machine

    @MainActor
    func test_activityFeedViewModel_initialState_isIdle() {
        let vm = ActivityFeedViewModel(api: makeMockAPI())
        if case .idle = vm.state { /* pass */ }
        else { XCTFail("Expected .idle, got \(vm.state)") }
    }

    // MARK: - Helper

    private func makeMockAPI() -> APIClient {
        APIClient()
    }
}
