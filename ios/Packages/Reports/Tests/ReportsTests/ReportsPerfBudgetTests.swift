import XCTest
@testable import Reports

final class ReportsPerfBudgetTests: XCTestCase {

    func test_emptySnapshot_returnsZeroes() async {
        let budget = ReportsPerfBudget(budgetSeconds: 2.0, windowSize: 50)
        let snap = await budget.snapshot()
        XCTAssertEqual(snap.count, 0)
        XCTAssertEqual(snap.p95, 0)
        XCTAssertEqual(snap.budget, 2.0)
        XCTAssertFalse(snap.isOverBudget)
    }

    func test_recordsSamples_andComputesP95() async {
        let budget = ReportsPerfBudget(budgetSeconds: 2.0, windowSize: 50)
        for s in [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 5.0] {
            await budget.record(label: "loadAll", seconds: s)
        }
        let snap = await budget.snapshot()
        XCTAssertEqual(snap.count, 10)
        // Nearest-rank p95 of 10 samples → index ceil(0.95*10)-1 = 9 → 5.0
        XCTAssertEqual(snap.p95, 5.0, accuracy: 0.0001)
        XCTAssertEqual(snap.max, 5.0, accuracy: 0.0001)
        XCTAssertTrue(snap.isOverBudget)
        XCTAssertEqual(snap.overBudgetCount, 1)
    }

    func test_windowEvicts_oldestSamples() async {
        let budget = ReportsPerfBudget(budgetSeconds: 2.0, windowSize: 3)
        await budget.record(label: "x", seconds: 10.0)
        await budget.record(label: "x", seconds: 0.1)
        await budget.record(label: "x", seconds: 0.1)
        await budget.record(label: "x", seconds: 0.1) // evicts 10.0
        let snap = await budget.snapshot()
        XCTAssertEqual(snap.count, 3)
        XCTAssertEqual(snap.max, 0.1, accuracy: 0.0001)
        XCTAssertFalse(snap.isOverBudget)
    }

    func test_beginEnd_roundtrip_recordsPositiveDuration() async {
        let budget = ReportsPerfBudget(budgetSeconds: 2.0, windowSize: 10)
        let token = budget.begin(label: "loadAll")
        try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        await budget.end(token)
        let snap = await budget.snapshot()
        XCTAssertEqual(snap.count, 1)
        XCTAssertGreaterThan(snap.max, 0)
        XCTAssertLessThan(snap.max, 1.0)
    }

    func test_reset_clearsAllSamples() async {
        let budget = ReportsPerfBudget(budgetSeconds: 2.0, windowSize: 10)
        await budget.record(label: "x", seconds: 3.0)
        await budget.reset()
        let snap = await budget.snapshot()
        XCTAssertEqual(snap.count, 0)
        XCTAssertEqual(snap.overBudgetCount, 0)
    }
}
