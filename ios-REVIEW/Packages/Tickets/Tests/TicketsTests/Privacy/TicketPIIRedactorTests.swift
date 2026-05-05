import XCTest
@testable import Tickets

// §28 Security & Privacy — TicketPIIRedactor unit tests

final class TicketPIIRedactorTests: XCTestCase {

    // MARK: - redactTicketText

    func test_redactTicketText_removesEmail() {
        let note = "Customer contacted via alice@example.com for update"
        let result = TicketPIIRedactor.redactTicketText(note)
        XCTAssertFalse(result.contains("alice@example.com"), result)
        XCTAssertTrue(result.contains("<email>"), result)
    }

    func test_redactTicketText_removesPhone() {
        let note = "Call back at 555-123-4567 after 5pm"
        let result = TicketPIIRedactor.redactTicketText(note)
        XCTAssertFalse(result.contains("555-123-4567"), result)
        XCTAssertTrue(result.contains("<phone>"), result)
    }

    func test_redactTicketText_removesDeviceSerial() {
        let note = "Device serial: ABCD1234EF"
        let result = TicketPIIRedactor.redactTicketText(note)
        XCTAssertFalse(result.contains("ABCD1234EF"), result)
    }

    func test_redactTicketText_preservesNonPII() {
        let note = "Replaced screen and cleaned ports."
        let result = TicketPIIRedactor.redactTicketText(note)
        XCTAssertEqual(result, note)
    }

    // MARK: - redactContactInfo

    func test_redactContactInfo_removesEmailAndPhone() {
        let info = "alice@example.com / 555-123-4567"
        let result = TicketPIIRedactor.redactContactInfo(info)
        XCTAssertFalse(result.contains("alice@example.com"), result)
        XCTAssertFalse(result.contains("555-123-4567"), result)
    }

    func test_redactContactInfo_doesNotRedactSerialNumbers() {
        // Serial numbers are deviceID category, not in contactInfoCategories
        let info = "Serial: ABCD1234EF"
        let result = TicketPIIRedactor.redactContactInfo(info)
        // contactInfoCategories has no .deviceID rule — serial should survive
        XCTAssertTrue(result.contains("ABCD1234EF"), result)
    }

    // MARK: - redactDeviceInfo

    func test_redactDeviceInfo_removesUUID() {
        let info = "IDFV: 550e8400-e29b-41d4-a716-446655440000"
        let result = TicketPIIRedactor.redactDeviceInfo(info)
        XCTAssertFalse(result.contains("550e8400"), result)
        XCTAssertTrue(result.contains("<device-id>"), result)
    }

    // MARK: - redact(_:as:)

    func test_redactAs_email_redactsSingleEmail() {
        let result = TicketPIIRedactor.redact("bob@test.org", as: .email)
        XCTAssertEqual(result, "<email>")
    }

    func test_redactAs_phone_redactsSinglePhone() {
        let result = TicketPIIRedactor.redact("+1 555 000 1234", as: .phone)
        XCTAssertTrue(result.contains("<phone>"), result)
    }

    // MARK: - redactAll

    func test_redactAll_removesAllKnownPIICategories() {
        let mixed = "Name: Alice Smith, email: alice@example.com, phone: 555-123-4567"
        let result = TicketPIIRedactor.redactAll(mixed)
        XCTAssertFalse(result.contains("Alice Smith"), result)
        XCTAssertFalse(result.contains("alice@example.com"), result)
        XCTAssertFalse(result.contains("555-123-4567"), result)
    }

    // MARK: - Category set constants (sanity checks)

    func test_ticketTextCategories_doesNotIncludePaymentCard() {
        // Tickets never contain PANs — payment-card category must not be in ticketTextCategories
        XCTAssertFalse(
            TicketPIIRedactor.ticketTextCategories.contains(.paymentCard),
            "ticketTextCategories must not include .paymentCard"
        )
    }

    func test_contactInfoCategories_containsEmailPhoneName() {
        let cats = TicketPIIRedactor.contactInfoCategories
        XCTAssertTrue(cats.contains(.email))
        XCTAssertTrue(cats.contains(.phone))
        XCTAssertTrue(cats.contains(.name))
    }
}
