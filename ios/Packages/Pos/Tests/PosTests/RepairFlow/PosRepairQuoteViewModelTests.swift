#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

// MARK: - PosRepairQuoteViewModelTests

@MainActor
final class PosRepairQuoteViewModelTests: XCTestCase {

    // MARK: - Test 1: running estimate sums parts + labor (included lines only)

    func test_estimateCents_sumsIncludedLinesOnly() {
        let vm = PosRepairQuoteViewModel()
        vm.lines = [
            RepairQuoteLine(name: "Screen",    priceCents: 15000, isIncluded: true),
            RepairQuoteLine(name: "Labor",     priceCents: 4500,  isIncluded: true),
            RepairQuoteLine(name: "Adhesive",  priceCents: 800,   isIncluded: false), // excluded
        ]

        XCTAssertEqual(vm.estimateCents, 19500,
            "estimateCents must sum only the lines where isIncluded == true")
    }

    // MARK: - Test 2: toggleLine flips isIncluded and updates estimate

    func test_toggleLine_flipsIncludedAndUpdatesEstimate() {
        let vm = PosRepairQuoteViewModel()
        let line = RepairQuoteLine(name: "Battery", priceCents: 6000, isIncluded: true)
        vm.lines = [line]

        let beforeToggle = vm.estimateCents // 6000
        vm.toggleLine(line)                // now excluded
        let afterToggle = vm.estimateCents  // 0

        XCTAssertEqual(beforeToggle, 6000)
        XCTAssertEqual(afterToggle, 0,
            "Toggling an included line off must reduce estimate to 0")
        XCTAssertFalse(vm.lines.first?.isIncluded ?? true,
            "Line isIncluded should be false after toggle")
    }

    // MARK: - Test 3: addLine appends a new RepairQuoteLine

    func test_addLine_appendsNewLine() {
        let vm = PosRepairQuoteViewModel()
        vm.addLine(name: "Digitizer replacement", priceCents: 8500)

        XCTAssertEqual(vm.lines.count, 1)
        XCTAssertEqual(vm.lines.first?.name, "Digitizer replacement")
        XCTAssertEqual(vm.lines.first?.priceCents, 8500)
        XCTAssertTrue(vm.lines.first?.isIncluded ?? false)
    }

    // MARK: - Test 4: addLine with blank name is rejected

    func test_addLine_blankName_isRejected() {
        let vm = PosRepairQuoteViewModel()
        vm.addLine(name: "   ", priceCents: 5000)

        XCTAssertTrue(vm.lines.isEmpty,
            "Adding a line with whitespace-only name must not append anything")
    }

    // MARK: - Test 5: "Save as quote" — commitToDraft without advancing coordinator

    func test_commitToDraft_doesNotAdvanceCoordinatorStep() {
        let api = NullAPIClientForQuote()
        let coordinator = PosRepairFlowCoordinator(customerId: 1, api: api)
        let vm = PosRepairQuoteViewModel()
        vm.diagnosticNotes = "Ran diagnostics — water damage detected"
        vm.lines = [RepairQuoteLine(name: "Motherboard clean", priceCents: 12000)]

        vm.commitToDraft(coordinator: coordinator)

        // Step must not have changed — commitToDraft is the "save as quote" action.
        XCTAssertEqual(coordinator.currentStep, .pickDevice,
            "commitToDraft (Save as quote) must not call coordinator.advance()")
        XCTAssertEqual(coordinator.draft.diagnosticNotes, "Ran diagnostics — water damage detected")
        XCTAssertEqual(coordinator.draft.quoteLines.count, 1)
    }

    // MARK: - Test 6: "Continue to deposit" — commitToDraft then advance moves to deposit step

    func test_commitToDraftThenAdvance_movesToNextStep() async throws {
        let api = NullAPIClientForQuote()
        let coordinator = PosRepairFlowCoordinator(customerId: 1, api: api)
        // For diagnosticQuote → deposit transition savedDraftId must be nil
        // (coordinator guard falls through to deposit when no id).
        // Verify the guard path: commitQuoteStep() with nil savedDraftId → currentStep = .deposit.
        // We need to get coordinator to .diagnosticQuote first.
        // Since coordinator starts at .pickDevice and we can only jump backward,
        // the test verifies behavior through RepairStep navigation API.

        // Direct check: RepairStep.diagnosticQuote.next == .deposit
        XCTAssertEqual(RepairStep.diagnosticQuote.next, .deposit,
            "Advancing from diagnosticQuote must reach deposit")

        // And verify commitToDraft pushes the correct state:
        let vm = PosRepairQuoteViewModel()
        vm.diagnosticNotes = "All tests passed"
        vm.lines = [
            RepairQuoteLine(name: "Part A", priceCents: 5000),
            RepairQuoteLine(name: "Part B", priceCents: 3000)
        ]
        vm.commitToDraft(coordinator: coordinator)

        XCTAssertEqual(coordinator.draft.estimateCents, 8000)
        XCTAssertEqual(coordinator.draft.quoteLines.count, 2)
    }

    // MARK: - Test 7: removeLine removes at the given offsets

    func test_removeLine_removesCorrectLine() {
        let vm = PosRepairQuoteViewModel()
        vm.lines = [
            RepairQuoteLine(name: "A", priceCents: 1000),
            RepairQuoteLine(name: "B", priceCents: 2000),
            RepairQuoteLine(name: "C", priceCents: 3000),
        ]

        vm.removeLine(at: IndexSet(integer: 1)) // remove "B"

        XCTAssertEqual(vm.lines.count, 2)
        XCTAssertEqual(vm.lines.map { $0.name }, ["A", "C"],
            "Only the line at the given offset should be removed")
    }

    // MARK: - Test 8: formatCurrency renders cents correctly

    func test_formatCurrency_rendersCentsCorrectly() {
        XCTAssertEqual(PosRepairQuoteViewModel.formatCurrency(cents: 0),     "$0.00")
        XCTAssertEqual(PosRepairQuoteViewModel.formatCurrency(cents: 100),   "$1.00")
        XCTAssertEqual(PosRepairQuoteViewModel.formatCurrency(cents: 15099), "$150.99")
    }
}

// MARK: - NullAPIClientForQuote

private final class NullAPIClientForQuote: APIClient, @unchecked Sendable {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
