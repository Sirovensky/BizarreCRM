import XCTest
@testable import Inventory

// MARK: - POStatusTests
//
// Tests for POStatus domain logic: displayName, isOpen, canApprove.
// These cover the server's ENR-INV6 status workflow.

final class POStatusTests: XCTestCase {

    // MARK: displayName

    func test_displayName_allCases_neverEmpty() {
        for status in POStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, "displayName empty for \(status.rawValue)")
        }
    }

    func test_displayName_draft_returnsDraft() {
        XCTAssertEqual(POStatus.draft.displayName, "Draft")
    }

    func test_displayName_pending_returnsPending() {
        XCTAssertEqual(POStatus.pending.displayName, "Pending")
    }

    func test_displayName_ordered_returnsOrdered() {
        XCTAssertEqual(POStatus.ordered.displayName, "Ordered")
    }

    func test_displayName_backordered_returnsBackordered() {
        XCTAssertEqual(POStatus.backordered.displayName, "Backordered")
    }

    func test_displayName_partial_returnsPartial() {
        XCTAssertEqual(POStatus.partial.displayName, "Partial")
    }

    func test_displayName_received_returnsReceived() {
        XCTAssertEqual(POStatus.received.displayName, "Received")
    }

    func test_displayName_cancelled_returnsCancelled() {
        XCTAssertEqual(POStatus.cancelled.displayName, "Cancelled")
    }

    // MARK: isOpen

    func test_isOpen_draft_returnsTrue() {
        XCTAssertTrue(POStatus.draft.isOpen)
    }

    func test_isOpen_pending_returnsTrue() {
        XCTAssertTrue(POStatus.pending.isOpen)
    }

    func test_isOpen_ordered_returnsTrue() {
        XCTAssertTrue(POStatus.ordered.isOpen)
    }

    func test_isOpen_backordered_returnsTrue() {
        XCTAssertTrue(POStatus.backordered.isOpen)
    }

    func test_isOpen_partial_returnsTrue() {
        XCTAssertTrue(POStatus.partial.isOpen)
    }

    func test_isOpen_received_returnsFalse() {
        XCTAssertFalse(POStatus.received.isOpen)
    }

    func test_isOpen_cancelled_returnsFalse() {
        XCTAssertFalse(POStatus.cancelled.isOpen)
    }

    // MARK: canApprove

    func test_canApprove_draft_returnsTrue() {
        XCTAssertTrue(POStatus.draft.canApprove)
    }

    func test_canApprove_pending_returnsFalse() {
        XCTAssertFalse(POStatus.pending.canApprove)
    }

    func test_canApprove_ordered_returnsFalse() {
        XCTAssertFalse(POStatus.ordered.canApprove)
    }

    func test_canApprove_backordered_returnsFalse() {
        XCTAssertFalse(POStatus.backordered.canApprove)
    }

    func test_canApprove_partial_returnsFalse() {
        XCTAssertFalse(POStatus.partial.canApprove)
    }

    func test_canApprove_received_returnsFalse() {
        XCTAssertFalse(POStatus.received.canApprove)
    }

    func test_canApprove_cancelled_returnsFalse() {
        XCTAssertFalse(POStatus.cancelled.canApprove)
    }

    // MARK: rawValue round-trip (Codable)

    func test_rawValues_matchServerContract() {
        // Server ENR-INV6 specifies these exact strings
        XCTAssertEqual(POStatus.draft.rawValue,       "draft")
        XCTAssertEqual(POStatus.pending.rawValue,     "pending")
        XCTAssertEqual(POStatus.ordered.rawValue,     "ordered")
        XCTAssertEqual(POStatus.backordered.rawValue, "backordered")
        XCTAssertEqual(POStatus.partial.rawValue,     "partial")
        XCTAssertEqual(POStatus.received.rawValue,    "received")
        XCTAssertEqual(POStatus.cancelled.rawValue,   "cancelled")
    }

    func test_decodeFromRawValue_allCases() throws {
        for status in POStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(POStatus.self, from: encoded)
            XCTAssertEqual(decoded, status)
        }
    }
}
