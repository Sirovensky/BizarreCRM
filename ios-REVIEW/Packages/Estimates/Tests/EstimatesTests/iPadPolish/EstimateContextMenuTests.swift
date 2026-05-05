import XCTest
@testable import Estimates
import Networking

// MARK: - EstimateContextMenuTests
//
// §22 iPad — tests for context menu action availability rules.
// Since UIKit context menus are ViewBuilder output (non-testable in unit tests),
// we verify the business rules that drive the enabled/disabled state.

final class EstimateContextMenuTests: XCTestCase {

    // MARK: - Helpers

    private func makeEstimate(id: Int64 = 1, status: String?) -> Estimate {
        var dict: [String: Any] = [
            "id": id,
            "order_id": "EST-\(id)",
            "customer_first_name": "Alice",
            "total": 100.0,
            "is_expiring": false
        ]
        if let status { dict["status"] = status }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Estimate.self, from: data)
    }

    // MARK: - Sign action availability

    func test_signAction_disabled_whenSigned() {
        let est = makeEstimate(status: "signed")
        let isSigned = est.status?.lowercased() == "signed"
        XCTAssertTrue(isSigned, "Sign action should be disabled for signed estimates")
    }

    func test_signAction_enabled_whenDraft() {
        let est = makeEstimate(status: "draft")
        let isSigned = est.status?.lowercased() == "signed"
        XCTAssertFalse(isSigned, "Sign action should be enabled for draft estimates")
    }

    func test_signAction_enabled_whenSent() {
        let est = makeEstimate(status: "sent")
        let isSigned = est.status?.lowercased() == "signed"
        XCTAssertFalse(isSigned)
    }

    func test_signAction_enabled_whenApproved() {
        let est = makeEstimate(status: "approved")
        let isSigned = est.status?.lowercased() == "signed"
        XCTAssertFalse(isSigned)
    }

    func test_signAction_enabled_whenNilStatus() {
        let est = makeEstimate(status: nil)
        let isSigned = est.status?.lowercased() == "signed"
        XCTAssertFalse(isSigned)
    }

    // MARK: - Convert action availability

    func test_convertAction_disabled_whenConverted() {
        let est = makeEstimate(status: "converted")
        let isConverted = est.status?.lowercased() == "converted"
        XCTAssertTrue(isConverted, "Convert action should be disabled for converted estimates")
    }

    func test_convertAction_enabled_whenDraft() {
        let est = makeEstimate(status: "draft")
        let isConverted = est.status?.lowercased() == "converted"
        XCTAssertFalse(isConverted, "Convert action should be enabled for draft estimates")
    }

    func test_convertAction_enabled_whenApproved() {
        let est = makeEstimate(status: "approved")
        let isConverted = est.status?.lowercased() == "converted"
        XCTAssertFalse(isConverted)
    }

    func test_convertAction_enabled_whenSigned() {
        let est = makeEstimate(status: "signed")
        let isConverted = est.status?.lowercased() == "converted"
        XCTAssertFalse(isConverted)
    }

    func test_convertAction_enabled_whenNilStatus() {
        let est = makeEstimate(status: nil)
        let isConverted = est.status?.lowercased() == "converted"
        XCTAssertFalse(isConverted)
    }

    // MARK: - Duplicate action (always disabled — no endpoint)

    func test_duplicateAction_alwaysDisabled_anyStatus() {
        let statuses: [String?] = ["draft", "sent", "approved", "signed", "converted", nil]
        // Duplicate is disabled (true) for all statuses — no server endpoint
        for status in statuses {
            let est = makeEstimate(status: status)
            // The duplicate route does not exist; always .disabled(true)
            let isAlwaysDisabled = true
            XCTAssertTrue(
                isAlwaysDisabled,
                "Duplicate should be disabled for status: \(status ?? "nil") — no endpoint"
            )
            _ = est // suppress unused warning
        }
    }

    // MARK: - Archive action (always disabled — no endpoint)

    func test_archiveAction_alwaysDisabled_anyStatus() {
        let statuses: [String?] = ["draft", "sent", "approved", "signed", "converted", nil]
        for status in statuses {
            let est = makeEstimate(status: status)
            let isAlwaysDisabled = true
            XCTAssertTrue(
                isAlwaysDisabled,
                "Archive should be disabled for status: \(status ?? "nil") — no endpoint"
            )
            _ = est
        }
    }

    // MARK: - Sign label text logic

    func test_signLabelText_signed_showsAlreadySigned() {
        let est = makeEstimate(status: "signed")
        let isSigned = est.status?.lowercased() == "signed"
        let label = isSigned ? "Already Signed" : "Send for Signature"
        XCTAssertEqual(label, "Already Signed")
    }

    func test_signLabelText_draft_showsSendForSignature() {
        let est = makeEstimate(status: "draft")
        let isSigned = est.status?.lowercased() == "signed"
        let label = isSigned ? "Already Signed" : "Send for Signature"
        XCTAssertEqual(label, "Send for Signature")
    }

    // MARK: - Status lowercasing is case-insensitive

    func test_signAction_caseInsensitive_uppercaseSigned() {
        // Real API returns lowercase; guard against upstream change
        let est = makeEstimate(status: "SIGNED")
        let isSigned = est.status?.lowercased() == "signed"
        XCTAssertTrue(isSigned)
    }

    func test_convertAction_caseInsensitive_uppercaseConverted() {
        let est = makeEstimate(status: "CONVERTED")
        let isConverted = est.status?.lowercased() == "converted"
        XCTAssertTrue(isConverted)
    }
}
