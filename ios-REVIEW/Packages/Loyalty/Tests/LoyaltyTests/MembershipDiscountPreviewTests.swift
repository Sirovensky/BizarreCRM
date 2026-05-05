import XCTest
@testable import Loyalty

/// §38 — Tests for `MembershipDiscountPreview` (pure calc) and `MembershipDiscountPreviewView` model.
final class MembershipDiscountPreviewTests: XCTestCase {

    // MARK: - Helpers

    private func makeMembership(
        planId: String = "plan-1",
        status: MembershipStatus = .active
    ) -> Membership {
        Membership(
            id: "mem-1",
            customerId: "cust-1",
            planId: planId,
            status: status,
            startDate: Date(),
            endDate: nil,
            autoRenew: true,
            nextBillingAt: nil
        )
    }

    private func makePlan(
        id: String = "plan-1",
        perks: [MembershipPerk]
    ) -> MembershipPlan {
        MembershipPlan(
            id: id,
            name: "Gold Plan",
            pricePerPeriodCents: 1_999,
            periodDays: 30,
            perks: perks,
            signupBonusPoints: 100
        )
    }

    // MARK: - No membership → no discount

    func test_preview_nilMembership_zeroDiscount() {
        let preview = MembershipDiscountPreview(
            membership: nil,
            plan: nil,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 0)
        XCTAssertFalse(preview.hasDiscount)
    }

    // MARK: - Inactive membership → no discount

    func test_preview_cancelledMembership_zeroDiscount() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership(status: .cancelled)
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 0)
        XCTAssertFalse(preview.hasDiscount)
    }

    func test_preview_pausedMembership_zeroDiscount() {
        let plan = makePlan(perks: [.percentageDiscount(15)])
        let membership = makeMembership(status: .paused)
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 0)
    }

    func test_preview_gracePeriodMembership_hasDiscount() {
        // gracePeriod membership should still grant perks
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership(status: .gracePeriod)
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 1_000) // 10% of $100
        XCTAssertTrue(preview.hasDiscount)
    }

    // MARK: - Percentage discount

    func test_preview_10percentOn100dollars() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000 // $100
        )
        XCTAssertEqual(preview.discountCents, 1_000)
        XCTAssertEqual(preview.totalAfterDiscountCents, 9_000)
        XCTAssertTrue(preview.hasDiscount)
    }

    func test_preview_0percentPerk_noDiscount() {
        let plan = makePlan(perks: [.percentageDiscount(0)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 0)
        XCTAssertFalse(preview.hasDiscount)
    }

    // MARK: - Fixed discount

    func test_preview_fixed500centsDiscount() {
        let plan = makePlan(perks: [.fixedDiscount(500)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 500)
        XCTAssertEqual(preview.totalAfterDiscountCents, 9_500)
    }

    // MARK: - Discount capped at subtotal

    func test_preview_discountCappedAtSubtotal() {
        let plan = makePlan(perks: [.fixedDiscount(99_999)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 1_000
        )
        XCTAssertEqual(preview.discountCents, 1_000)
        XCTAssertEqual(preview.totalAfterDiscountCents, 0)
    }

    // MARK: - Best perk wins (no stacking)

    func test_preview_bestPerkWins_percentageBeatsFixed() {
        // $100 cart: 10% = $10, fixed $5 → percentage wins
        let plan = makePlan(perks: [.percentageDiscount(10), .fixedDiscount(500)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 1_000) // 10%
    }

    func test_preview_bestPerkWins_fixedBeatsSmallPercentage() {
        // $10 cart: 5% = $0.50 → fixed $2 wins
        let plan = makePlan(perks: [.percentageDiscount(5), .fixedDiscount(200)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 1_000 // $10
        )
        XCTAssertEqual(preview.discountCents, 200) // $2 fixed wins over $0.50
    }

    // MARK: - Free service perk (no cash value)

    func test_preview_freeServicePerk_noDiscount() {
        let plan = makePlan(perks: [.freeService(serviceId: "battery", displayName: "Battery Test")])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.discountCents, 0)
        XCTAssertFalse(preview.hasDiscount)
    }

    // MARK: - Formatted strings

    func test_preview_formattedDiscount_correctFormat() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.formattedDiscount, "-$10.00")
    }

    func test_preview_formattedTotal_correctFormat() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.formattedTotal, "$90.00")
    }

    func test_preview_formattedDiscount_noDiscount_zeroString() {
        let preview = MembershipDiscountPreview(
            membership: nil,
            plan: nil,
            subtotalCents: 10_000
        )
        XCTAssertEqual(preview.formattedDiscount, "-$0.00")
    }

    // MARK: - appliedPerkSummary

    func test_preview_appliedPerkSummary_returnsNilWhenNoDiscount() {
        let preview = MembershipDiscountPreview(
            membership: nil,
            plan: nil,
            subtotalCents: 10_000
        )
        XCTAssertNil(preview.appliedPerkSummary)
    }

    func test_preview_appliedPerkSummary_returnsPerkNameWhenDiscount() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 10_000
        )
        XCTAssertNotNil(preview.appliedPerkSummary)
    }

    // MARK: - Zero subtotal

    func test_preview_zeroSubtotal_zeroDiscount() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 0
        )
        XCTAssertEqual(preview.discountCents, 0)
        XCTAssertEqual(preview.totalAfterDiscountCents, 0)
    }

    // MARK: - totalAfterDiscount never negative

    func test_preview_totalAfterDiscount_neverNegative() {
        let plan = makePlan(perks: [.percentageDiscount(200)])
        let membership = makeMembership()
        let preview = MembershipDiscountPreview(
            membership: membership,
            plan: plan,
            subtotalCents: 5_000
        )
        XCTAssertGreaterThanOrEqual(preview.totalAfterDiscountCents, 0)
    }
}
