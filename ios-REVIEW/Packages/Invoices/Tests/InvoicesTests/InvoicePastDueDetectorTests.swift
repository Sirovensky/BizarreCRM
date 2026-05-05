import XCTest
@testable import Invoices

final class InvoicePastDueDetectorTests: XCTestCase {

    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_paidInvoice_isNotPastDue() {
        let r = InvoicePastDueDetector.evaluate(
            balanceCents: 0, dueDate: date(2024, 1, 1),
            status: "paid", asOf: date(2024, 5, 1), calendar: utc
        )
        XCTAssertFalse(r.isPastDue)
    }

    func test_voidInvoice_isNotPastDue() {
        let r = InvoicePastDueDetector.evaluate(
            balanceCents: 5000, dueDate: date(2024, 1, 1),
            status: "void", asOf: date(2024, 5, 1), calendar: utc
        )
        XCTAssertFalse(r.isPastDue)
    }

    func test_overdueUnpaid_isPastDue_andCanRemind() {
        let r = InvoicePastDueDetector.evaluate(
            balanceCents: 5000, dueDate: date(2024, 1, 1),
            status: "unpaid", asOf: date(2024, 1, 10), calendar: utc
        )
        XCTAssertTrue(r.isPastDue)
        XCTAssertEqual(r.daysPastDue, 9)
        XCTAssertTrue(r.shouldSendReminder)
    }

    func test_recentReminder_blocksResend() {
        let r = InvoicePastDueDetector.evaluate(
            balanceCents: 5000, dueDate: date(2024, 1, 1),
            status: "unpaid", asOf: date(2024, 1, 10),
            lastReminderSentAt: date(2024, 1, 9),
            calendar: utc
        )
        XCTAssertTrue(r.isPastDue)
        XCTAssertFalse(r.shouldSendReminder)
    }

    func test_dueToday_notYetPastDue() {
        let r = InvoicePastDueDetector.evaluate(
            balanceCents: 5000, dueDate: date(2024, 1, 1),
            status: "unpaid", asOf: date(2024, 1, 1), calendar: utc
        )
        XCTAssertFalse(r.isPastDue)
    }
}
