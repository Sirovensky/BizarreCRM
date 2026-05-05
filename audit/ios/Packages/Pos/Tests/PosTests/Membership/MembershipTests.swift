import XCTest
@testable import Pos

// MARK: - Stub repository

/// Configurable test double for `LoyaltyRepository`.
private final class StubLoyaltyRepository: LoyaltyRepository, @unchecked Sendable {
    var accountToReturn: LoyaltyAccount?
    var redeemError: Error?
    var redeemCreditCents: Int = 0

    func fetchAccount(customerId: Int64) async throws -> LoyaltyAccount? {
        accountToReturn
    }

    func redeemPoints(customerId: Int64, points: Int, invoiceId: Int64?) async throws -> Int {
        if let err = redeemError { throw err }
        return redeemCreditCents
    }
}

// MARK: - LoyaltyTier tests

@MainActor
final class LoyaltyTierTests: XCTestCase {

    // ── Tier thresholds ──────────────────────────────────────────────────

    func test_silverMinimumPoints_is100() {
        XCTAssertEqual(LoyaltyTier.silver.minimumPoints, 100)
    }

    func test_goldMinimumPoints_is250() {
        XCTAssertEqual(LoyaltyTier.gold.minimumPoints, 250)
    }

    func test_platinumMinimumPoints_is500() {
        XCTAssertEqual(LoyaltyTier.platinum.minimumPoints, 500)
    }

    func test_noneMinimumPoints_isZero() {
        XCTAssertEqual(LoyaltyTier.none.minimumPoints, 0)
    }

    // ── next() chain ─────────────────────────────────────────────────────

    func test_silverNext_isGold() {
        XCTAssertEqual(LoyaltyTier.silver.next, .gold)
    }

    func test_goldNext_isPlatinum() {
        XCTAssertEqual(LoyaltyTier.gold.next, .platinum)
    }

    func test_platinumNext_isNil() {
        XCTAssertNil(LoyaltyTier.platinum.next)
    }

    func test_noneNext_isNil() {
        XCTAssertNil(LoyaltyTier.none.next)
    }

    // ── progressTo(next:currentPoints:) ──────────────────────────────────

    func test_progressToGold_midway() {
        // gold starts at 250, silver at 100 → span = 150
        // currentPoints = 175 → earned = 75/150 = 0.5
        let progress = LoyaltyTier.silver.progressTo(next: .gold, currentPoints: 175)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func test_progressToPlatinum_at285() {
        // platinum starts at 500, gold at 250 → span = 250
        // currentPoints = 285 → earned = 35/250 = 0.14
        let progress = LoyaltyTier.gold.progressTo(next: .platinum, currentPoints: 285)
        XCTAssertEqual(progress, 0.14, accuracy: 0.001,
                       "285/500 progress bar from mockup")
    }

    func test_progressClampedAt1WhenAboveThreshold() {
        let progress = LoyaltyTier.silver.progressTo(next: .gold, currentPoints: 9_999)
        XCTAssertEqual(progress, 1.0)
    }

    func test_progressClampedAt0WhenBelowThreshold() {
        let progress = LoyaltyTier.silver.progressTo(next: .gold, currentPoints: 0)
        XCTAssertEqual(progress, 0.0)
    }

    func test_platinum_progressReturns1() {
        // No next tier → always 1
        let progress = LoyaltyTier.platinum.progressTo(next: .platinum, currentPoints: 500)
        XCTAssertEqual(progress, 1.0)
    }

    // ── pointsNeeded ─────────────────────────────────────────────────────

    func test_pointsNeeded_gold285_to_platinum_is215() {
        // From mockup: 285 pts · 215 to PLATINUM
        let needed = LoyaltyTier.gold.pointsNeeded(currentPoints: 285)
        XCTAssertEqual(needed, 215)
    }

    func test_pointsNeeded_platinum_isZero() {
        XCTAssertEqual(LoyaltyTier.platinum.pointsNeeded(currentPoints: 600), 0)
    }

    // ── from(serverName:) ────────────────────────────────────────────────

    func test_fromServerName_lowercaseGold() {
        XCTAssertEqual(LoyaltyTier.from(serverName: "gold"), .gold)
    }

    func test_fromServerName_unknownMapsToNone() {
        XCTAssertEqual(LoyaltyTier.from(serverName: "diamond"), .none)
    }

    func test_fromServerName_nilMapsToNone() {
        XCTAssertEqual(LoyaltyTier.from(serverName: nil), .none)
    }
}

// MARK: - LoyaltyAccount tests

@MainActor
final class LoyaltyAccountTests: XCTestCase {

    func makeSilverAccount(points: Int = 150, discount: Int = 5) -> LoyaltyAccount {
        LoyaltyAccount(
            customerId: 1,
            tier: .silver,
            pointsBalance: points,
            pointsThisYear: points,
            discountPercent: discount
        )
    }

    func test_discountCents_10percent_on1000cents() {
        let acct = LoyaltyAccount(customerId: 1, tier: .gold, pointsBalance: 0, pointsThisYear: 0, discountPercent: 10)
        XCTAssertEqual(acct.discountCents(for: 1000), 100)
    }

    func test_discountCents_0percent_returnsZero() {
        let acct = LoyaltyAccount(customerId: 1, tier: .silver, pointsBalance: 0, pointsThisYear: 0, discountPercent: 0)
        XCTAssertEqual(acct.discountCents(for: 5000), 0)
    }

    func test_estimatedPointsEarned_27451cents_is274() {
        let acct = makeSilverAccount()
        XCTAssertEqual(acct.estimatedPointsEarned(subtotalCents: 27451), 274)
    }

    func test_isMember_trueForSilver() {
        XCTAssertTrue(makeSilverAccount().isMember)
    }

    func test_isMember_falseForNone() {
        let acct = LoyaltyAccount(customerId: 1, tier: .none, pointsBalance: 0, pointsThisYear: 0, discountPercent: 0)
        XCTAssertFalse(acct.isMember)
    }

    func test_progressToNextTier_gold285pts() {
        let acct = LoyaltyAccount(customerId: 1, tier: .gold, pointsBalance: 285, pointsThisYear: 285, discountPercent: 10)
        XCTAssertEqual(acct.progressToNextTier, 0.14, accuracy: 0.01)
    }

    func test_pointsToNextTier_gold285_is215() {
        let acct = LoyaltyAccount(customerId: 1, tier: .gold, pointsBalance: 285, pointsThisYear: 285, discountPercent: 10)
        XCTAssertEqual(acct.pointsToNextTier, 215)
    }
}

// MARK: - MembershipViewModel tests

@MainActor
final class MembershipViewModelTests: XCTestCase {

    private func makeVM(account: LoyaltyAccount? = nil, redeemError: Error? = nil, redeemCredit: Int = 0) -> (MembershipViewModel, StubLoyaltyRepository) {
        let stub = StubLoyaltyRepository()
        stub.accountToReturn = account
        stub.redeemError = redeemError
        stub.redeemCreditCents = redeemCredit
        let vm = MembershipViewModel(repository: stub)
        return (vm, stub)
    }

    private func goldAccount(points: Int = 350) -> LoyaltyAccount {
        LoyaltyAccount(customerId: 42, tier: .gold, pointsBalance: points, pointsThisYear: points, discountPercent: 10)
    }

    // ── load ──────────────────────────────────────────────────────────────

    func test_load_setsAccountWhenMember() async {
        let (vm, _) = makeVM(account: goldAccount())
        await vm.load(customerId: 42)
        XCTAssertNotNil(vm.account)
        XCTAssertEqual(vm.account?.tier, .gold)
    }

    func test_load_nilAccountForWalkIn() async {
        let (vm, _) = makeVM(account: nil)
        await vm.load(customerId: 0)
        XCTAssertNil(vm.account)
    }

    func test_load_clearsPreviousRedemption() async {
        let (vm, stub) = makeVM(account: goldAccount())
        stub.redeemCreditCents = 500
        await vm.load(customerId: 42)
        vm.cartSubtotalCents = 10_000
        try? await vm.redeem(points: 50)
        // Now reload
        await vm.load(customerId: 42)
        XCTAssertEqual(vm.redeemPoints, 0)
        XCTAssertEqual(vm.saved, 0)
    }

    // ── pointsToEarn ──────────────────────────────────────────────────────

    func test_pointsToEarn_updatesWithSubtotal() async {
        let (vm, _) = makeVM(account: goldAccount())
        await vm.load(customerId: 42)
        vm.cartSubtotalCents = 27451
        XCTAssertEqual(vm.pointsToEarn, 274)  // 1 pt per $1
    }

    // ── redeem validation ─────────────────────────────────────────────────

    func test_redeem_succeedsWhenPointsWithinBalance() async throws {
        let (vm, stub) = makeVM(account: goldAccount(points: 350))
        stub.redeemCreditCents = 1000
        await vm.load(customerId: 42)
        vm.cartSubtotalCents = 50_000
        try await vm.redeem(points: 100)
        XCTAssertEqual(vm.redeemPoints, 100)
        XCTAssertEqual(vm.saved, 1000)
    }

    func test_redeem_throwsInsufficientPointsWhenExceedingBalance() async {
        let (vm, _) = makeVM(account: goldAccount(points: 50))
        await vm.load(customerId: 42)
        vm.cartSubtotalCents = 50_000
        do {
            try await vm.redeem(points: 100)
            XCTFail("Should have thrown")
        } catch LoyaltyRedemptionError.insufficientPoints(let available, let requested) {
            XCTAssertEqual(available, 50)
            XCTAssertEqual(requested, 100)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_redeem_throwsExceedsCartTotalWhenDiscountTooLarge() async {
        let (vm, _) = makeVM(account: goldAccount(points: 500))
        await vm.load(customerId: 42)
        // Cart total = $5.00 = 500 cents; 100 pts = $10.00 = 1000 cents → exceeds
        vm.cartSubtotalCents = 500
        do {
            try await vm.redeem(points: 100)
            XCTFail("Should have thrown")
        } catch LoyaltyRedemptionError.exceedsCartTotal(let discount, let total) {
            XCTAssertEqual(discount, 1000)   // 100 pts * 10 cents
            XCTAssertEqual(total, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_redeem_throwsInvalidAmountForZeroPoints() async {
        let (vm, _) = makeVM(account: goldAccount())
        await vm.load(customerId: 42)
        vm.cartSubtotalCents = 50_000
        do {
            try await vm.redeem(points: 0)
            XCTFail("Should have thrown")
        } catch LoyaltyRedemptionError.invalidPointsAmount {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_clearRedemption_resetsState() async throws {
        let (vm, stub) = makeVM(account: goldAccount(points: 300))
        stub.redeemCreditCents = 500
        await vm.load(customerId: 42)
        vm.cartSubtotalCents = 50_000
        try await vm.redeem(points: 50)
        vm.clearRedemption()
        XCTAssertEqual(vm.redeemPoints, 0)
        XCTAssertEqual(vm.saved, 0)
    }

    // ── non-member / walk-in fallback ─────────────────────────────────────

    func test_noCustomer_accountIsNil() async {
        let (vm, _) = makeVM(account: nil)
        await vm.load(customerId: 99)
        XCTAssertNil(vm.account)
        XCTAssertFalse(vm.account?.isMember ?? false)
    }

    func test_nonMemberAccount_isMemberFalse() async {
        let nonMember = LoyaltyAccount(customerId: 1, tier: .none, pointsBalance: 0, pointsThisYear: 0, discountPercent: 0)
        let (vm, _) = makeVM(account: nonMember)
        await vm.load(customerId: 1)
        XCTAssertEqual(vm.account?.tier, .none)
        XCTAssertFalse(vm.account?.isMember ?? true)
    }

    // ── tier-up detection ─────────────────────────────────────────────────

    func test_tierUpDetection_gold285pts_reachesNearPlatinum() async {
        let acct = LoyaltyAccount(customerId: 7, tier: .gold, pointsBalance: 285, pointsThisYear: 285, discountPercent: 10)
        let (vm, _) = makeVM(account: acct)
        await vm.load(customerId: 7)
        // After a sale that earns 215+ pts, the customer would tier up to Platinum.
        // We verify the progress and points-needed computation.
        XCTAssertEqual(acct.pointsToNextTier, 215)
        XCTAssertEqual(acct.tier.next, .platinum)
    }

    func test_tierUp_platinumHasNoNextTier() async {
        let acct = LoyaltyAccount(customerId: 8, tier: .platinum, pointsBalance: 600, pointsThisYear: 600, discountPercent: 15)
        let (vm, _) = makeVM(account: acct)
        await vm.load(customerId: 8)
        XCTAssertNil(vm.account?.tier.next)
        XCTAssertEqual(vm.account?.pointsToNextTier, 0)
    }

    // ── maxRedeemablePoints ───────────────────────────────────────────────

    func test_maxRedeemablePoints_cappedByCartTotal() async {
        // balance = 500 pts ($50), cart = $20 = 2000 cents → max = 200 pts ($20)
        let acct = LoyaltyAccount(customerId: 9, tier: .gold, pointsBalance: 500, pointsThisYear: 500, discountPercent: 10)
        let (vm, _) = makeVM(account: acct)
        await vm.load(customerId: 9)
        vm.cartSubtotalCents = 2_000   // $20.00
        XCTAssertEqual(vm.maxRedeemablePoints, 200)
    }

    func test_maxRedeemablePoints_cappedByBalance() async {
        // balance = 100 pts, cart = $1000 → max = 100 pts
        let acct = LoyaltyAccount(customerId: 10, tier: .silver, pointsBalance: 100, pointsThisYear: 100, discountPercent: 5)
        let (vm, _) = makeVM(account: acct)
        await vm.load(customerId: 10)
        vm.cartSubtotalCents = 100_000   // $1000
        XCTAssertEqual(vm.maxRedeemablePoints, 100)
    }

    // ── progress bar math (covers spec "285 / 500 · 215 to PLATINUM") ─────

    func test_progressBar_gold285_outOf500() {
        // span = 500 - 250 = 250; earned = 285 - 250 = 35; 35/250 = 0.14
        let progress = LoyaltyTier.gold.progressTo(next: .platinum, currentPoints: 285)
        XCTAssertEqual(progress, 35.0 / 250.0, accuracy: 0.001)
    }
}
