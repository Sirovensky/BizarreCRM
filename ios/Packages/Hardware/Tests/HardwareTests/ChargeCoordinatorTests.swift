import XCTest
@testable import Hardware

// MARK: - ChargeCoordinatorTests

final class ChargeCoordinatorTests: XCTestCase {

    private var terminal: MockCardTerminal!
    private var coordinator: ChargeCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        terminal = MockCardTerminal()
        coordinator = ChargeCoordinator(terminal: terminal)
    }

    // MARK: - coordinateCharge: not paired

    func test_coordinateCharge_notPaired_throwsNoTerminalPaired() async {
        await terminal.set(stubbedIsPaired: false, stubbedTerminalName: nil)

        do {
            _ = try await coordinator.coordinateCharge(amountCents: 1000)
            XCTFail("Expected ChargeCoordinatorError.noTerminalPaired")
        } catch ChargeCoordinatorError.noTerminalPaired {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - coordinateCharge: success

    func test_coordinateCharge_paired_returnsTransaction() async throws {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")

        let txn = try await coordinator.coordinateCharge(amountCents: 1500, tipCents: 200)

        XCTAssertTrue(txn.approved)
        XCTAssertEqual(txn.amountCents, 1500)
        XCTAssertEqual(txn.tipCents, 200)
        XCTAssertEqual(terminal.chargeCallCount, 1)
    }

    func test_coordinateCharge_propagatesMetadata() async throws {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")

        // No error thrown = metadata passed through correctly
        _ = try await coordinator.coordinateCharge(
            amountCents: 500,
            tipCents: 0,
            metadata: ["orderRef": "INV-001", "description": "Test"]
        )
        XCTAssertEqual(terminal.chargeCallCount, 1)
    }

    // MARK: - coordinateCharge: declined

    func test_coordinateCharge_declined_throwsChargeDeclined() async {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")
        await terminal.set(chargeResult: TerminalTransaction(
            id: "TXN-DEC-001",
            approved: false,
            approvalCode: nil,
            amountCents: 1000,
            tipCents: 0,
            cardBrand: "Visa",
            cardLast4: "1234",
            receiptHtml: nil,
            capturedAt: Date(),
            errorMessage: "Insufficient funds"
        ))

        do {
            _ = try await coordinator.coordinateCharge(amountCents: 1000)
            XCTFail("Expected ChargeCoordinatorError.chargeDeclined")
        } catch ChargeCoordinatorError.chargeDeclined(let msg) {
            XCTAssertEqual(msg, "Insufficient funds")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - coordinateCharge: terminal error

    func test_coordinateCharge_terminalError_rethrows() async {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")
        await terminal.set(chargeError: TerminalError.unreachable)

        do {
            _ = try await coordinator.coordinateCharge(amountCents: 1000)
            XCTFail("Expected TerminalError.unreachable")
        } catch TerminalError.unreachable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - cancelCharge

    func test_cancelCharge_callsTerminalCancel() async {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")
        await coordinator.cancelCharge()
        XCTAssertEqual(terminal.cancelCallCount, 1)
    }

    // MARK: - reverseCharge: not paired

    func test_reverseCharge_notPaired_throwsNoTerminalPaired() async {
        await terminal.set(stubbedIsPaired: false, stubbedTerminalName: nil)

        do {
            _ = try await coordinator.reverseCharge(transactionId: "TXN-001", amountCents: 500)
            XCTFail("Expected noTerminalPaired")
        } catch ChargeCoordinatorError.noTerminalPaired {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - reverseCharge: success

    func test_reverseCharge_paired_returnsTransaction() async throws {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")

        let txn = try await coordinator.reverseCharge(transactionId: "TXN-REV-001", amountCents: 750)

        XCTAssertTrue(txn.approved)
        XCTAssertEqual(txn.amountCents, 750)
    }

    // MARK: - ping: not paired

    func test_ping_notPaired_throwsNoTerminalPaired() async {
        await terminal.set(stubbedIsPaired: false, stubbedTerminalName: nil)

        do {
            _ = try await coordinator.ping()
            XCTFail("Expected noTerminalPaired")
        } catch ChargeCoordinatorError.noTerminalPaired {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - ping: success

    func test_ping_paired_returnsResult() async throws {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")

        let result = try await coordinator.ping()

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.latencyMs, 42)
    }
}

// MARK: - MockCardTerminal additional helpers (for ChargeCoordinator tests)

extension MockCardTerminal {
    func set(chargeResult: TerminalTransaction?) {
        self.chargeResult = chargeResult
    }
}
