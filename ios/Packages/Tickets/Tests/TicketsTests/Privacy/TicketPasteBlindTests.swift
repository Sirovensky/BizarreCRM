import XCTest
@testable import Tickets

// §28.9 Pasteboard hygiene — TicketPasteBlind unit tests
//
// Note: These tests verify audit-closure mechanics and expiry-policy constants.
// They intentionally do NOT assert on actual UIPasteboard state — pasteboard
// access in XCTest on iOS triggers a permissions toast and is flaky in CI.
// The real write path is covered by manual + integration smoke tests.

final class TicketPasteBlindTests: XCTestCase {

    // MARK: - sensitiveExpirySeconds constant

    func test_sensitiveExpirySeconds_isPositive() {
        XCTAssertGreaterThan(TicketPasteBlind.sensitiveExpirySeconds, 0)
    }

    func test_sensitiveExpirySeconds_isAtLeast60() {
        // Policy: sensitive items must be cleared within a reasonable window.
        // We require ≥ 60 s so the user has time to switch apps and paste.
        XCTAssertGreaterThanOrEqual(TicketPasteBlind.sensitiveExpirySeconds, 60)
    }

    func test_sensitiveExpirySeconds_isAtMost300() {
        // Policy: sensitive items must not linger more than 5 minutes.
        XCTAssertLessThanOrEqual(TicketPasteBlind.sensitiveExpirySeconds, 300)
    }

    // MARK: - copyEmail — audit closure

    func test_copyEmail_callsAuditClosure() {
        var auditMessage: String?
        TicketPasteBlind.copyEmail("alice@example.com") { msg in
            auditMessage = msg
        }
        XCTAssertNotNil(auditMessage, "copyEmail must invoke onCopy closure")
    }

    func test_copyEmail_auditMessage_doesNotContainRawEmail() {
        var auditMessage: String?
        TicketPasteBlind.copyEmail("alice@example.com") { msg in
            auditMessage = msg
        }
        XCTAssertFalse(
            auditMessage?.contains("alice@example.com") == true,
            "Audit message must not leak raw email: \(auditMessage ?? "")"
        )
    }

    func test_copyEmail_auditMessage_containsExpiryHint() {
        var auditMessage: String?
        TicketPasteBlind.copyEmail("alice@example.com") { msg in auditMessage = msg }
        XCTAssertTrue(
            auditMessage?.contains("expires") == true,
            "Audit message should mention expiry: \(auditMessage ?? "")"
        )
    }

    // MARK: - copyPhone — audit closure

    func test_copyPhone_callsAuditClosure() {
        var called = false
        TicketPasteBlind.copyPhone("555-123-4567") { _ in called = true }
        XCTAssertTrue(called)
    }

    func test_copyPhone_auditMessage_doesNotContainRawPhone() {
        var msg: String?
        TicketPasteBlind.copyPhone("555-123-4567") { msg = $0 }
        XCTAssertFalse(msg?.contains("555-123-4567") == true, msg ?? "")
    }

    // MARK: - copyDeviceSerial — audit closure

    func test_copyDeviceSerial_callsAuditClosure() {
        var called = false
        TicketPasteBlind.copyDeviceSerial("ABCD1234EF") { _ in called = true }
        XCTAssertTrue(called)
    }

    // MARK: - Non-sensitive copies — no expiry, audit contains actual value

    func test_copyTicketID_auditMessageContainsID() {
        var msg: String?
        TicketPasteBlind.copyTicketID("#4821") { msg = $0 }
        XCTAssertTrue(msg?.contains("#4821") == true, "Ticket ID should appear in audit: \(msg ?? "")")
    }

    func test_copyInvoiceNumber_auditMessageContainsNumber() {
        var msg: String?
        TicketPasteBlind.copyInvoiceNumber("INV-2024-001") { msg = $0 }
        XCTAssertTrue(msg?.contains("INV-2024-001") == true, msg ?? "")
    }

    func test_copySKU_auditMessageContainsSKU() {
        var msg: String?
        TicketPasteBlind.copySKU("SKU-XR-SCREEN") { msg = $0 }
        XCTAssertTrue(msg?.contains("SKU-XR-SCREEN") == true, msg ?? "")
    }

    // MARK: - Nil closure does not crash

    func test_copyEmail_nilClosure_doesNotCrash() {
        XCTAssertNoThrow(TicketPasteBlind.copyEmail("a@b.com"))
    }

    func test_copyPhone_nilClosure_doesNotCrash() {
        XCTAssertNoThrow(TicketPasteBlind.copyPhone("555-0000"))
    }

    func test_copyTicketID_nilClosure_doesNotCrash() {
        XCTAssertNoThrow(TicketPasteBlind.copyTicketID("#999"))
    }
}
