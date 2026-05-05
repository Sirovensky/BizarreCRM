#if canImport(SwiftUI)
import XCTest
@testable import Hardware

// MARK: - DeviceTestActionsViewModelTests
//
// Tests the observable view-model that drives inline test-fire buttons.
//
// Coverage:
//   - Initial state: all actions start .idle
//   - printTestPage: idle → running → success on clean closure
//   - printTestPage: idle → running → failure when closure throws
//   - printTestPage: noop when already running (guard)
//   - openDrawer: same state machine
//   - readScale: success path returns the reading string
//   - testScanner: success / failure paths
//   - pingTerminal: success / failure paths
//   - resetAll: returns all states to .idle
//   - reset(for:): returns only the targeted state to .idle
//   - TestActionState Equatable conformance

@MainActor
final class DeviceTestActionsViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM() -> DeviceTestActionsViewModel {
        DeviceTestActionsViewModel()
    }

    private struct TestError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Initial state

    func test_initialState_allActionsIdle() {
        let vm = makeVM()
        XCTAssertEqual(vm.printerTestState,  .idle)
        XCTAssertEqual(vm.drawerTestState,   .idle)
        XCTAssertEqual(vm.scaleTestState,    .idle)
        XCTAssertEqual(vm.scannerTestState,  .idle)
        XCTAssertEqual(vm.terminalTestState, .idle)
    }

    // MARK: - printTestPage

    func test_printTestPage_successPath_setsSuccessState() async {
        let vm = makeVM()
        vm.onPrintTestPage = { /* no-op success */ }
        await vm.printTestPage()
        if case .success = vm.printerTestState { /* ok */ } else {
            XCTFail("Expected .success, got \(vm.printerTestState)")
        }
    }

    func test_printTestPage_failurePath_setsFailureState() async {
        let vm = makeVM()
        vm.onPrintTestPage = { throw TestError(message: "Printer offline") }
        await vm.printTestPage()
        if case .failure(let msg) = vm.printerTestState {
            XCTAssertEqual(msg, "Printer offline")
        } else {
            XCTFail("Expected .failure, got \(vm.printerTestState)")
        }
    }

    func test_printTestPage_doesNotRunWhenAlreadyRunning() async {
        let vm = makeVM()
        // Manually set running state
        vm.printerTestState = .running
        var callCount = 0
        vm.onPrintTestPage = { callCount += 1 }
        await vm.printTestPage()
        XCTAssertEqual(callCount, 0, "printTestPage must be a noop when already running")
    }

    func test_printTestPage_successMessage() async {
        let vm = makeVM()
        vm.onPrintTestPage = {}
        await vm.printTestPage()
        if case .success(let msg) = vm.printerTestState {
            XCTAssertFalse(msg.isEmpty, "Success message must not be empty")
        } else {
            XCTFail("Expected .success")
        }
    }

    // MARK: - openDrawer

    func test_openDrawer_successPath_setsSuccessState() async {
        let vm = makeVM()
        vm.onOpenDrawer = {}
        await vm.openDrawer()
        if case .success = vm.drawerTestState { /* ok */ } else {
            XCTFail("Expected .success, got \(vm.drawerTestState)")
        }
    }

    func test_openDrawer_failurePath_setsFailureState() async {
        let vm = makeVM()
        vm.onOpenDrawer = { throw TestError(message: "Drawer not connected") }
        await vm.openDrawer()
        if case .failure(let msg) = vm.drawerTestState {
            XCTAssertEqual(msg, "Drawer not connected")
        } else {
            XCTFail("Expected .failure")
        }
    }

    func test_openDrawer_doesNotRunWhenAlreadyRunning() async {
        let vm = makeVM()
        vm.drawerTestState = .running
        var callCount = 0
        vm.onOpenDrawer = { callCount += 1 }
        await vm.openDrawer()
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - readScale

    func test_readScale_successPath_returnsReading() async {
        let vm = makeVM()
        vm.onReadScale = { return "250 g" }
        await vm.readScale()
        if case .success(let msg) = vm.scaleTestState {
            XCTAssertEqual(msg, "250 g")
        } else {
            XCTFail("Expected .success with reading, got \(vm.scaleTestState)")
        }
    }

    func test_readScale_failurePath_setsFailureState() async {
        let vm = makeVM()
        vm.onReadScale = { throw TestError(message: "Scale timeout") }
        await vm.readScale()
        if case .failure(let msg) = vm.scaleTestState {
            XCTAssertEqual(msg, "Scale timeout")
        } else {
            XCTFail("Expected .failure")
        }
    }

    func test_readScale_doesNotRunWhenAlreadyRunning() async {
        let vm = makeVM()
        vm.scaleTestState = .running
        var callCount = 0
        vm.onReadScale = { callCount += 1; return "1 g" }
        await vm.readScale()
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - testScanner

    func test_testScanner_successPath() async {
        let vm = makeVM()
        vm.onTestScanner = {}
        await vm.testScanner()
        if case .success = vm.scannerTestState { /* ok */ } else {
            XCTFail("Expected .success, got \(vm.scannerTestState)")
        }
    }

    func test_testScanner_failurePath() async {
        let vm = makeVM()
        vm.onTestScanner = { throw TestError(message: "Scanner not paired") }
        await vm.testScanner()
        if case .failure(let msg) = vm.scannerTestState {
            XCTAssertEqual(msg, "Scanner not paired")
        } else {
            XCTFail("Expected .failure")
        }
    }

    // MARK: - pingTerminal

    func test_pingTerminal_successPath_returnsPingResult() async {
        let vm = makeVM()
        vm.onPingTerminal = { return "OK — 12ms" }
        await vm.pingTerminal()
        if case .success(let msg) = vm.terminalTestState {
            XCTAssertEqual(msg, "OK — 12ms")
        } else {
            XCTFail("Expected .success with ping result")
        }
    }

    func test_pingTerminal_failurePath() async {
        let vm = makeVM()
        vm.onPingTerminal = { throw TestError(message: "Terminal unreachable") }
        await vm.pingTerminal()
        if case .failure(let msg) = vm.terminalTestState {
            XCTAssertEqual(msg, "Terminal unreachable")
        } else {
            XCTFail("Expected .failure")
        }
    }

    func test_pingTerminal_doesNotRunWhenAlreadyRunning() async {
        let vm = makeVM()
        vm.terminalTestState = .running
        var callCount = 0
        vm.onPingTerminal = { callCount += 1; return "ok" }
        await vm.pingTerminal()
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - resetAll

    func test_resetAll_clearsAllStates() async {
        let vm = makeVM()
        vm.onPrintTestPage = {}
        vm.onOpenDrawer    = {}
        vm.onReadScale     = { return "1 g" }
        vm.onTestScanner   = {}
        vm.onPingTerminal  = { return "ok" }

        await vm.printTestPage()
        await vm.openDrawer()
        await vm.readScale()
        await vm.testScanner()
        await vm.pingTerminal()

        // Verify all are non-idle before reset
        XCTAssertNotEqual(vm.printerTestState,  .idle)
        XCTAssertNotEqual(vm.drawerTestState,   .idle)
        XCTAssertNotEqual(vm.scaleTestState,    .idle)
        XCTAssertNotEqual(vm.scannerTestState,  .idle)
        XCTAssertNotEqual(vm.terminalTestState, .idle)

        vm.resetAll()

        XCTAssertEqual(vm.printerTestState,  .idle)
        XCTAssertEqual(vm.drawerTestState,   .idle)
        XCTAssertEqual(vm.scaleTestState,    .idle)
        XCTAssertEqual(vm.scannerTestState,  .idle)
        XCTAssertEqual(vm.terminalTestState, .idle)
    }

    // MARK: - reset(for:)

    func test_resetForType_onlyResetsPrinter() async {
        let vm = makeVM()
        vm.onPrintTestPage = {}
        vm.onOpenDrawer    = {}
        await vm.printTestPage()
        await vm.openDrawer()

        vm.reset(for: .printer)

        XCTAssertEqual(vm.printerTestState, .idle, "Printer state must be reset")
        XCTAssertNotEqual(vm.drawerTestState, .idle, "Drawer state must be untouched")
    }

    func test_resetForType_onlyResetsDrawer() async {
        let vm = makeVM()
        vm.onPrintTestPage = {}
        vm.onOpenDrawer    = {}
        await vm.printTestPage()
        await vm.openDrawer()

        vm.reset(for: .drawer)

        XCTAssertEqual(vm.drawerTestState, .idle)
        XCTAssertNotEqual(vm.printerTestState, .idle)
    }

    func test_resetForType_scale() async {
        let vm = makeVM()
        vm.onReadScale = { return "5 g" }
        await vm.readScale()
        vm.reset(for: .scale)
        XCTAssertEqual(vm.scaleTestState, .idle)
    }

    func test_resetForType_scanner() async {
        let vm = makeVM()
        vm.onTestScanner = {}
        await vm.testScanner()
        vm.reset(for: .scanner)
        XCTAssertEqual(vm.scannerTestState, .idle)
    }

    func test_resetForType_terminal() async {
        let vm = makeVM()
        vm.onPingTerminal = { return "ok" }
        await vm.pingTerminal()
        vm.reset(for: .terminal)
        XCTAssertEqual(vm.terminalTestState, .idle)
    }
}

// MARK: - TestActionState Equatable tests

final class TestActionStateTests: XCTestCase {

    func test_idle_equalsIdle() {
        XCTAssertEqual(TestActionState.idle, TestActionState.idle)
    }

    func test_running_equalsRunning() {
        XCTAssertEqual(TestActionState.running, TestActionState.running)
    }

    func test_success_equalsSuccess_samemessage() {
        XCTAssertEqual(TestActionState.success("ok"), TestActionState.success("ok"))
    }

    func test_success_notEqual_differentMessage() {
        XCTAssertNotEqual(TestActionState.success("a"), TestActionState.success("b"))
    }

    func test_failure_equalsFailure_sameMessage() {
        XCTAssertEqual(TestActionState.failure("err"), TestActionState.failure("err"))
    }

    func test_failure_notEqual_differentMessage() {
        XCTAssertNotEqual(TestActionState.failure("x"), TestActionState.failure("y"))
    }

    func test_idle_notEqualRunning() {
        XCTAssertNotEqual(TestActionState.idle, TestActionState.running)
    }

    func test_success_notEqualFailure() {
        XCTAssertNotEqual(TestActionState.success("ok"), TestActionState.failure("ok"))
    }
}

#endif
