import XCTest
@testable import Employees
import Networking

// MARK: - MockGoalsRepository

final class MockGoalsRepository: GoalsRepository, @unchecked Sendable {
    var stubbedGoals: [Goal] = []
    var shouldThrow: Bool = false
    var deletedIds: [String] = []
    var createdRequests: [CreateGoalRequest] = []

    func listGoals(userId: String?, teamId: String?) async throws -> [Goal] {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return stubbedGoals
    }

    func createGoal(_ req: CreateGoalRequest) async throws -> Goal {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        createdRequests.append(req)
        let goal = Goal(
            id: "new-\(createdRequests.count)",
            goalType: req.goalType,
            targetValue: req.targetValue,
            period: req.period,
            startDate: req.startDate,
            endDate: req.endDate
        )
        return goal
    }

    func updateGoal(id: String, _ req: UpdateGoalRequest) async throws -> Goal {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return stubbedGoals.first { $0.id == id } ?? Goal(
            id: id, goalType: .dailyRevenue, targetValue: 100,
            period: .daily, startDate: Date(), endDate: Date()
        )
    }

    func deleteGoal(id: String) async throws {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        deletedIds.append(id)
    }
}

// MARK: - GoalListViewModelTests

@MainActor
final class GoalListViewModelTests: XCTestCase {

    private func makeGoal(id: String = "g1") -> Goal {
        Goal(
            id: id,
            goalType: .dailyRevenue,
            targetValue: 1000,
            currentValue: 500,
            period: .daily,
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400)
        )
    }

    func test_load_populatesGoals() async {
        let repo = MockGoalsRepository()
        repo.stubbedGoals = [makeGoal(id: "g1"), makeGoal(id: "g2")]
        let vm = GoalListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.goals.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsErrorOnFailure() async {
        let repo = MockGoalsRepository()
        repo.shouldThrow = true
        let vm = GoalListViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.goals.isEmpty)
    }

    func test_delete_removesFromList() async {
        let repo = MockGoalsRepository()
        let goal = makeGoal(id: "del-me")
        repo.stubbedGoals = [goal]
        let vm = GoalListViewModel(repo: repo)
        await vm.load()
        await vm.delete(goal: goal)
        XCTAssertTrue(vm.goals.isEmpty)
        XCTAssertTrue(repo.deletedIds.contains("del-me"))
    }

    func test_append_addsGoal() {
        let repo = MockGoalsRepository()
        let vm = GoalListViewModel(repo: repo)
        let goal = makeGoal(id: "appended")
        vm.append(goal)
        XCTAssertEqual(vm.goals.count, 1)
        XCTAssertEqual(vm.goals.first?.id, "appended")
    }

    func test_isLoading_trueWhileLoadingEmpty() async {
        let repo = MockGoalsRepository()
        let vm = GoalListViewModel(repo: repo)
        // Before load, not loading
        XCTAssertFalse(vm.isLoading)
    }
}

// MARK: - GoalEditorViewModelTests

@MainActor
final class GoalEditorViewModelTests: XCTestCase {

    func test_save_callsCreateGoal() async {
        let repo = MockGoalsRepository()
        var savedGoal: Goal?
        let vm = GoalEditorViewModel(repo: repo) { goal in
            savedGoal = goal
        }
        vm.targetValue = 500
        vm.goalType = .weeklyTicketCount
        vm.period = .weekly
        vm.startDate = Date()
        vm.endDate = Date().addingTimeInterval(86400 * 7)

        await vm.save()

        XCTAssertNotNil(savedGoal)
        XCTAssertFalse(repo.createdRequests.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func test_save_failsWithZeroTarget() async {
        let repo = MockGoalsRepository()
        let vm = GoalEditorViewModel(repo: repo) { _ in }
        vm.targetValue = 0
        await vm.save()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_save_failsWhenEndBeforeStart() async {
        let repo = MockGoalsRepository()
        let vm = GoalEditorViewModel(repo: repo) { _ in }
        vm.targetValue = 100
        vm.startDate = Date()
        vm.endDate = Date().addingTimeInterval(-86400)
        await vm.save()
        XCTAssertNotNil(vm.errorMessage)
    }
}
