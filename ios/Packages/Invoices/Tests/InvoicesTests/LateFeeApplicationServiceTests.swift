import XCTest
@testable import Invoices

final class LateFeeApplicationServiceTests: XCTestCase {

    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_zeroBalance_doesNotApply() {
        let inv = InvoiceForFeeCalc(balanceCents: 0, dueDate: date(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 0)
        let dec = LateFeeApplicationService.evaluate(invoice: inv, asOf: date(2024, 2, 1), policy: policy, calendar: utc)
        XCTAssertFalse(dec.shouldApply)
        XCTAssertEqual(dec.computedFeeCents, 0)
    }

    func test_noDueDate_doesNotApply() {
        let inv = InvoiceForFeeCalc(balanceCents: 5000, dueDate: nil)
        let policy = LateFeePolicy(flatFeeCents: 500)
        let dec = LateFeeApplicationService.evaluate(invoice: inv, asOf: date(2024, 2, 1), policy: policy, calendar: utc)
        XCTAssertFalse(dec.shouldApply)
    }

    func test_withinGrace_doesNotApply() {
        let inv = InvoiceForFeeCalc(balanceCents: 10_000, dueDate: date(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 7)
        let dec = LateFeeApplicationService.evaluate(invoice: inv, asOf: date(2024, 1, 5), policy: policy, calendar: utc)
        XCTAssertFalse(dec.shouldApply)
    }

    func test_pastGrace_appliesFlatFee() {
        let inv = InvoiceForFeeCalc(balanceCents: 10_000, dueDate: date(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 7)
        let dec = LateFeeApplicationService.evaluate(invoice: inv, asOf: date(2024, 1, 15), policy: policy, calendar: utc)
        XCTAssertTrue(dec.shouldApply)
        XCTAssertEqual(dec.computedFeeCents, 500)
    }

    func test_alreadyApplied_returnsDelta() {
        let inv = InvoiceForFeeCalc(balanceCents: 10_000, dueDate: date(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 0)
        let dec = LateFeeApplicationService.evaluate(
            invoice: inv, asOf: date(2024, 1, 5), policy: policy,
            alreadyAppliedCents: 500, calendar: utc
        )
        XCTAssertFalse(dec.shouldApply)
    }
}
