#if canImport(UIKit)
import XCTest
@testable import Pos

// MARK: - PosRepairSymptomViewModelTests

@MainActor
final class PosRepairSymptomViewModelTests: XCTestCase {

    // MARK: - Test 1: empty symptomText blocks Continue (isValid = false)

    func test_emptySymptomText_blocksAdvance() {
        let vm = PosRepairSymptomViewModel()

        XCTAssertFalse(vm.isValid,
            "isValid must be false when symptomText is empty")
    }

    // MARK: - Test 2: whitespace-only symptomText also blocks Continue

    func test_whitespaceOnlySymptomText_blocksAdvance() {
        let vm = PosRepairSymptomViewModel()
        vm.symptomText = "   \n\t  "

        XCTAssertFalse(vm.isValid,
            "isValid must be false when symptomText contains only whitespace")
    }

    // MARK: - Test 3: non-empty symptomText unblocks Continue (isValid = true)

    func test_nonEmptySymptomText_unblocksContinue() {
        let vm = PosRepairSymptomViewModel()
        vm.symptomText = "Screen is cracked."

        XCTAssertTrue(vm.isValid,
            "isValid must be true when symptomText has non-whitespace content")
    }

    // MARK: - Test 4: quick-pick chip pre-fills by toggling into selectedChips

    func test_quickPickChip_prefillsSelectedChips() {
        let vm = PosRepairSymptomViewModel()
        XCTAssertTrue(vm.selectedChips.isEmpty)

        vm.toggleChip(.screenCracked)

        XCTAssertTrue(vm.selectedChips.contains(.screenCracked),
            "toggleChip should insert the chip when it is not already selected")
    }

    // MARK: - Test 5: toggling a chip twice removes it

    func test_toggleChip_twice_removesChip() {
        let vm = PosRepairSymptomViewModel()
        vm.toggleChip(.battery)
        XCTAssertTrue(vm.selectedChips.contains(.battery))

        vm.toggleChip(.battery)

        XCTAssertFalse(vm.selectedChips.contains(.battery),
            "Toggling an already-selected chip should deselect it")
    }

    // MARK: - Test 6: progress bar value for describeIssue step is 50%

    func test_describeIssueStepProgressPercent_is50() {
        XCTAssertEqual(RepairStep.describeIssue.progressPercent, 50,
            "describeIssue step progress must be 50%%")
    }

    // MARK: - Test 7: progress bar advances 25% per step

    func test_progressPercent_advancesBy25PerStep() {
        let steps = RepairStep.allCases
        let percents = steps.map { $0.progressPercent }

        XCTAssertEqual(percents, [25, 50, 75, 100],
            "Steps must progress at 25%%, 50%%, 75%%, 100%%")

        for i in 1..<steps.count {
            XCTAssertEqual(
                percents[i] - percents[i - 1], 25,
                "Progress must increase by exactly 25%% per step"
            )
        }
    }

    // MARK: - Test 8: commitToDraft pushes all fields into coordinator draft

    func test_commitToDraft_pushesSymptomsIntoCoordinator() async throws {
        let api = NullAPIClient()
        let coordinator = PosRepairFlowCoordinator(customerId: 5, api: api)

        let vm = PosRepairSymptomViewModel()
        vm.symptomText = "Won't charge"
        vm.selectedCondition = .poor
        vm.selectedChips = [.wontCharge, .battery]
        vm.internalNotes = "Customer dropped it in water"

        vm.commitToDraft(coordinator: coordinator)

        XCTAssertEqual(coordinator.draft.symptomText, "Won't charge")
        XCTAssertEqual(coordinator.draft.condition, .poor)
        XCTAssertTrue(coordinator.draft.quickChips.contains(.wontCharge))
        XCTAssertTrue(coordinator.draft.quickChips.contains(.battery))
        XCTAssertEqual(coordinator.draft.internalNotes, "Customer dropped it in water")
    }
}

// MARK: - NullAPIClient (no network, used as a dependency stub)

/// APIClient that never makes real network calls.  Suitable for coordinator
/// instances that won't be asked to advance through network steps.
private final class NullAPIClient: APIClient, @unchecked Sendable {
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
