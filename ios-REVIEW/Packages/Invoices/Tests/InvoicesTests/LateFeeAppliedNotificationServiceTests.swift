import XCTest
@testable import Invoices

final class LateFeeAppliedNotificationServiceTests: XCTestCase {

    func test_formatMessage_includesAllFields() {
        let msg = LateFeeAppliedNotificationService.formatMessage(
            invoiceDisplayId: "INV-1234",
            feeCents: 250,
            newBalanceCents: 10_250,
            paymentLinkURL: "https://pay.example.com/abc",
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(msg.contains("INV-1234"))
        XCTAssertTrue(msg.contains("$2.50"))
        XCTAssertTrue(msg.contains("$102.50"))
        XCTAssertTrue(msg.contains("https://pay.example.com/abc"))
    }
}
