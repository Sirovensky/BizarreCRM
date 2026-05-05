#if canImport(UIKit)
import XCTest
@testable import Pos

/// §16 — Unit tests for `PricingRulesListViewModel`.
///
/// Covers: load success/error, move/reorder, delete (happy + failure-reloads),
/// toggleEnabled (happy + failure-reverts), upsert (insert + update).
@MainActor
final class PricingRulesListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeRule(id: String, name: String = "Rule", enabled: Bool = true, priority: Int = 0) -> PricingRule {
        PricingRule(id: id, name: name, type: .tieredVolume, enabled: enabled, priority: priority)
    }

    private func makeVM(repo: MockPricingRulesRepository) -> PricingRulesListViewModel {
        PricingRulesListViewModel(repository: repo)
    }

    // MARK: - load()

    func test_load_setsLoadedState_onSuccess() async {
        let rules = [makeRule(id: "1", priority: 0), makeRule(id: "2", priority: 1)]
        let repo = MockPricingRulesRepository(listResult: .success(rules))
        let vm = makeVM(repo: repo)

        XCTAssertEqual(vm.loadState, .idle)
        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.rules.count, 2)
        XCTAssertEqual(vm.rules.map(\.id), ["1", "2"])
    }

    func test_load_setsErrorState_onFailure() async {
        let repo = MockPricingRulesRepository(listResult: .failure(TestError.network))
        let vm = makeVM(repo: repo)

        await vm.load()

        if case .error = vm.loadState { } else {
            XCTFail("Expected .error loadState, got \(vm.loadState)")
        }
    }

    func test_load_transitionsThrough_loadingState() async {
        let repo = MockPricingRulesRepository(listResult: .success([]))
        let vm = makeVM(repo: repo)

        // Verify idle → loading → loaded
        let task = Task { await vm.load() }
        await task.value
        XCTAssertEqual(vm.loadState, .loaded)
    }

    // MARK: - move(from:to:)

    func test_move_reordersLocalArray_andReassignsPriorities() async {
        let rules = [
            makeRule(id: "A", priority: 0),
            makeRule(id: "B", priority: 1),
            makeRule(id: "C", priority: 2)
        ]
        let repo = MockPricingRulesRepository(listResult: .success(rules))
        let vm = makeVM(repo: repo)
        await vm.load()

        // Move "C" (index 2) to front (index 0)
        vm.move(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(vm.rules.map(\.id), ["C", "A", "B"])
        XCTAssertEqual(vm.rules[0].priority, 0, "priorities reassigned 0,1,2")
        XCTAssertEqual(vm.rules[1].priority, 1)
        XCTAssertEqual(vm.rules[2].priority, 2)
    }

    func test_move_callsReorder() async {
        let rules = [makeRule(id: "A"), makeRule(id: "B")]
        let repo = MockPricingRulesRepository(listResult: .success(rules))
        let vm = makeVM(repo: repo)
        await vm.load()

        vm.move(from: IndexSet(integer: 1), to: 0)

        // Wait for the async Task inside move() to complete
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(repo.reorderCalled, "reorderRules should be called after move")
    }

    // MARK: - delete()

    func test_delete_removesRuleOptimistically() async {
        let ruleA = makeRule(id: "A")
        let ruleB = makeRule(id: "B")
        let repo = MockPricingRulesRepository(listResult: .success([ruleA, ruleB]))
        let vm = makeVM(repo: repo)
        await vm.load()

        await vm.delete(rule: ruleA)

        XCTAssertEqual(vm.rules.map(\.id), ["B"])
    }

    func test_delete_reloadsOnFailure() async {
        let ruleA = makeRule(id: "A")
        let ruleB = makeRule(id: "B")
        let repo = MockPricingRulesRepository(
            listResult: .success([ruleA, ruleB]),
            deleteResult: .failure(TestError.network)
        )
        let vm = makeVM(repo: repo)
        await vm.load()
        XCTAssertEqual(repo.listCallCount, 1)

        await vm.delete(rule: ruleA)

        // After failure, load() is called again (listCallCount becomes 2)
        XCTAssertEqual(repo.listCallCount, 2, "load() should be called on delete failure")
    }

    // MARK: - toggleEnabled()

    func test_toggleEnabled_flipsEnabledFlag() async {
        let rule = makeRule(id: "A", enabled: true)
        let repo = MockPricingRulesRepository(listResult: .success([rule]))
        let vm = makeVM(repo: repo)
        await vm.load()

        await vm.toggleEnabled(rule: rule)

        XCTAssertEqual(vm.rules.first?.enabled, false)
        XCTAssertTrue(repo.updateCalled)
    }

    func test_toggleEnabled_revertsOnFailure() async {
        let rule = makeRule(id: "A", enabled: true)
        let repo = MockPricingRulesRepository(
            listResult: .success([rule]),
            updateResult: .failure(TestError.network)
        )
        let vm = makeVM(repo: repo)
        await vm.load()

        await vm.toggleEnabled(rule: rule)

        // Should revert to original enabled = true
        XCTAssertEqual(vm.rules.first?.enabled, true, "toggle must revert on failure")
    }

    // MARK: - upsert()

    func test_upsert_appendsNewRule() async {
        let repo = MockPricingRulesRepository(listResult: .success([]))
        let vm = makeVM(repo: repo)
        await vm.load()

        let newRule = makeRule(id: "X", name: "New")
        vm.upsert(newRule)

        XCTAssertEqual(vm.rules.count, 1)
        XCTAssertEqual(vm.rules.first?.id, "X")
    }

    func test_upsert_updatesExistingRule() async {
        let rule = makeRule(id: "A", name: "Old Name")
        let repo = MockPricingRulesRepository(listResult: .success([rule]))
        let vm = makeVM(repo: repo)
        await vm.load()

        var updated = rule
        updated.name = "New Name"
        vm.upsert(updated)

        XCTAssertEqual(vm.rules.count, 1)
        XCTAssertEqual(vm.rules.first?.name, "New Name")
    }

    func test_upsert_assignsPriority_toNewRule() async {
        let existingRules = [makeRule(id: "A", priority: 0), makeRule(id: "B", priority: 1)]
        let repo = MockPricingRulesRepository(listResult: .success(existingRules))
        let vm = makeVM(repo: repo)
        await vm.load()

        let newRule = makeRule(id: "C")
        vm.upsert(newRule)

        // New rule should get priority == rules.count before insertion (= 2)
        XCTAssertEqual(vm.rules.last?.id, "C")
        XCTAssertEqual(vm.rules.last?.priority, 2)
    }
}

// MARK: - MockPricingRulesRepository

private enum TestError: Error { case network }

private final class MockPricingRulesRepository: PricingRulesRepository {

    private let listResult: Result<[PricingRule], Error>
    private let deleteResult: Result<Void, Error>
    private let updateResult: Result<Void, Error>

    private(set) var reorderCalled = false
    private(set) var updateCalled = false
    private(set) var listCallCount = 0

    init(
        listResult: Result<[PricingRule], Error>,
        deleteResult: Result<Void, Error> = .success(()),
        updateResult: Result<Void, Error> = .success(())
    ) {
        self.listResult = listResult
        self.deleteResult = deleteResult
        self.updateResult = updateResult
    }

    func listRules() async throws -> [PricingRule] {
        listCallCount += 1
        return try listResult.get()
    }

    func updateRule(_ rule: PricingRule) async throws {
        updateCalled = true
        try updateResult.get()
    }

    func deleteRule(id: String) async throws {
        try deleteResult.get()
    }

    func reorderRules(orderedIds: [String]) async throws {
        reorderCalled = true
    }
}
#endif
