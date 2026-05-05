import XCTest
@testable import Core

// §64 — Tests for SuccessCopy catalog completeness and content quality.

final class SuccessCopyTests: XCTestCase {

    // MARK: — Catalog completeness

    func testAllEventsHaveNonEmptyMessageAndSymbol() {
        for event in SuccessCopy.Event.allCases {
            let copy = SuccessCopy.copy(for: event)
            XCTAssertFalse(copy.message.isEmpty,    "message must not be empty for \(event)")
            XCTAssertFalse(copy.symbolName.isEmpty, "symbolName must not be empty for \(event)")
        }
    }

    // MARK: — Messages end with a period

    func testAllMessagesEndWithPeriod() {
        for event in SuccessCopy.Event.allCases {
            let message = SuccessCopy.copy(for: event).message
            XCTAssertTrue(message.hasSuffix("."),
                "message for \(event) must end with a period; got: \"\(message)\"")
        }
    }

    // MARK: — Messages are brief (suitable for a transient banner)

    func testAllMessagesAreShort() {
        for event in SuccessCopy.Event.allCases {
            let message = SuccessCopy.copy(for: event).message
            XCTAssertLessThanOrEqual(message.count, 60,
                "message for \(event) should be <= 60 chars for a banner; got \(message.count): \"\(message)\"")
        }
    }

    // MARK: — Specific spot checks

    func testInvoiceSent_messageContainsSent() {
        let copy = SuccessCopy.copy(for: .invoiceSent)
        XCTAssertTrue(copy.message.lowercased().contains("sent"))
    }

    func testCustomerSaved_messageContainsSaved() {
        let copy = SuccessCopy.copy(for: .customerSaved)
        XCTAssertTrue(copy.message.lowercased().contains("saved"))
    }

    func testInvoicePaid_messageContainsPayment() {
        let copy = SuccessCopy.copy(for: .invoicePaid)
        XCTAssertTrue(copy.message.lowercased().contains("payment"))
    }

    func testSyncComplete_messageContainsSync() {
        let copy = SuccessCopy.copy(for: .syncComplete)
        XCTAssertTrue(copy.message.lowercased().contains("sync"))
    }

    // MARK: — Symbol names are non-empty SF Symbol identifiers

    func testAllSymbolNamesLookLikeSystemSymbols() {
        for event in SuccessCopy.Event.allCases {
            let symbol = SuccessCopy.copy(for: event).symbolName
            // SF Symbol names are lowercase dot-separated identifiers
            XCTAssertFalse(symbol.isEmpty, "symbolName for \(event) must not be empty")
            XCTAssertTrue(symbol == symbol.lowercased(),
                "symbolName for \(event) should be lowercase SF Symbol identifier; got: \"\(symbol)\"")
        }
    }

    // MARK: — Tone compliance

    func testAllCopiesPassToneGuidelines() {
        for event in SuccessCopy.Event.allCases {
            let copy = SuccessCopy.copy(for: event)
            let violations = ToneGuidelines.violations(in: copy.message)
            XCTAssertTrue(violations.isEmpty,
                "message for \(event) has tone violations: \(violations) — \"\(copy.message)\"")
        }
    }
}
