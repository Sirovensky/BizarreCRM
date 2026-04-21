import XCTest
@testable import Loyalty

/// §38 — LoyaltyCalculator, LoyaltyRule, LoyaltyTier threshold tests.
///
/// All helpers are pure functions — no network, no MainActor required.
final class LoyaltyEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeRule(
        pointsPerDollar: Int = 1,
        tuesdayMultiplier: Int = 2,
        signupBonusPoints: Int = 100,
        birthdayMultiplier: Int = 3,
        expiryDays: Int = 365
    ) -> LoyaltyRule {
        LoyaltyRule(
            pointsPerDollar: pointsPerDollar,
            tuesdayMultiplier: tuesdayMultiplier,
            signupBonusPoints: signupBonusPoints,
            birthdayMultiplier: birthdayMultiplier,
            expiryDays: expiryDays
        )
    }

    private func makeSale(
        amountCents: Int,
        date: Date = Date(),
        isBirthday: Bool = false
    ) -> LoyaltySale {
        LoyaltySale(amountCents: amountCents, date: date, isBirthday: isBirthday)
    }

    // MARK: - LoyaltyTier thresholds

    func test_tier_bronze_zeroSpend() {
        XCTAssertEqual(LoyaltyCalculator.tier(for: 0), .bronze)
    }

    func test_tier_bronze_justBelow500() {
        // $499.99 = 49_999 cents → bronze
        XCTAssertEqual(LoyaltyCalculator.tier(for: 49_999), .bronze)
    }

    func test_tier_silver_atThreshold() {
        // $500 = 50_000 cents → silver
        XCTAssertEqual(LoyaltyCalculator.tier(for: 50_000), .silver)
    }

    func test_tier_silver_justBelow1000() {
        XCTAssertEqual(LoyaltyCalculator.tier(for: 99_999), .silver)
    }

    func test_tier_gold_atThreshold() {
        // $1,000 = 100_000 cents → gold
        XCTAssertEqual(LoyaltyCalculator.tier(for: 100_000), .gold)
    }

    func test_tier_gold_justBelow5000() {
        XCTAssertEqual(LoyaltyCalculator.tier(for: 499_999), .gold)
    }

    func test_tier_platinum_atThreshold() {
        // $5,000 = 500_000 cents → platinum
        XCTAssertEqual(LoyaltyCalculator.tier(for: 500_000), .platinum)
    }

    func test_tier_platinum_largeSpend() {
        XCTAssertEqual(LoyaltyCalculator.tier(for: 10_000_000), .platinum)
    }

    // MARK: - LoyaltyTier.minLifetimeSpendCents

    func test_bronze_minLifetimeSpendCents_zero() {
        XCTAssertEqual(LoyaltyTier.bronze.minLifetimeSpendCents, 0)
    }

    func test_silver_minLifetimeSpendCents_50000() {
        XCTAssertEqual(LoyaltyTier.silver.minLifetimeSpendCents, 50_000)
    }

    func test_gold_minLifetimeSpendCents_100000() {
        XCTAssertEqual(LoyaltyTier.gold.minLifetimeSpendCents, 100_000)
    }

    func test_platinum_minLifetimeSpendCents_500000() {
        XCTAssertEqual(LoyaltyTier.platinum.minLifetimeSpendCents, 500_000)
    }

    // MARK: - LoyaltyTier.perksDescription

    func test_perksDescription_notEmpty_bronze() {
        XCTAssertFalse(LoyaltyTier.bronze.perksDescription.isEmpty)
    }

    func test_perksDescription_notEmpty_silver() {
        XCTAssertFalse(LoyaltyTier.silver.perksDescription.isEmpty)
    }

    func test_perksDescription_notEmpty_gold() {
        XCTAssertFalse(LoyaltyTier.gold.perksDescription.isEmpty)
    }

    func test_perksDescription_notEmpty_platinum() {
        XCTAssertFalse(LoyaltyTier.platinum.perksDescription.isEmpty)
    }

    // MARK: - Points earn — basic

    // Use a known non-Tuesday date: 2026-04-22 is Wednesday
    private var wednesday: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 22
        return cal.date(from: comps)!
    }

    func test_points_earned_onePointPerDollar() {
        let rule = makeRule(pointsPerDollar: 1)
        let sale = makeSale(amountCents: 100_00, date: wednesday) // $100, not Tuesday
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 100)
    }

    func test_points_earned_twoPointsPerDollar() {
        let rule = makeRule(pointsPerDollar: 2)
        let sale = makeSale(amountCents: 50_00, date: wednesday) // $50, not Tuesday
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 100)
    }

    func test_points_earned_zeroCents_returnsZero() {
        let rule = makeRule(pointsPerDollar: 1)
        let sale = makeSale(amountCents: 0, date: wednesday)
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 0)
    }

    func test_points_earned_rounds_down_subDollar() {
        // 99 cents → 0 full dollars → 0 points
        let rule = makeRule(pointsPerDollar: 1)
        let sale = makeSale(amountCents: 99, date: wednesday)
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 0)
    }

    func test_points_earned_exactDollar_onePoint() {
        let rule = makeRule(pointsPerDollar: 1)
        let sale = makeSale(amountCents: 100, date: wednesday)
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 1)
    }

    // MARK: - Tuesday bonus

    func test_points_earned_tuesdayBonus_applied() {
        // Tuesday: 2026-04-21 is a Tuesday
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 21
        let tuesday = cal.date(from: comps)!

        let rule = makeRule(pointsPerDollar: 1, tuesdayMultiplier: 2)
        let sale = makeSale(amountCents: 100_00, date: tuesday)
        // $100 * 1pt/$ * 2x Tuesday = 200
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 200)
    }

    func test_points_earned_wednesday_noTuesdayBonus() {
        // 2026-04-22 is a Wednesday
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 22
        let wednesday = cal.date(from: comps)!

        let rule = makeRule(pointsPerDollar: 1, tuesdayMultiplier: 2)
        let sale = makeSale(amountCents: 100_00, date: wednesday)
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 100)
    }

    // MARK: - Birthday bonus

    func test_points_earned_birthdayMultiplier_applied() {
        let rule = makeRule(pointsPerDollar: 1, birthdayMultiplier: 3)
        let sale = makeSale(amountCents: 100_00, isBirthday: true)
        // $100 * 1pt/$ * 3x birthday = 300
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 300)
    }

    func test_points_earned_notBirthday_noBirthdayMultiplier() {
        let rule = makeRule(pointsPerDollar: 1, birthdayMultiplier: 3)
        let sale = makeSale(amountCents: 100_00, date: wednesday, isBirthday: false)
        XCTAssertEqual(LoyaltyCalculator.points(earned: sale, rule: rule), 100)
    }

    // MARK: - Points redemption

    func test_redemption_100points_atDefault_rate() {
        // Default: 100 points = $1 = 100 cents
        let rate = LoyaltyRedemptionRate(centsPerPoint: 1)
        XCTAssertEqual(LoyaltyCalculator.redemption(points: 100, rate: rate), 100)
    }

    func test_redemption_200points_at2centsPerPoint() {
        let rate = LoyaltyRedemptionRate(centsPerPoint: 2)
        XCTAssertEqual(LoyaltyCalculator.redemption(points: 200, rate: rate), 400)
    }

    func test_redemption_zeroPoints_zeroDiscount() {
        let rate = LoyaltyRedemptionRate(centsPerPoint: 1)
        XCTAssertEqual(LoyaltyCalculator.redemption(points: 0, rate: rate), 0)
    }

    func test_redemption_fractionalCent_floorsToZero() {
        // 1 point at 0.5 cents each → 0 cents (integer math)
        let rate = LoyaltyRedemptionRate(centsPerPoint: 0)
        XCTAssertEqual(LoyaltyCalculator.redemption(points: 100, rate: rate), 0)
    }

    // MARK: - Expiry

    func test_expiry_365days_returnsCorrectDate() {
        let rule = makeRule(expiryDays: 365)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2025; comps.month = 1; comps.day = 1
        comps.timeZone = TimeZone(identifier: "UTC")
        let earned = cal.date(from: comps)!
        let expected = cal.date(byAdding: .day, value: 365, to: earned)!
        let expiry = LoyaltyCalculator.expiry(earnedAt: earned, rule: rule)
        XCTAssertEqual(expiry, expected)
    }

    func test_expiry_0days_returnsNil() {
        let rule = makeRule(expiryDays: 0)
        let expiry = LoyaltyCalculator.expiry(earnedAt: Date(), rule: rule)
        XCTAssertNil(expiry)
    }

    func test_expiry_negativeDays_returnsNil() {
        let rule = makeRule(expiryDays: -1)
        let expiry = LoyaltyCalculator.expiry(earnedAt: Date(), rule: rule)
        XCTAssertNil(expiry)
    }

    func test_expiry_30days_shortExpiry() {
        let rule = makeRule(expiryDays: 30)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2025; comps.month = 3; comps.day = 1
        comps.timeZone = TimeZone(identifier: "UTC")
        let earned = cal.date(from: comps)!
        let expected = cal.date(byAdding: .day, value: 30, to: earned)!
        XCTAssertEqual(LoyaltyCalculator.expiry(earnedAt: earned, rule: rule), expected)
    }

    // MARK: - LoyaltyRule defaults

    func test_loyaltyRule_defaults_sane() {
        let rule = LoyaltyRule.default
        XCTAssertGreaterThan(rule.pointsPerDollar, 0)
        XCTAssertGreaterThan(rule.expiryDays, 0)
    }

    func test_loyaltyRule_signupBonus_positive() {
        let rule = makeRule(signupBonusPoints: 200)
        XCTAssertEqual(rule.signupBonusPoints, 200)
    }
}

// MARK: - MembershipPerkApplierTests

final class MembershipPerkApplierTests: XCTestCase {

    private func makeCart(subtotalCents: Int) -> LoyaltyCart {
        LoyaltyCart(subtotalCents: subtotalCents)
    }

    private func makePlan(perks: [MembershipPerk]) -> MembershipPlan {
        MembershipPlan(
            id: "plan-1",
            name: "Gold Plan",
            pricePerPeriodCents: 999,
            periodDays: 30,
            perks: perks,
            signupBonusPoints: 50
        )
    }

    private func makeMembership(planId: String = "plan-1", status: MembershipStatus = .active) -> Membership {
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

    // MARK: - No membership

    func test_discount_nilMembership_returnsZero() {
        let cart = makeCart(subtotalCents: 10_000)
        let discount = MembershipPerkApplier.discount(cart: cart, membership: nil, plan: nil)
        XCTAssertEqual(discount, 0)
    }

    func test_discount_inactiveMembership_returnsZero() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership(status: .cancelled)
        let cart = makeCart(subtotalCents: 10_000)
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertEqual(discount, 0)
    }

    // MARK: - Percentage discount

    func test_discount_10percent_on_100dollars() {
        let plan = makePlan(perks: [.percentageDiscount(10)])
        let membership = makeMembership()
        let cart = makeCart(subtotalCents: 10_000) // $100
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertEqual(discount, 1_000) // $10 off
    }

    func test_discount_50percent_on_200dollars() {
        let plan = makePlan(perks: [.percentageDiscount(50)])
        let membership = makeMembership()
        let cart = makeCart(subtotalCents: 20_000) // $200
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertEqual(discount, 10_000) // $100 off
    }

    func test_discount_doesNotExceedSubtotal() {
        let plan = makePlan(perks: [.percentageDiscount(200)])
        let membership = makeMembership()
        let cart = makeCart(subtotalCents: 5_000)
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertLessThanOrEqual(discount, cart.subtotalCents)
    }

    // MARK: - Fixed discount

    func test_discount_fixed500cents() {
        let plan = makePlan(perks: [.fixedDiscount(500)])
        let membership = makeMembership()
        let cart = makeCart(subtotalCents: 10_000)
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertEqual(discount, 500)
    }

    func test_discount_fixed_capped_at_subtotal() {
        let plan = makePlan(perks: [.fixedDiscount(99_999)])
        let membership = makeMembership()
        let cart = makeCart(subtotalCents: 1_000)
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertEqual(discount, 1_000)
    }

    // MARK: - No perks = zero discount

    func test_discount_noPerks_returnsZero() {
        let plan = makePlan(perks: [])
        let membership = makeMembership()
        let cart = makeCart(subtotalCents: 10_000)
        let discount = MembershipPerkApplier.discount(cart: cart, membership: membership, plan: plan)
        XCTAssertEqual(discount, 0)
    }
}

// MARK: - MembershipSubscriptionManagerTests

final class MembershipSubscriptionManagerTests: XCTestCase {

    func test_initialState_isEmpty() async {
        let mgr = MembershipSubscriptionManager()
        let memberships = await mgr.activeMemberships
        XCTAssertTrue(memberships.isEmpty)
    }

    func test_enroll_addsToActiveMemberships() async {
        let mgr = MembershipSubscriptionManager()
        let plan = MembershipPlan(
            id: "plan-1",
            name: "Basic",
            pricePerPeriodCents: 999,
            periodDays: 30,
            perks: [],
            signupBonusPoints: 0
        )
        let membership = await mgr.enroll(customerId: "cust-1", plan: plan)
        XCTAssertEqual(membership.status, .active)
        XCTAssertEqual(membership.customerId, "cust-1")
        XCTAssertEqual(membership.planId, plan.id)
    }

    func test_cancel_setsStatusToCancelled() async {
        let mgr = MembershipSubscriptionManager()
        let plan = MembershipPlan(
            id: "plan-2",
            name: "Pro",
            pricePerPeriodCents: 1999,
            periodDays: 30,
            perks: [],
            signupBonusPoints: 0
        )
        let membership = await mgr.enroll(customerId: "cust-2", plan: plan)
        let cancelled = await mgr.cancel(membershipId: membership.id)
        XCTAssertEqual(cancelled?.status, .cancelled)
    }

    func test_pause_setsStatusToPaused() async {
        let mgr = MembershipSubscriptionManager()
        let plan = MembershipPlan(
            id: "plan-3",
            name: "Premium",
            pricePerPeriodCents: 2999,
            periodDays: 30,
            perks: [],
            signupBonusPoints: 0
        )
        let membership = await mgr.enroll(customerId: "cust-3", plan: plan)
        let paused = await mgr.pause(membershipId: membership.id)
        XCTAssertEqual(paused?.status, .paused)
    }

    func test_resume_setsStatusBackToActive() async {
        let mgr = MembershipSubscriptionManager()
        let plan = MembershipPlan(
            id: "plan-4",
            name: "Standard",
            pricePerPeriodCents: 499,
            periodDays: 30,
            perks: [],
            signupBonusPoints: 0
        )
        let membership = await mgr.enroll(customerId: "cust-4", plan: plan)
        _ = await mgr.pause(membershipId: membership.id)
        let resumed = await mgr.resume(membershipId: membership.id)
        XCTAssertEqual(resumed?.status, .active)
    }

    func test_cancel_unknownId_returnsNil() async {
        let mgr = MembershipSubscriptionManager()
        let result = await mgr.cancel(membershipId: "nonexistent")
        XCTAssertNil(result)
    }
}
