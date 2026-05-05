import XCTest
@testable import Core

// §64 — Tests for ErrorCopy catalog completeness and content quality.

final class ErrorCopyTests: XCTestCase {

    // MARK: — Catalog completeness

    /// Every CoreErrorState must produce a non-empty title and body.
    func testAllStatesProduceNonEmptyTitleAndBody() {
        let states: [CoreErrorState] = [
            .network,
            .server(status: 500, message: nil),
            .server(status: 503, message: "Unavailable"),
            .unauthorized,
            .forbidden,
            .notFound,
            .offline,
            .validation([]),
            .validation(["email", "phone"]),
            .rateLimited(retrySeconds: nil),
            .rateLimited(retrySeconds: 30),
            .unknown
        ]
        for state in states {
            let copy = ErrorCopy.copy(for: state)
            XCTAssertFalse(copy.title.isEmpty, "title must not be empty for \(state)")
            XCTAssertFalse(copy.body.isEmpty,  "body must not be empty for \(state)")
        }
    }

    // MARK: — Retryable states have a retryLabel

    func testRetryableStatesHaveRetryLabel() {
        let retryableStates: [CoreErrorState] = [
            .network,
            .server(status: 500, message: nil),
            .unauthorized,
            .offline,
            .rateLimited(retrySeconds: nil),
            .unknown
        ]
        for state in retryableStates {
            let copy = ErrorCopy.copy(for: state)
            XCTAssertNotNil(copy.retryLabel, "retryLabel should be present for \(state)")
            XCTAssertFalse(copy.retryLabel!.isEmpty, "retryLabel must not be empty for \(state)")
        }
    }

    // MARK: — Non-retryable states have no retryLabel

    func testNonRetryableStatesHaveNoRetryLabel() {
        let nonRetryableStates: [CoreErrorState] = [
            .forbidden,
            .notFound,
            .validation([])
        ]
        for state in nonRetryableStates {
            let copy = ErrorCopy.copy(for: state)
            XCTAssertNil(copy.retryLabel, "retryLabel should be nil for \(state)")
        }
    }

    // MARK: — Unauthorized uses Sign In label

    func testUnauthorized_retryLabelIsSignIn() {
        let copy = ErrorCopy.copy(for: .unauthorized)
        XCTAssertEqual(copy.retryLabel, "Sign In")
    }

    // MARK: — server() with a server message surfaces that message

    func testServer_withMessage_usesServerMessage() {
        let serverMsg = "Database unavailable"
        let copy = ErrorCopy.copy(for: .server(status: 503, message: serverMsg))
        XCTAssertEqual(copy.body, serverMsg)
    }

    func testServer_withoutMessage_fallsBackToGenericBody() {
        let copy = ErrorCopy.copy(for: .server(status: 500, message: nil))
        XCTAssertFalse(copy.body.isEmpty)
        // Must not contain raw HTTP status in the body (user-facing)
        XCTAssertFalse(copy.body.contains("500"))
    }

    // MARK: — validation() with fields surfaces field names

    func testValidation_withFields_mentionsFields() {
        let fields = ["email", "phone"]
        let copy = ErrorCopy.copy(for: .validation(fields))
        XCTAssertTrue(copy.body.contains("email"), "body should mention 'email'")
        XCTAssertTrue(copy.body.contains("phone"), "body should mention 'phone'")
    }

    func testValidation_withManyFields_clampedToThree() {
        let fields = ["a", "b", "c", "d", "e"]
        let copy = ErrorCopy.copy(for: .validation(fields))
        XCTAssertFalse(copy.body.contains("d"), "4th field must not appear in body")
        XCTAssertFalse(copy.body.contains("e"), "5th field must not appear in body")
    }

    func testValidation_emptyFields_stillHasBody() {
        let copy = ErrorCopy.copy(for: .validation([]))
        XCTAssertFalse(copy.body.isEmpty)
    }

    // MARK: — rateLimited() with seconds includes the count

    func testRateLimited_withSeconds_includesCount() {
        let copy = ErrorCopy.copy(for: .rateLimited(retrySeconds: 60))
        XCTAssertTrue(copy.body.contains("60"), "body should include the retry second count")
    }

    func testRateLimited_nilSeconds_hasGenericBody() {
        let copy = ErrorCopy.copy(for: .rateLimited(retrySeconds: nil))
        XCTAssertFalse(copy.body.isEmpty)
    }

    // MARK: — Tone compliance

    func testAllCopiesPassToneGuidelines() {
        let states: [CoreErrorState] = [
            .network,
            .server(status: 500, message: nil),
            .unauthorized,
            .forbidden,
            .notFound,
            .offline,
            .validation([]),
            .validation(["email"]),
            .rateLimited(retrySeconds: nil),
            .rateLimited(retrySeconds: 10),
            .unknown
        ]
        for state in states {
            let copy = ErrorCopy.copy(for: state)
            let titleViolations = ToneGuidelines.violations(in: copy.title)
            let bodyViolations  = ToneGuidelines.violations(in: copy.body)
            XCTAssertTrue(titleViolations.isEmpty,
                "Title for \(state) has tone violations: \(titleViolations) — \"\(copy.title)\"")
            XCTAssertTrue(bodyViolations.isEmpty,
                "Body for \(state) has tone violations: \(bodyViolations) — \"\(copy.body)\"")
        }
    }
}
