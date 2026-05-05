import XCTest
@testable import Core

// §71 Privacy-first Analytics — unit tests for AnalyticsPIIGuard

// MARK: - AnalyticsPIIGuardTests

final class AnalyticsPIIGuardTests: XCTestCase {

    // MARK: - markSafe

    func test_markSafe_preservesOriginalString() {
        let safe = AnalyticsPIIGuard.markSafe("ticket")
        XCTAssertEqual(safe.rawString, "ticket")
    }

    func test_markSafe_emptyString_isAllowed() {
        let safe = AnalyticsPIIGuard.markSafe("")
        XCTAssertEqual(safe.rawString, "")
    }

    func test_markSafe_returnsCorrectPhantomType() {
        // This is a compile-time test: the line below must compile.
        let _: SafeValue<PIISafe> = AnalyticsPIIGuard.markSafe("x")
    }

    // MARK: - scrubAndMark

    func test_scrubAndMark_removesEmailFromString() {
        let safe = AnalyticsPIIGuard.scrubAndMark("Contact user@example.com for info")
        XCTAssertFalse(safe.rawString.contains("@"),
                       "Email should be redacted, got: \(safe.rawString)")
        XCTAssertTrue(safe.rawString.contains("<email>"))
    }

    func test_scrubAndMark_removesPhoneFromString() {
        let safe = AnalyticsPIIGuard.scrubAndMark("Call 555-123-4567 now")
        XCTAssertFalse(safe.rawString.contains("555-123-4567"),
                       "Phone should be redacted, got: \(safe.rawString)")
        XCTAssertTrue(safe.rawString.contains("<phone>"))
    }

    func test_scrubAndMark_preservesSafeContent() {
        let safe = AnalyticsPIIGuard.scrubAndMark("ticket-open")
        XCTAssertEqual(safe.rawString, "ticket-open",
                       "Safe content should pass through unchanged")
    }

    func test_scrubAndMark_returnsCorrectPhantomType() {
        let _: SafeValue<PIISafe> = AnalyticsPIIGuard.scrubAndMark("any input")
    }

    // MARK: - isForbiddenField

    func test_isForbiddenField_returnsTrue_forKnownPIIFields() {
        let piiFields = ["email", "phone", "address", "firstName", "lastName",
                         "fullName", "customerName", "ssn", "creditCard", "cardNumber"]
        for field in piiFields {
            XCTAssertTrue(AnalyticsPIIGuard.isForbiddenField(field),
                          "'\(field)' should be detected as a forbidden field")
        }
    }

    func test_isForbiddenField_isCaseInsensitive() {
        XCTAssertTrue(AnalyticsPIIGuard.isForbiddenField("EMAIL"))
        XCTAssertTrue(AnalyticsPIIGuard.isForbiddenField("Phone"))
        XCTAssertTrue(AnalyticsPIIGuard.isForbiddenField("FIRSTNAME"))
    }

    func test_isForbiddenField_returnsFalse_forSafeFields() {
        let safeFields = ["screen", "priority", "entity", "id", "feature_id",
                          "command_id", "total_cents", "item_count", "error_code"]
        for field in safeFields {
            XCTAssertFalse(AnalyticsPIIGuard.isForbiddenField(field),
                           "'\(field)' should NOT be detected as a forbidden field")
        }
    }

    func test_isForbiddenField_returnsFalse_forPartialMatches() {
        // "emailNotificationsEnabled" contains "email" as substring but is not a PII field
        XCTAssertFalse(AnalyticsPIIGuard.isForbiddenField("emailNotificationsEnabled"),
                       "Partial substring match should not flag non-PII keys")
    }

    // MARK: - forbiddenFieldNames

    func test_forbiddenFieldNames_isNonEmpty() {
        XCTAssertFalse(AnalyticsPIIGuard.forbiddenFieldNames.isEmpty)
    }

    func test_forbiddenFieldNames_containsEmail() {
        // email is the canonical PII field
        XCTAssertTrue(AnalyticsPIIGuard.forbiddenFieldNames.contains("email"))
    }

    func test_forbiddenFieldNames_containsPhone() {
        XCTAssertTrue(AnalyticsPIIGuard.forbiddenFieldNames.contains("phone"))
    }

    // MARK: - Phantom type safety (compile-time; no runtime assertions needed)

    func test_safeValuePhantomType_compileTimeCheck() {
        // These two types must be distinct — the compiler enforces it.
        let safe: SafeValue<PIISafe> = AnalyticsPIIGuard.markSafe("safe")
        // SafeValue<PIIUnsafe> cannot be passed where SafeValue<PIISafe> is expected.
        // The following would NOT compile (verified by absence from the file):
        //   let unsafe: SafeValue<PIIUnsafe> = SafeValue(rawString: "x")
        //   AnalyticsEventMapper.buildRecord(for: .customerCreated, safeMarker: unsafe)
        XCTAssertEqual(safe.rawString, "safe")
    }
}
