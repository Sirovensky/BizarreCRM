import XCTest
import Core
@testable import Hardware

// MARK: - MockCardTerminal

/// Controllable mock for `CardTerminal`.
/// Each property / method is independently configurable for test scenarios.
actor MockCardTerminal: CardTerminal {
    // MARK: - Configuration
    var stubbedIsPaired: Bool = false
    var stubbedTerminalName: String? = nil
    var pairError: Error? = nil
    var chargeResult: TerminalTransaction? = nil
    var chargeError: Error? = nil
    var reverseResult: TerminalTransaction? = nil
    var reverseError: Error? = nil
    var pingResult: TerminalPingResult? = TerminalPingResult(ok: true, latencyMs: 42)
    var pingError: Error? = nil

    // MARK: - Call tracking
    nonisolated(unsafe) var pairCallCount: Int = 0
    nonisolated(unsafe) var chargeCallCount: Int = 0
    nonisolated(unsafe) var cancelCallCount: Int = 0
    nonisolated(unsafe) var unpairCallCount: Int = 0
    nonisolated(unsafe) var lastPairingCredentials: BlockChypCredentials? = nil
    nonisolated(unsafe) var lastActivationCode: String? = nil
    nonisolated(unsafe) var lastTerminalName: String? = nil

    // MARK: - CardTerminal

    var isPaired: Bool { stubbedIsPaired }
    var pairedTerminalName: String? { stubbedTerminalName }

    func pair(
        apiCredentials: BlockChypCredentials,
        activationCode: String,
        terminalName: String
    ) async throws {
        pairCallCount += 1
        lastPairingCredentials = apiCredentials
        lastActivationCode = activationCode
        lastTerminalName = terminalName

        if let error = pairError { throw error }
        // On success, update state
        stubbedIsPaired = true
        stubbedTerminalName = terminalName
    }

    func charge(
        amountCents: Int,
        tipCents: Int,
        metadata: [String: String]
    ) async throws -> TerminalTransaction {
        chargeCallCount += 1
        if let error = chargeError { throw error }
        return chargeResult ?? TerminalTransaction(
            id: "TEST-TXN-001",
            approved: true,
            approvalCode: "AUTH01",
            amountCents: amountCents,
            tipCents: tipCents,
            cardBrand: "Visa",
            cardLast4: "4242",
            receiptHtml: nil,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            errorMessage: nil
        )
    }

    func reverse(
        transactionId: String,
        amountCents: Int
    ) async throws -> TerminalTransaction {
        if let error = reverseError { throw error }
        return reverseResult ?? TerminalTransaction(
            id: transactionId,
            approved: true,
            approvalCode: "REV01",
            amountCents: amountCents,
            tipCents: 0,
            cardBrand: nil,
            cardLast4: nil,
            receiptHtml: nil,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            errorMessage: nil
        )
    }

    func cancel() async {
        cancelCallCount += 1
    }

    func ping() async throws -> TerminalPingResult {
        if let error = pingError { throw error }
        return pingResult ?? TerminalPingResult(ok: false, latencyMs: 0)
    }

    func unpair() async {
        unpairCallCount += 1
        stubbedIsPaired = false
        stubbedTerminalName = nil
    }
}

// MARK: - BlockChypPairingViewModelTests

@MainActor
final class BlockChypPairingViewModelTests: XCTestCase {

    private var terminal: MockCardTerminal!
    private var viewModel: BlockChypPairingViewModel!
    private let testCredentials = BlockChypCredentials(
        apiKey: "TESTKEY",
        bearerToken: "TESTTOKEN",
        signingKey: "deadbeef0011223344556677deadbeef0011223344556677deadbeef00112233"
    )

    override func setUp() async throws {
        try await super.setUp()
        terminal = MockCardTerminal()
        viewModel = BlockChypPairingViewModel(terminal: terminal)
    }

    // MARK: - onAppear

    func test_onAppear_notPaired_staysIdle() async {
        await terminal.set(stubbedIsPaired: false, stubbedTerminalName: nil)
        await viewModel.onAppear()
        guard case .idle = viewModel.state else {
            XCTFail("Expected .idle, got \(viewModel.state)")
            return
        }
    }

    func test_onAppear_paired_transitionsToPaired() async {
        await terminal.set(stubbedIsPaired: true, stubbedTerminalName: "Counter 1")
        await viewModel.onAppear()
        guard case .paired(let info) = viewModel.state else {
            XCTFail("Expected .paired, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(info.name, "Counter 1")
    }

    // MARK: - beginPairing — validation

    func test_beginPairing_emptyCode_stateIsFailed() async {
        viewModel.activationCode = ""
        viewModel.terminalName = "Counter 1"
        await viewModel.beginPairing(credentials: testCredentials)
        guard case .failed = viewModel.state else {
            XCTFail("Expected .failed for empty code")
            return
        }
    }

    func test_beginPairing_emptyName_stateIsFailed() async {
        viewModel.activationCode = "ABCD1234"
        viewModel.terminalName = ""
        await viewModel.beginPairing(credentials: testCredentials)
        guard case .failed = viewModel.state else {
            XCTFail("Expected .failed for empty name")
            return
        }
    }

    func test_beginPairing_whitespaceOnlyCode_stateIsFailed() async {
        viewModel.activationCode = "   "
        viewModel.terminalName = "Counter 1"
        await viewModel.beginPairing(credentials: testCredentials)
        guard case .failed = viewModel.state else {
            XCTFail("Expected .failed for whitespace code")
            return
        }
    }

    // MARK: - beginPairing — success path

    func test_beginPairing_success_transitionsToPaired() async {
        viewModel.activationCode = "PAIR1234"
        viewModel.terminalName = "Counter 1"
        await viewModel.beginPairing(credentials: testCredentials)
        guard case .paired(let info) = viewModel.state else {
            XCTFail("Expected .paired after successful pair, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(info.name, "Counter 1")
    }

    func test_beginPairing_success_clearsActivationCode() async {
        viewModel.activationCode = "PAIR1234"
        viewModel.terminalName = "Terminal 1"
        await viewModel.beginPairing(credentials: testCredentials)
        XCTAssertEqual(viewModel.activationCode, "")
    }

    func test_beginPairing_success_callsTerminalPair() async {
        viewModel.activationCode = "CODE5678"
        viewModel.terminalName = "Lane 2"
        await viewModel.beginPairing(credentials: testCredentials)
        XCTAssertEqual(terminal.pairCallCount, 1)
        XCTAssertEqual(terminal.lastActivationCode, "CODE5678")
        XCTAssertEqual(terminal.lastTerminalName, "Lane 2")
    }

    // MARK: - beginPairing — failure path

    func test_beginPairing_terminalError_transitionsToFailed() async {
        await terminal.set(pairError: TerminalError.pairingFailed("Bad code"))
        viewModel.activationCode = "BADCODE1"
        viewModel.terminalName = "Terminal 1"
        await viewModel.beginPairing(credentials: testCredentials)
        guard case .failed(let msg) = viewModel.state else {
            XCTFail("Expected .failed, got \(viewModel.state)")
            return
        }
        XCTAssertTrue(msg.contains("Bad code"), "Error message should contain original reason")
    }

    func test_beginPairing_networkError_transitionsToFailed() async {
        await terminal.set(pairError: AppError.network(underlying: URLError(.notConnectedToInternet)))
        viewModel.activationCode = "NETFAIL1"
        viewModel.terminalName = "Terminal 1"
        await viewModel.beginPairing(credentials: testCredentials)
        guard case .failed = viewModel.state else {
            XCTFail("Expected .failed for network error")
            return
        }
    }

    // MARK: - testCharge — success

    func test_testCharge_success_returnsToPaired() async {
        // Start in paired state
        viewModel.activationCode = "PAIRCODE"
        viewModel.terminalName = "Checkout"
        await viewModel.beginPairing(credentials: testCredentials)

        await viewModel.testCharge()

        guard case .paired(let info) = viewModel.state else {
            XCTFail("Expected .paired after test charge, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(info.name, "Checkout")
        XCTAssertEqual(terminal.chargeCallCount, 1)
    }

    func test_testCharge_failure_transitionsToFailed() async {
        await terminal.set(chargeError: TerminalError.chargeFailed("Terminal busy"))
        viewModel.activationCode = "PAIRCODE"
        viewModel.terminalName = "Checkout"
        await viewModel.beginPairing(credentials: testCredentials)

        await viewModel.testCharge()

        guard case .failed = viewModel.state else {
            XCTFail("Expected .failed after test charge error")
            return
        }
    }

    // MARK: - unpair

    func test_unpair_resetsToIdle() async {
        viewModel.activationCode = "PAIRCODE"
        viewModel.terminalName = "Counter 1"
        await viewModel.beginPairing(credentials: testCredentials)

        await viewModel.unpair()

        guard case .idle = viewModel.state else {
            XCTFail("Expected .idle after unpair, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(terminal.unpairCallCount, 1)
    }

    func test_unpair_clearsTerminalName() async {
        viewModel.activationCode = "PAIRCODE"
        viewModel.terminalName = "Counter 1"
        await viewModel.beginPairing(credentials: testCredentials)

        await viewModel.unpair()

        XCTAssertEqual(viewModel.terminalName, "Terminal 1", "Name should reset to default")
    }

    // MARK: - retryFromFailure

    func test_retryFromFailure_setsIdle() async {
        await terminal.set(pairError: TerminalError.pairingFailed("err"))
        viewModel.activationCode = "CODE"
        viewModel.terminalName = "T"
        await viewModel.beginPairing(credentials: testCredentials)

        viewModel.retryFromFailure()

        guard case .idle = viewModel.state else {
            XCTFail("Expected .idle after retry")
            return
        }
    }
}

// MARK: - MockCardTerminal convenience helpers

extension MockCardTerminal {
    func set(stubbedIsPaired: Bool, stubbedTerminalName: String?) {
        self.stubbedIsPaired = stubbedIsPaired
        self.stubbedTerminalName = stubbedTerminalName
    }

    func set(pairError: Error?) {
        self.pairError = pairError
    }

    func set(chargeError: Error?) {
        self.chargeError = chargeError
    }
}
