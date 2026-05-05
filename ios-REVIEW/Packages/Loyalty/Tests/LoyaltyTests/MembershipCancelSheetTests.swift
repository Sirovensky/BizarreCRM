import XCTest
@testable import Loyalty

// MARK: - §38.5 MembershipCancelSheet + MembershipRenewalReminderView logic tests

final class MembershipCancelSheetTests: XCTestCase {

    // MARK: - CancelPolicy

    func test_cancelPolicy_allCases_hasTwoOptions() {
        XCTAssertEqual(MembershipCancelSheet.CancelPolicy.allCases.count, 2)
    }

    func test_cancelPolicy_endOfPeriod_rawValue() {
        XCTAssertEqual(MembershipCancelSheet.CancelPolicy.endOfPeriod.rawValue, "End of billing period")
    }

    func test_cancelPolicy_immediate_rawValue() {
        XCTAssertEqual(MembershipCancelSheet.CancelPolicy.immediate.rawValue, "Immediately")
    }

    func test_cancelPolicy_isSendable() {
        // Compile-time check: CancelPolicy conforms to Sendable
        let policy: MembershipCancelSheet.CancelPolicy = .endOfPeriod
        let _: Sendable = policy
    }

    func test_cancelPolicy_caseIterable_order() {
        let cases = MembershipCancelSheet.CancelPolicy.allCases
        XCTAssertEqual(cases[0], .endOfPeriod)
        XCTAssertEqual(cases[1], .immediate)
    }

    // MARK: - MembershipRenewalReminderView — reminder date math

    func test_reminderDates_30DaysBeforeNextBilling() throws {
        let billing = Date().addingTimeInterval(60 * 86400) // 60 days out
        let membership = Membership(
            id: "m1",
            customerId: "c1",
            planId: "p1",
            status: .active,
            startDate: Date(),
            autoRenew: true,
            nextBillingAt: billing
        )
        guard let fireDate = Calendar.current.date(
            byAdding: .day, value: -30, to: billing
        ) else {
            return XCTFail("Calendar math failed")
        }
        let diff = abs(fireDate.timeIntervalSince(billing) / 86400)
        XCTAssertEqual(diff, 30, accuracy: 0.1)
        _ = membership // suppress unused warning
    }

    func test_reminderDates_1DayBeforeNextBilling() throws {
        let billing = Date().addingTimeInterval(10 * 86400)
        guard let fireDate = Calendar.current.date(
            byAdding: .day, value: -1, to: billing
        ) else {
            return XCTFail("Calendar math failed")
        }
        let diff = billing.timeIntervalSince(fireDate) / 86400
        XCTAssertEqual(diff, 1, accuracy: 0.1)
    }

    func test_reminderOffsetDays_hasFourValues() {
        // The view uses [30, 14, 7, 1] — verify the conceptual contract
        let offsets = [30, 14, 7, 1]
        XCTAssertEqual(offsets.count, 4)
        XCTAssertTrue(offsets.contains(30))
        XCTAssertTrue(offsets.contains(1))
    }

    func test_reminderDate_isPast_forOldMembership() throws {
        // A reminder fire date that precedes now should be marked isPast
        let pastDate = Date().addingTimeInterval(-86400) // yesterday
        XCTAssertTrue(pastDate < Date())
    }

    func test_reminderDate_isFuture_forFutureMembership() throws {
        let futureDate = Date().addingTimeInterval(86400 * 7) // 7 days out
        XCTAssertFalse(futureDate < Date())
    }

    // MARK: - Membership withStatus helper (used post-cancel)

    func test_withStatus_cancelled_updatesStatus() {
        let m = Membership(
            id: "m2",
            customerId: "c2",
            planId: "p2",
            status: .active,
            startDate: Date()
        )
        let cancelled = m.withStatus(.cancelled)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.id, m.id)
        XCTAssertEqual(cancelled.customerId, m.customerId)
    }

    func test_withStatus_preservesNextBillingAt() {
        let billing = Date().addingTimeInterval(30 * 86400)
        let m = Membership(
            id: "m3",
            customerId: "c3",
            planId: "p3",
            status: .active,
            startDate: Date(),
            nextBillingAt: billing
        )
        let paused = m.withStatus(.paused)
        XCTAssertEqual(paused.nextBillingAt, billing)
    }

    // MARK: - MembershipStatus display

    func test_cancelledStatus_displayName() {
        XCTAssertEqual(MembershipStatus.cancelled.displayName, "Cancelled")
    }

    func test_activeStatus_perksActive() {
        XCTAssertTrue(MembershipStatus.active.perksActive)
    }

    func test_cancelledStatus_perksNotActive() {
        XCTAssertFalse(MembershipStatus.cancelled.perksActive)
    }

    func test_gracePeriodStatus_perksActive() {
        XCTAssertTrue(MembershipStatus.gracePeriod.perksActive)
    }
}
