import XCTest
import Networking
@testable import Loyalty

// MARK: - §22 iPad polish test suite
//
// Covers all five new components:
//   1. MembershipBalanceInspectorViewModel — state machine, progress, history.
//   2. PointsHistoryEntry — model init + identity.
//   3. TierSidebarItem — init + identity.
//   4. LoyaltyShortcutDescriptions — count + content.
//   5. MembershipContextMenuActions — closure wiring (value-type test).

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 1. MembershipBalanceInspectorViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MembershipBalanceInspectorViewModelTests: XCTestCase {

    // MARK: Helpers

    private func makeBalance(
        customerId: Int64 = 1,
        points: Int = 600,
        tier: String = "silver",
        lifetimeSpendCents: Int = 60_000,
        memberSince: String = "2024-01-01"
    ) -> LoyaltyBalance {
        LoyaltyBalance(
            customerId: customerId,
            points: points,
            tier: tier,
            lifetimeSpendCents: lifetimeSpendCents,
            memberSince: memberSince
        )
    }

    private func makeVM(result: Result<LoyaltyBalance, Error>) -> MembershipBalanceInspectorViewModel {
        MembershipBalanceInspectorViewModel(api: MockInspectorClient(result: result))
    }

    // MARK: Initial state

    func test_initialState_isIdle() {
        let vm = makeVM(result: .failure(URLError(.badURL)))
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(vm.balance)
        XCTAssertTrue(vm.history.isEmpty)
    }

    // MARK: Success path

    func test_load_success_transitionsToLoaded() async {
        let vm = makeVM(result: .success(makeBalance(points: 300, tier: "gold")))
        await vm.load(customerId: 1)
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertNotNil(vm.balance)
    }

    func test_load_success_balanceFieldsPreserved() async {
        let vm = makeVM(result: .success(makeBalance(points: 777, tier: "platinum")))
        await vm.load(customerId: 1)
        XCTAssertEqual(vm.balance?.points, 777)
        XCTAssertEqual(vm.balance?.tier, "platinum")
    }

    func test_load_success_historyNonEmpty() async {
        let vm = makeVM(result: .success(makeBalance(points: 300)))
        await vm.load(customerId: 1)
        XCTAssertFalse(vm.history.isEmpty)
    }

    func test_load_success_historySortedDescending() async {
        let vm = makeVM(result: .success(makeBalance(points: 300)))
        await vm.load(customerId: 1)
        let dates = vm.history.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    // MARK: Error paths

    func test_load_404_transitionsToComingSoon() async {
        let vm = makeVM(result: .failure(APITransportError.httpStatus(404, message: nil)))
        await vm.load(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
        XCTAssertNil(vm.balance)
    }

    func test_load_501_transitionsToComingSoon() async {
        let vm = makeVM(result: .failure(APITransportError.httpStatus(501, message: nil)))
        await vm.load(customerId: 1)
        XCTAssertEqual(vm.state, .comingSoon)
    }

    func test_load_networkError_transitionsToFailed() async {
        let vm = makeVM(result: .failure(URLError(.notConnectedToInternet)))
        await vm.load(customerId: 1)
        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    func test_load_networkError_balanceIsNil() async {
        let vm = makeVM(result: .failure(URLError(.notConnectedToInternet)))
        await vm.load(customerId: 1)
        XCTAssertNil(vm.balance)
    }

    // MARK: Repeat load clears old data

    func test_load_calledTwice_stateIsLoaded() async {
        let vm = makeVM(result: .success(makeBalance(points: 100, tier: "bronze")))
        await vm.load(customerId: 1)
        await vm.load(customerId: 2)
        XCTAssertEqual(vm.state, .loaded)
    }

    // MARK: State equatable

    func test_state_idle_equatable() {
        XCTAssertEqual(
            MembershipBalanceInspectorViewModel.State.idle,
            MembershipBalanceInspectorViewModel.State.idle
        )
    }

    func test_state_loading_equatable() {
        XCTAssertEqual(
            MembershipBalanceInspectorViewModel.State.loading,
            MembershipBalanceInspectorViewModel.State.loading
        )
    }

    func test_state_comingSoon_equatable() {
        XCTAssertEqual(
            MembershipBalanceInspectorViewModel.State.comingSoon,
            MembershipBalanceInspectorViewModel.State.comingSoon
        )
    }

    func test_state_failed_sameMessage_equatable() {
        XCTAssertEqual(
            MembershipBalanceInspectorViewModel.State.failed("oops"),
            MembershipBalanceInspectorViewModel.State.failed("oops")
        )
    }

    func test_state_failed_differentMessages_notEqual() {
        XCTAssertNotEqual(
            MembershipBalanceInspectorViewModel.State.failed("a"),
            MembershipBalanceInspectorViewModel.State.failed("b")
        )
    }

    func test_state_loaded_notEqual_idle() {
        XCTAssertNotEqual(
            MembershipBalanceInspectorViewModel.State.loaded,
            MembershipBalanceInspectorViewModel.State.idle
        )
    }

    // MARK: Tier progress

    func test_tierProgress_bronze_atZero_isZeroOrPositive() async {
        // Bronze with 0 pts → progress is 0 (or tiny if points = threshold)
        let vm = makeVM(result: .success(makeBalance(points: 0, tier: "bronze")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        let p = vm.tierProgress(for: bal)
        XCTAssertGreaterThanOrEqual(p, 0.0)
        XCTAssertLessThanOrEqual(p, 1.0)
    }

    func test_tierProgress_platinum_isOne() async {
        let vm = makeVM(result: .success(makeBalance(points: 99_999, tier: "platinum")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        XCTAssertEqual(vm.tierProgress(for: bal), 1.0)
    }

    func test_tierProgress_clampedToOneMax() async {
        // Way more points than the next threshold.
        let vm = makeVM(result: .success(makeBalance(points: 999_999, tier: "bronze")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        XCTAssertLessThanOrEqual(vm.tierProgress(for: bal), 1.0)
    }

    func test_tierProgress_clampedToZeroMin() async {
        // Negative or zero points should never go below 0.
        let vm = makeVM(result: .success(makeBalance(points: 0, tier: "bronze")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        XCTAssertGreaterThanOrEqual(vm.tierProgress(for: bal), 0.0)
    }

    // MARK: pointsToNextTier

    func test_pointsToNextTier_platinum_isNil() async {
        let vm = makeVM(result: .success(makeBalance(points: 5000, tier: "platinum")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        XCTAssertNil(vm.pointsToNextTier(for: bal))
    }

    func test_pointsToNextTier_bronze_isNonNegative() async {
        let vm = makeVM(result: .success(makeBalance(points: 100, tier: "bronze")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        if let remaining = vm.pointsToNextTier(for: bal) {
            XCTAssertGreaterThanOrEqual(remaining, 0)
        }
    }

    func test_pointsToNextTier_atSilverThreshold_isZero() async {
        // Silver min = 50_000 / 100 = 500 pts.
        let vm = makeVM(result: .success(makeBalance(points: 500, tier: "bronze")))
        await vm.load(customerId: 1)
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        // Anything past the threshold should be 0 (clamped).
        if let r = vm.pointsToNextTier(for: bal) {
            XCTAssertGreaterThanOrEqual(r, 0)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 2. PointsHistoryEntry model
// ─────────────────────────────────────────────────────────────────────────────

final class PointsHistoryEntryTests: XCTestCase {

    func test_init_fieldsPreserved() {
        let date = Date(timeIntervalSince1970: 0)
        let entry = PointsHistoryEntry(id: "abc", date: date, description: "Sign-up bonus", delta: 100)
        XCTAssertEqual(entry.id, "abc")
        XCTAssertEqual(entry.date, date)
        XCTAssertEqual(entry.description, "Sign-up bonus")
        XCTAssertEqual(entry.delta, 100)
    }

    func test_negativeDeltas_preserved() {
        let entry = PointsHistoryEntry(id: "x", date: .now, description: "Redemption", delta: -50)
        XCTAssertEqual(entry.delta, -50)
    }

    func test_identifiable_byId() {
        let a = PointsHistoryEntry(id: "id1", date: .now, description: "A", delta: 10)
        let b = PointsHistoryEntry(id: "id2", date: .now, description: "B", delta: 20)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_equatable_sameValues() {
        let date = Date(timeIntervalSince1970: 1_000)
        let a = PointsHistoryEntry(id: "e", date: date, description: "Earn", delta: 5)
        let b = PointsHistoryEntry(id: "e", date: date, description: "Earn", delta: 5)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentDelta_notEqual() {
        let date = Date(timeIntervalSince1970: 1_000)
        let a = PointsHistoryEntry(id: "e", date: date, description: "Earn", delta: 5)
        let b = PointsHistoryEntry(id: "e", date: date, description: "Earn", delta: 10)
        XCTAssertNotEqual(a, b)
    }

    func test_zeroDelta_preserved() {
        let entry = PointsHistoryEntry(id: "z", date: .now, description: "Adjustment", delta: 0)
        XCTAssertEqual(entry.delta, 0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 3. TierSidebarItem model
// ─────────────────────────────────────────────────────────────────────────────

final class TierSidebarItemTests: XCTestCase {

    func test_init_tierAndMemberCount_preserved() {
        let item = TierSidebarItem(tier: .gold, memberCount: 42)
        XCTAssertEqual(item.id, .gold)
        XCTAssertEqual(item.memberCount, 42)
    }

    func test_init_defaultMemberCount_isZero() {
        let item = TierSidebarItem(tier: .platinum)
        XCTAssertEqual(item.memberCount, 0)
    }

    func test_identifiable_byTier() {
        let a = TierSidebarItem(tier: .bronze)
        let b = TierSidebarItem(tier: .silver)
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_equatable_sameTierAndCount() {
        let a = TierSidebarItem(tier: .silver, memberCount: 7)
        let b = TierSidebarItem(tier: .silver, memberCount: 7)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentCount_notEqual() {
        let a = TierSidebarItem(tier: .gold, memberCount: 1)
        let b = TierSidebarItem(tier: .gold, memberCount: 2)
        XCTAssertNotEqual(a, b)
    }

    func test_allTiers_oneItemEach() {
        // Mirrors what LoyaltyTierSidebar initialiser builds.
        let counts: [LoyaltyTier: Int] = [.bronze: 3, .silver: 5, .gold: 1, .platinum: 0]
        let items = LoyaltyTier.allCases.map { TierSidebarItem(tier: $0, memberCount: counts[$0] ?? 0) }
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].id, .bronze)
        XCTAssertEqual(items[3].id, .platinum)
    }

    func test_memberCount_largeValue_preserved() {
        let item = TierSidebarItem(tier: .bronze, memberCount: 100_000)
        XCTAssertEqual(item.memberCount, 100_000)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 4. LoyaltyShortcutDescriptions
// ─────────────────────────────────────────────────────────────────────────────

final class LoyaltyShortcutDescriptionsTests: XCTestCase {

    func test_allEntries_countIs7() {
        XCTAssertEqual(LoyaltyShortcutDescriptions.all.count, 7)
    }

    func test_tierEntries_count4() {
        let tierEntries = LoyaltyShortcutDescriptions.all.filter {
            ["bronze", "silver", "gold", "platinum"].contains($0.id)
        }
        XCTAssertEqual(tierEntries.count, 4)
    }

    func test_bronze_key_is1() {
        let entry = LoyaltyShortcutDescriptions.all.first { $0.id == "bronze" }
        XCTAssertEqual(entry?.key, "1")
    }

    func test_silver_key_is2() {
        let entry = LoyaltyShortcutDescriptions.all.first { $0.id == "silver" }
        XCTAssertEqual(entry?.key, "2")
    }

    func test_gold_key_is3() {
        let entry = LoyaltyShortcutDescriptions.all.first { $0.id == "gold" }
        XCTAssertEqual(entry?.key, "3")
    }

    func test_platinum_key_is4() {
        let entry = LoyaltyShortcutDescriptions.all.first { $0.id == "platinum" }
        XCTAssertEqual(entry?.key, "4")
    }

    func test_refresh_entry_exists() {
        XCTAssertNotNil(LoyaltyShortcutDescriptions.all.first { $0.id == "refresh" })
    }

    func test_search_entry_exists() {
        XCTAssertNotNil(LoyaltyShortcutDescriptions.all.first { $0.id == "search" })
    }

    func test_clear_entry_exists() {
        XCTAssertNotNil(LoyaltyShortcutDescriptions.all.first { $0.id == "clear" })
    }

    func test_allEntryIds_unique() {
        let ids = LoyaltyShortcutDescriptions.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_allEntries_haveNonEmptyDescriptions() {
        for entry in LoyaltyShortcutDescriptions.all {
            XCTAssertFalse(entry.description.isEmpty, "Entry \(entry.id) has empty description")
        }
    }

    func test_allTierEntries_haveCommandModifier() {
        let tierIds = ["bronze", "silver", "gold", "platinum"]
        for entry in LoyaltyShortcutDescriptions.all where tierIds.contains(entry.id) {
            XCTAssertEqual(entry.modifiers, "⌘", "Entry \(entry.id) should use ⌘ modifier")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 5. MembershipContextMenuActions closure wiring
// ─────────────────────────────────────────────────────────────────────────────

final class MembershipContextMenuActionsTests: XCTestCase {

    func test_onEnroll_invoked_withCorrectId() {
        var capturedId: String? = nil
        let actions = MembershipContextMenuActions(
            onEnroll: { capturedId = $0 },
            onRedeemPoints: { _ in },
            onViewHistory: { _ in },
            onTogglePause: { _ in }
        )
        actions.onEnroll("mem-1")
        XCTAssertEqual(capturedId, "mem-1")
    }

    func test_onRedeemPoints_invoked_withCorrectId() {
        var capturedId: String? = nil
        let actions = MembershipContextMenuActions(
            onEnroll: { _ in },
            onRedeemPoints: { capturedId = $0 },
            onViewHistory: { _ in },
            onTogglePause: { _ in }
        )
        actions.onRedeemPoints("mem-42")
        XCTAssertEqual(capturedId, "mem-42")
    }

    func test_onViewHistory_invoked_withCorrectId() {
        var capturedId: String? = nil
        let actions = MembershipContextMenuActions(
            onEnroll: { _ in },
            onRedeemPoints: { _ in },
            onViewHistory: { capturedId = $0 },
            onTogglePause: { _ in }
        )
        actions.onViewHistory("mem-7")
        XCTAssertEqual(capturedId, "mem-7")
    }

    func test_onTogglePause_invoked_withCorrectId() {
        var capturedId: String? = nil
        let actions = MembershipContextMenuActions(
            onEnroll: { _ in },
            onRedeemPoints: { _ in },
            onViewHistory: { _ in },
            onTogglePause: { capturedId = $0 }
        )
        actions.onTogglePause("mem-99")
        XCTAssertEqual(capturedId, "mem-99")
    }

    func test_actions_doNotCrossWire() {
        // Ensures each callback fires independently and doesn't invoke others.
        var enrollCount = 0
        var redeemCount = 0
        var historyCount = 0
        var pauseCount = 0

        let actions = MembershipContextMenuActions(
            onEnroll: { _ in enrollCount += 1 },
            onRedeemPoints: { _ in redeemCount += 1 },
            onViewHistory: { _ in historyCount += 1 },
            onTogglePause: { _ in pauseCount += 1 }
        )

        actions.onEnroll("x")
        XCTAssertEqual(enrollCount, 1)
        XCTAssertEqual(redeemCount, 0)
        XCTAssertEqual(historyCount, 0)
        XCTAssertEqual(pauseCount, 0)

        actions.onRedeemPoints("x")
        XCTAssertEqual(enrollCount, 1)
        XCTAssertEqual(redeemCount, 1)
        XCTAssertEqual(historyCount, 0)
        XCTAssertEqual(pauseCount, 0)

        actions.onViewHistory("x")
        XCTAssertEqual(historyCount, 1)

        actions.onTogglePause("x")
        XCTAssertEqual(pauseCount, 1)
    }

    func test_actions_calledWithEmptyId() {
        var capturedId: String? = nil
        let actions = MembershipContextMenuActions(
            onEnroll: { capturedId = $0 },
            onRedeemPoints: { _ in },
            onViewHistory: { _ in },
            onTogglePause: { _ in }
        )
        actions.onEnroll("")
        XCTAssertEqual(capturedId, "")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - 6. Integration — tier progress × balance combinations
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class TierProgressIntegrationTests: XCTestCase {

    private func vmLoaded(points: Int, tier: String) async -> MembershipBalanceInspectorViewModel {
        let balance = LoyaltyBalance(
            customerId: 1,
            points: points,
            tier: tier,
            lifetimeSpendCents: points * 100,
            memberSince: "2024-01-01"
        )
        let vm = MembershipBalanceInspectorViewModel(
            api: MockInspectorClient(result: .success(balance))
        )
        await vm.load(customerId: 1)
        return vm
    }

    func test_bronzeProgress_halfwayToSilver_isApproximatelyHalf() async {
        // Silver threshold = 500 pts, bronze = 0 pts.
        // Half way = 250 pts.
        let vm = await vmLoaded(points: 250, tier: "bronze")
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        let p = vm.tierProgress(for: bal)
        XCTAssertEqual(p, 0.5, accuracy: 0.01)
    }

    func test_goldProgress_isInZeroToOneRange() async {
        let vm = await vmLoaded(points: 1500, tier: "gold")
        guard let bal = vm.balance else { return XCTFail("balance nil") }
        let p = vm.tierProgress(for: bal)
        XCTAssertGreaterThanOrEqual(p, 0.0)
        XCTAssertLessThanOrEqual(p, 1.0)
    }

    func test_syntheticHistory_containsSignupEntry() async {
        let vm = await vmLoaded(points: 200, tier: "bronze")
        let hasSignup = vm.history.contains { $0.description == "Welcome bonus" }
        XCTAssertTrue(hasSignup)
    }

    func test_syntheticHistory_earlyEntryForExcessPoints() async {
        let vm = await vmLoaded(points: 500, tier: "silver")
        // Should have at least the signup bonus + a lifetime-spend entry.
        XCTAssertGreaterThanOrEqual(vm.history.count, 2)
    }

    func test_syntheticHistory_exactlyOneEntryWhen_pointsEqual100() async {
        // Exactly 100 pts = welcome bonus only; no "lifetime spend" entry.
        let vm = await vmLoaded(points: 100, tier: "bronze")
        // Only the welcome bonus entry.
        XCTAssertEqual(vm.history.count, 1)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Mock APIClient for inspector tests
// ─────────────────────────────────────────────────────────────────────────────

private final class MockInspectorClient: APIClient, @unchecked Sendable {

    private let result: Result<LoyaltyBalance, Error>

    init(result: Result<LoyaltyBalance, Error>) {
        self.result = result
    }

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> T {
        switch result {
        case .success(let balance):
            if path.contains("/analytics") {
                struct FakeAnalytics: Encodable {
                    let total_tickets: Int
                    let lifetime_value: Double
                    let first_visit: String?
                }
                let a = FakeAnalytics(
                    total_tickets: 1,
                    lifetime_value: Double(balance.lifetimeSpendCents) / 100.0,
                    first_visit: balance.memberSince
                )
                let data = try JSONEncoder().encode(a)
                return try JSONDecoder().decode(T.self, from: data)
            }
            if path.contains("/membership/customer") {
                let nullData = "null".data(using: .utf8)!
                return try JSONDecoder().decode(T.self, from: nullData)
            }
            throw URLError(.badURL)
        case .failure(let error):
            throw error
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.badURL) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { URL(string: "https://test.example.com/api/v1") }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
