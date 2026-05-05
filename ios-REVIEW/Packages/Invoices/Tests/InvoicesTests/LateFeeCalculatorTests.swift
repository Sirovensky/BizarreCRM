import XCTest
@testable import Invoices

// §7.12 LateFeeCalculator tests — flat, percent, compound, grace window

final class LateFeeCalculatorTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    // MARK: - No fee cases

    func test_noDueDate_returnsZero() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: nil)
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 0)
        XCTAssertEqual(LateFeeCalculator.compute(invoice: invoice, asOf: makeDate(2024, 2, 1), policy: policy), 0)
    }

    func test_zeroBalance_returnsZero() {
        let invoice = InvoiceForFeeCalc(balanceCents: 0, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 0)
        XCTAssertEqual(LateFeeCalculator.compute(invoice: invoice, asOf: makeDate(2024, 2, 1), policy: policy), 0)
    }

    func test_withinGracePeriod_returnsZero() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 7)
        // 5 days after due, grace = 7 → no fee
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 6),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 0)
    }

    func test_exactlyOnDueDate_returnsZero() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 15))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 0)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 15),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 0)
    }

    func test_noPolicyConfigured_returnsZero() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(gracePeriodDays: 0)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 2, 1),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 0)
    }

    // MARK: - Flat fee

    func test_flatFee_afterGrace_returnsFlatAmount() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 2500, gracePeriodDays: 3)
        // 10 days after due, 3-day grace → 7 overdue days → flat fee applies
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 11),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 2500)
    }

    func test_flatFee_dayAfterGraceExpires_appliesExactly() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 1000, gracePeriodDays: 5)
        // Exactly 6 days after due: 6 > 5 grace → fee applies
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 7),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 1000)
    }

    func test_flatFee_withCap_cappedAtMaxFee() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 5000, gracePeriodDays: 0, maxFeeCents: 1000)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 2),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 1000)
    }

    func test_flatFee_zeroCap_returnsZero() {
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 5000, gracePeriodDays: 0, maxFeeCents: 0)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 15),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 0)
    }

    // MARK: - Simple percentage

    func test_simplePercent_oneDay_correctAmount() {
        // balance=10000¢, rate=1%/day, 1 overdue day → fee = 100¢
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(percentPerDay: 1.0, gracePeriodDays: 0, compoundDaily: false)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 2),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 100)
    }

    func test_simplePercent_tenDays_linearAccumulation() {
        // balance=10000¢, 0.5%/day, 10 overdue days → fee = 10000 × 0.005 × 10 = 500¢
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(percentPerDay: 0.5, gracePeriodDays: 0, compoundDaily: false)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 11),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 500)
    }

    func test_simplePercent_withGrace_onlyCountsOverdueDays() {
        // balance=10000¢, 1%/day, grace=5, asOf 10 days late → 5 overdue days → fee = 500¢
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(percentPerDay: 1.0, gracePeriodDays: 5, compoundDaily: false)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 11),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 500)
    }

    func test_simplePercent_withCap_respectsCap() {
        // balance=100000¢, 10%/day, 5 overdue → fee = 50000 but cap is 5000
        let invoice = InvoiceForFeeCalc(balanceCents: 100000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(percentPerDay: 10.0, gracePeriodDays: 0, compoundDaily: false, maxFeeCents: 5000)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 6),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 5000)
    }

    // MARK: - Compound percentage

    func test_compoundPercent_greaterThanSimple() {
        // With compound, after N days the fee should be >= the simple fee
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let simplePolicy = LateFeePolicy(percentPerDay: 1.0, gracePeriodDays: 0, compoundDaily: false)
        let compoundPolicy = LateFeePolicy(percentPerDay: 1.0, gracePeriodDays: 0, compoundDaily: true)
        let asOf = makeDate(2024, 1, 31)  // 30 overdue days

        let simpleFee = LateFeeCalculator.compute(
            invoice: invoice, asOf: asOf, policy: simplePolicy, calendar: utcCalendar
        )
        let compoundFee = LateFeeCalculator.compute(
            invoice: invoice, asOf: asOf, policy: compoundPolicy, calendar: utcCalendar
        )
        XCTAssertGreaterThan(compoundFee, simpleFee)
    }

    func test_compoundPercent_oneDayMatchesSimple() {
        // After 1 day, compound == simple (no difference for single period)
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let simplePolicy = LateFeePolicy(percentPerDay: 2.0, gracePeriodDays: 0, compoundDaily: false)
        let compoundPolicy = LateFeePolicy(percentPerDay: 2.0, gracePeriodDays: 0, compoundDaily: true)
        let asOf = makeDate(2024, 1, 2)

        let simpleFee = LateFeeCalculator.compute(
            invoice: invoice, asOf: asOf, policy: simplePolicy, calendar: utcCalendar
        )
        let compoundFee = LateFeeCalculator.compute(
            invoice: invoice, asOf: asOf, policy: compoundPolicy, calendar: utcCalendar
        )
        XCTAssertEqual(simpleFee, compoundFee)
    }

    func test_compoundPercent_knownValue() {
        // balance=10000, 1%/day, 2 days → compound = 10000 × ((1.01)^2 - 1) = 10000 × 0.0201 = 201¢
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(percentPerDay: 1.0, gracePeriodDays: 0, compoundDaily: true)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 3),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 201)
    }

    func test_compoundPercent_withCap_appliesCap() {
        let invoice = InvoiceForFeeCalc(balanceCents: 100000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(percentPerDay: 5.0, gracePeriodDays: 0, compoundDaily: true, maxFeeCents: 10000)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 31),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 10000)
    }

    // MARK: - Grace period edge cases

    func test_gracePeriodExactlyExpired_feeApplies() {
        // grace=3, 4 days late → grace over by 1 day
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 3)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 5),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 500)
    }

    func test_gracePeriodLastDay_noFee() {
        // grace=3, exactly 3 days late → still in grace
        let invoice = InvoiceForFeeCalc(balanceCents: 10000, dueDate: makeDate(2024, 1, 1))
        let policy = LateFeePolicy(flatFeeCents: 500, gracePeriodDays: 3)
        let fee = LateFeeCalculator.compute(
            invoice: invoice,
            asOf: makeDate(2024, 1, 4),
            policy: policy,
            calendar: utcCalendar
        )
        XCTAssertEqual(fee, 0)
    }

    // MARK: - Helpers

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
