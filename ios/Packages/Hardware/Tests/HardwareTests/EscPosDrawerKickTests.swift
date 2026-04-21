import XCTest
@testable import Hardware

// MARK: - Mock EscPosSender

final class MockEscPosSender: EscPosSender, @unchecked Sendable {

    var isConnected: Bool
    var capturedBytes: [[UInt8]] = []
    var shouldThrow: Bool = false

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }

    func sendBytes(_ bytes: [UInt8]) async throws {
        if shouldThrow { throw URLError(.timedOut) }
        capturedBytes.append(bytes)
    }
}

// MARK: - EscPosDrawerKickTests

final class EscPosDrawerKickTests: XCTestCase {

    // MARK: - kickCommand constant

    func test_kickCommand_is5Bytes() {
        XCTAssertEqual(EscPosDrawerKick.kickCommand.count, 5)
    }

    func test_kickCommand_firstByteIsESC() {
        XCTAssertEqual(EscPosDrawerKick.kickCommand[0], 0x1B)
    }

    func test_kickCommand_secondByteIsP() {
        XCTAssertEqual(EscPosDrawerKick.kickCommand[1], 0x70)
    }

    func test_kickCommand_drawerPinIsZero() {
        XCTAssertEqual(EscPosDrawerKick.kickCommand[2], 0x00)
    }

    func test_kickCommand_onTime() {
        XCTAssertEqual(EscPosDrawerKick.kickCommand[3], 0x19)
    }

    func test_kickCommand_offTime() {
        XCTAssertEqual(EscPosDrawerKick.kickCommand[4], 0xFA)
    }

    // MARK: - buildKickBytes

    func test_buildKickBytes_defaultDrawer1() {
        let sender = MockEscPosSender()
        let kick = EscPosDrawerKick(sender: sender)
        let bytes = kick.buildKickBytes()
        XCTAssertEqual(bytes, [0x1B, 0x70, 0x00, 0x19, 0xFA])
    }

    func test_buildKickBytes_drawer2() {
        let sender = MockEscPosSender()
        let kick = EscPosDrawerKick(sender: sender, drawerPin: 0x01)
        let bytes = kick.buildKickBytes()
        XCTAssertEqual(bytes, [0x1B, 0x70, 0x01, 0x19, 0xFA])
    }

    func test_buildKickBytes_customTimings() {
        let sender = MockEscPosSender()
        let kick = EscPosDrawerKick(sender: sender, onTime: 0x0A, offTime: 0x0F)
        let bytes = kick.buildKickBytes()
        XCTAssertEqual(bytes, [0x1B, 0x70, 0x00, 0x0A, 0x0F])
    }

    // MARK: - open() — happy path

    func test_open_sendsExact5ByteKickCommand() async throws {
        let sender = MockEscPosSender(isConnected: true)
        let kick = EscPosDrawerKick(sender: sender)
        try await kick.open()
        XCTAssertEqual(sender.capturedBytes.count, 1)
        XCTAssertEqual(sender.capturedBytes[0].count, 5)
    }

    func test_open_sendsCorrectESCSequence() async throws {
        let sender = MockEscPosSender(isConnected: true)
        let kick = EscPosDrawerKick(sender: sender)
        try await kick.open()
        XCTAssertEqual(sender.capturedBytes[0], [0x1B, 0x70, 0x00, 0x19, 0xFA])
    }

    // MARK: - open() — error paths

    func test_open_throwsPrinterRequired_whenNotConnected() async {
        let sender = MockEscPosSender(isConnected: false)
        let kick = EscPosDrawerKick(sender: sender)
        do {
            try await kick.open()
            XCTFail("Expected CashDrawerError.printerRequired")
        } catch CashDrawerError.printerRequired {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_open_throwsKickFailed_whenSenderThrows() async {
        let sender = MockEscPosSender(isConnected: true)
        sender.shouldThrow = true
        let kick = EscPosDrawerKick(sender: sender)
        do {
            try await kick.open()
            XCTFail("Expected CashDrawerError.kickFailed")
        } catch CashDrawerError.kickFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - isConnected passthrough

    func test_isConnected_true_whenSenderConnected() {
        let sender = MockEscPosSender(isConnected: true)
        let kick = EscPosDrawerKick(sender: sender)
        XCTAssertTrue(kick.isConnected)
    }

    func test_isConnected_false_whenSenderDisconnected() {
        let sender = MockEscPosSender(isConnected: false)
        let kick = EscPosDrawerKick(sender: sender)
        XCTAssertFalse(kick.isConnected)
    }

    // MARK: - CashDrawerError descriptions

    func test_errorDescriptions_areNonEmpty() {
        XCTAssertNotNil(CashDrawerError.notConnected.errorDescription)
        XCTAssertNotNil(CashDrawerError.kickFailed("boom").errorDescription)
        XCTAssertNotNil(CashDrawerError.printerRequired.errorDescription)
        XCTAssertTrue(CashDrawerError.kickFailed("boom").errorDescription!.contains("boom"))
    }

    // MARK: - NullCashDrawer

    func test_nullDrawer_isNotConnected() {
        XCTAssertFalse(NullCashDrawer().isConnected)
    }

    func test_nullDrawer_throwsNotConnected() async {
        do {
            try await NullCashDrawer().open()
            XCTFail("Expected notConnected")
        } catch CashDrawerError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }
}
