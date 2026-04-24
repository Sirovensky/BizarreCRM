import XCTest
import Networking
@testable import Pos

/// Tests for `PosTerminalService` conformances.
///
/// Uses `SimulatedPosTerminalService` (a test double) and `StubPosTerminalService`
/// (the production no-op) to verify result handling without network calls.
final class PosTerminalServiceTests: XCTestCase {

    // MARK: - StubPosTerminalService

    func test_stub_alwaysReturnsDeclined() async throws {
        let stub = StubPosTerminalService()
        let result = try await stub.charge(
            invoiceId: 1,
            amountCents: 1000,
            idempotencyKey: "key-1",
            tipCents: 0
        )
        guard case .declined(let reason) = result else {
            XCTFail("Expected .declined, got \(result)")
            return
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func test_stub_isNotApproved() async throws {
        let stub = StubPosTerminalService()
        let result = try await stub.charge(invoiceId: 2, amountCents: 500, idempotencyKey: "k2", tipCents: 0)
        XCTAssertFalse(result.isApproved)
    }

    // MARK: - PosTerminalResult

    func test_approved_isApproved_true() {
        let r = PosTerminalResult.approved(transactionId: "txn123", cardLabel: "Visa ••••1234", authCode: "AB1234")
        XCTAssertTrue(r.isApproved)
    }

    func test_declined_isApproved_false() {
        let r = PosTerminalResult.declined(reason: "Insufficient funds")
        XCTAssertFalse(r.isApproved)
    }

    func test_pendingReconciliation_isApproved_false() {
        let r = PosTerminalResult.pendingReconciliation(transactionRef: "ref-abc")
        XCTAssertFalse(r.isApproved)
    }

    func test_approved_displayMessage_includesCardAndAuth() {
        let r = PosTerminalResult.approved(transactionId: nil, cardLabel: "Mastercard ••••5678", authCode: "XY99")
        XCTAssertTrue(r.displayMessage.contains("Mastercard ••••5678"))
        XCTAssertTrue(r.displayMessage.contains("XY99"))
    }

    func test_approved_noCardNoAuth_displayMessage_isApproved() {
        let r = PosTerminalResult.approved(transactionId: nil, cardLabel: nil, authCode: nil)
        XCTAssertEqual(r.displayMessage, "Approved")
    }

    func test_declined_displayMessage_includesReason() {
        let r = PosTerminalResult.declined(reason: "Card expired")
        XCTAssertTrue(r.displayMessage.contains("Card expired"))
    }

    func test_pendingReconciliation_displayMessage_mentionsVerify() {
        let r = PosTerminalResult.pendingReconciliation(transactionRef: nil)
        XCTAssertTrue(r.displayMessage.lowercased().contains("verify") ||
                      r.displayMessage.lowercased().contains("unknown"))
    }
}

// MARK: - SimulatedPosTerminalService (test double)

/// Configurable terminal service for unit tests.
/// Not exported — lives only in the test target.
private final class SimulatedPosTerminalService: PosTerminalService, @unchecked Sendable {
    var stubbedResult: PosTerminalResult

    init(result: PosTerminalResult) {
        self.stubbedResult = result
    }

    func charge(
        invoiceId: Int64,
        amountCents: Int,
        idempotencyKey: String,
        tipCents: Int
    ) async throws -> PosTerminalResult {
        stubbedResult
    }
}

// MARK: - Simulated approval tests

final class SimulatedPosTerminalServiceTests: XCTestCase {

    func test_simulated_approved_returnsApproved() async throws {
        let svc = SimulatedPosTerminalService(result: .approved(
            transactionId: "sim-001",
            cardLabel: "Visa ••••0001",
            authCode: "SIM"
        ))
        let result = try await svc.charge(invoiceId: 99, amountCents: 5000, idempotencyKey: "k", tipCents: 0)
        XCTAssertTrue(result.isApproved)
        if case .approved(let txn, let card, _) = result {
            XCTAssertEqual(txn, "sim-001")
            XCTAssertEqual(card, "Visa ••••0001")
        } else {
            XCTFail("Expected .approved")
        }
    }

    func test_simulated_pendingReconciliation() async throws {
        let svc = SimulatedPosTerminalService(result: .pendingReconciliation(transactionRef: "ref-xyz"))
        let result = try await svc.charge(invoiceId: 10, amountCents: 100, idempotencyKey: "k2", tipCents: 0)
        if case .pendingReconciliation(let ref) = result {
            XCTAssertEqual(ref, "ref-xyz")
        } else {
            XCTFail("Expected .pendingReconciliation")
        }
    }
}
