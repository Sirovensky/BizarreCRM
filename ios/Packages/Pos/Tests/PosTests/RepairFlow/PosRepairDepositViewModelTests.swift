#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

// MARK: - PosRepairDepositViewModelTests
//
// Tests cover TicketDraft deposit helpers, RepairDepositCoordinator behaviour,
// and the end-to-end deposit step wiring (setDepositCents + advance).

@MainActor
final class PosRepairDepositViewModelTests: XCTestCase {

    // MARK: - Test 1: default deposit is 15% of estimate (TicketDraft.suggestedDepositCents)

    func test_suggestedDepositCents_is15PercentOfEstimate() {
        let lines = [
            RepairQuoteLine(name: "Screen replacement", priceCents: 20000, isIncluded: true),
        ]
        let draft = TicketDraft(customerId: 1)
            .withQuote(diagnosticNotes: "", lines: lines)

        // 15% of 20000 = 3000
        XCTAssertEqual(draft.suggestedDepositCents, 3000,
            "suggestedDepositCents must be 15%% of estimateCents, rounded")
    }

    // MARK: - Test 2: suggested deposit rounds correctly

    func test_suggestedDepositCents_roundsToNearestCent() {
        // 15% of 10001 = 1500.15 → rounds to 1500
        let lines = [RepairQuoteLine(name: "Part", priceCents: 10001, isIncluded: true)]
        let draft = TicketDraft(customerId: 1).withQuote(diagnosticNotes: "", lines: lines)
        let expected = Int((Double(10001) * 0.15).rounded()) // 1500
        XCTAssertEqual(draft.suggestedDepositCents, expected)
    }

    // MARK: - Test 3: custom deposit clamps to ≤ estimate (isDepositStepValid)

    func test_depositCents_greaterThanEstimate_isInvalid() {
        let lines = [RepairQuoteLine(name: "Labor", priceCents: 5000, isIncluded: true)]
        let draft = TicketDraft(customerId: 1)
            .withQuote(diagnosticNotes: "", lines: lines)
            .withDeposit(cents: 9999) // more than the 5000 estimate

        XCTAssertFalse(draft.isDepositStepValid,
            "Deposit exceeding estimate must be invalid")
    }

    // MARK: - Test 4: deposit equal to estimate is valid

    func test_depositCents_equalToEstimate_isValid() {
        let lines = [RepairQuoteLine(name: "Labor", priceCents: 5000, isIncluded: true)]
        let draft = TicketDraft(customerId: 1)
            .withQuote(diagnosticNotes: "", lines: lines)
            .withDeposit(cents: 5000)

        XCTAssertTrue(draft.isDepositStepValid,
            "Deposit exactly equal to estimate must be valid")
    }

    // MARK: - Test 5: deposit zero is valid (optional deposit policy)

    func test_depositCents_zero_isValid() {
        let draft = TicketDraft(customerId: 1)
        XCTAssertTrue(draft.isDepositStepValid,
            "Zero deposit must be valid (cashier may waive it)")
    }

    // MARK: - Test 6: balanceDueCents = estimate − deposit, floored at 0

    func test_balanceDueCents_isEstimateMinusDeposit() {
        let lines = [RepairQuoteLine(name: "Screen", priceCents: 10000, isIncluded: true)]
        let draft = TicketDraft(customerId: 1)
            .withQuote(diagnosticNotes: "", lines: lines)
            .withDeposit(cents: 2000)

        XCTAssertEqual(draft.balanceDueCents, 8000,
            "Balance due must be estimate minus deposit")
    }

    func test_balanceDueCents_clampedAtZero() {
        let lines = [RepairQuoteLine(name: "Part", priceCents: 1000, isIncluded: true)]
        let draft = TicketDraft(customerId: 1)
            .withQuote(diagnosticNotes: "", lines: lines)
            .withDeposit(cents: 3000) // over-deposit

        XCTAssertEqual(draft.balanceDueCents, 0,
            "balanceDueCents must never go negative (clamp at 0)")
    }

    // MARK: - Test 7: RepairDepositCoordinator – depositHeaderText reflects amount

    func test_repairDepositCoordinator_depositHeaderText() {
        let coordinator = RepairDepositCoordinator(totalCents: 30000, defaultDepositCents: 4500)

        // "Deposit $45.00 of $300.00"
        let header = coordinator.depositHeaderText
        XCTAssertTrue(header.contains("$45.00"), "Header should contain formatted deposit amount")
        XCTAssertTrue(header.contains("$300.00"), "Header should contain formatted total amount")
    }

    // MARK: - Test 8: RepairDepositCoordinator – balanceFooterText is correct

    func test_repairDepositCoordinator_balanceFooterText() {
        let coordinator = RepairDepositCoordinator(totalCents: 30000, defaultDepositCents: 4500)
        let footer = coordinator.balanceFooterText

        // balance = 30000 − 4500 = 25500 → $255.00
        XCTAssertTrue(footer.contains("$255.00"),
            "balanceFooterText must display the balance due after deposit")
    }

    // MARK: - Test 9: on confirm, balanceDue updates and onTendered fires

    func test_confirmDeposit_callsOnTenderedWithDepositCents() {
        let depositCoordinator = RepairDepositCoordinator(
            totalCents: 20000,
            defaultDepositCents: 3000
        )
        var tenderedCents: Int?
        depositCoordinator.onTendered = { tenderedCents = $0 }

        depositCoordinator.confirmDeposit()

        XCTAssertNotNil(tenderedCents, "onTendered must be called after confirmDeposit()")
        XCTAssertEqual(tenderedCents, 3000, "onTendered must receive the current depositCents")
        XCTAssertTrue(depositCoordinator.isComplete)
        XCTAssertFalse(depositCoordinator.isProcessing)
    }

    // MARK: - Test 10: confirmDeposit with zero deposit surfaces an error

    func test_confirmDeposit_zeroDeposit_setsError() {
        let depositCoordinator = RepairDepositCoordinator(
            totalCents: 20000,
            defaultDepositCents: 0   // zero
        )

        depositCoordinator.confirmDeposit()

        XCTAssertNotNil(depositCoordinator.errorMessage,
            "Confirming a zero deposit must surface an error message")
        XCTAssertFalse(depositCoordinator.isComplete,
            "isComplete must remain false when deposit is zero")
    }

    // MARK: - Test 11: setDepositCents propagates through coordinator draft

    func test_setDepositCents_propagatesThroughCoordinatorDraft() {
        let api = NullAPIClientForDeposit()
        let coordinator = PosRepairFlowCoordinator(customerId: 3, api: api)

        coordinator.setDepositCents(7500)

        XCTAssertEqual(coordinator.draft.depositCents, 7500,
            "setDepositCents must update the coordinator's draft immutably")
    }
}

// MARK: - NullAPIClientForDeposit

private final class NullAPIClientForDeposit: APIClient, @unchecked Sendable {
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
