import XCTest
@testable import Core

// §28.7 — Unit tests for @SensitiveField property wrapper

final class SensitiveFieldMarkerTests: XCTestCase {

    // MARK: - Helpers

    private struct Contact {
        @SensitiveField(.email) var email: String
        @SensitiveField(.phone) var phone: String
        @SensitiveField(.name)  var name: String
        // Multi-category field
        @SensitiveField(.email, .phone) var contactSummary: String
    }

    // MARK: - wrappedValue

    func test_wrappedValue_returnsRawEmail() {
        var c = Contact(email: "alice@example.com", phone: "555-1234", name: "Alice Smith", contactSummary: "")
        XCTAssertEqual(c.email, "alice@example.com")
    }

    func test_wrappedValue_isMutable() {
        var c = Contact(email: "a@b.com", phone: "", name: "", contactSummary: "")
        c.email = "new@example.org"
        XCTAssertEqual(c.email, "new@example.org")
    }

    // MARK: - projectedValue.redacted

    func test_projectedValue_redactsEmail() {
        let c = Contact(email: "alice@example.com", phone: "", name: "", contactSummary: "")
        // $email.redacted should not contain the raw address
        XCTAssertFalse(c.$email.redacted.contains("alice@example.com"))
        XCTAssertTrue(c.$email.redacted.contains("<email>"))
    }

    func test_projectedValue_redactsPhone() {
        let c = Contact(email: "", phone: "555-123-4567", name: "", contactSummary: "")
        XCTAssertFalse(c.$phone.redacted.contains("555-123-4567"))
        XCTAssertTrue(c.$phone.redacted.contains("<phone>"))
    }

    func test_projectedValue_redactsName() {
        let c = Contact(email: "", phone: "", name: "Alice Smith", contactSummary: "")
        XCTAssertFalse(c.$name.redacted.contains("Alice Smith"))
        XCTAssertTrue(c.$name.redacted.contains("<name>"))
    }

    func test_projectedValue_redactsBothCategoriesOnMultiField() {
        let c = Contact(
            email: "",
            phone: "",
            name: "",
            contactSummary: "alice@example.com 555-123-4567"
        )
        let redacted = c.$contactSummary.redacted
        XCTAssertFalse(redacted.contains("alice@example.com"))
        XCTAssertFalse(redacted.contains("555-123-4567"))
    }

    func test_projectedValue_nonPIITextUnchanged() {
        let c = Contact(email: "Customer checked in", phone: "", name: "", contactSummary: "")
        // "Customer checked in" contains no email pattern
        XCTAssertEqual(c.$email.redacted, "Customer checked in")
    }

    // MARK: - raw accessor on projection

    func test_projectedValue_raw_returnsOriginal() {
        let c = Contact(email: "alice@example.com", phone: "", name: "", contactSummary: "")
        XCTAssertEqual(c.$email.raw, "alice@example.com")
    }

    // MARK: - CustomStringConvertible guard

    func test_description_containsSentinel() {
        @SensitiveField(.email) var email: String = "alice@example.com"
        let desc = _email.description
        XCTAssertTrue(desc.contains("SENSITIVE"), "description must contain sentinel 'SENSITIVE'")
    }

    func test_debugDescription_containsSentinel() {
        @SensitiveField(.phone) var phone: String = "555-1234"
        let desc = _phone.debugDescription
        XCTAssertTrue(desc.contains("SENSITIVE"))
    }

    // MARK: - Non-String type fallback

    func test_nonStringType_redacted_containsRedactedLabel() {
        @SensitiveField(.deviceID) var deviceToken: Int = 42
        let projection = _deviceToken.projectedValue
        XCTAssertTrue(projection.redacted.contains("<redacted:"), projection.redacted)
    }

    // MARK: - Default categories (no explicit categories → all)

    func test_defaultCategories_whenNoneSpecified_coversAllCategories() {
        let wrapper = SensitiveField(wrappedValue: "test", categories: [])
        // When no categories supplied, the wrapper falls back to allCases
        XCTAssertEqual(wrapper.categories.count, DataHandlingCategory.allCases.count)
    }
}
