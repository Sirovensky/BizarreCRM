import XCTest
@testable import Hardware

// MARK: - MockCashDrawer

final class MockCashDrawer: CashDrawer {
    var isConnected: Bool
    var openCallCount: Int = 0
    var shouldThrow: Bool = false

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }

    func open() async throws {
        if shouldThrow {
            throw CashDrawerError.kickFailed("mock error")
        }
        openCallCount += 1
    }
}

// MARK: - MockManagerPinValidator

final class MockManagerPinValidator: ManagerPinValidator {
    var validPIN: String = "1234"

    func validate(pin: String) async -> Bool {
        pin == validPIN
    }
}

// MARK: - MockCashDrawerAuditLogger

actor MockCashDrawerAuditLogger: CashDrawerAuditLogger {
    var events: [(reason: String, cashier: String)] = []

    func logDrawerOpen(reason: String, cashierName: String) async {
        events.append((reason: reason, cashier: cashierName))
    }
}

// MARK: - CashDrawerManagerTests

@MainActor
final class CashDrawerManagerTests: XCTestCase {

    // MARK: - Tender-driven kick

    func test_handleCashTender_opensDrawer() async {
        let drawer = MockCashDrawer()
        let manager = CashDrawerManager(drawer: drawer)

        await manager.handleTender(.cash, cashierName: "Bob")

        XCTAssertEqual(drawer.openCallCount, 1)
        XCTAssertEqual(manager.status, .open)
    }

    func test_handleCheckTender_opensDrawer() async {
        let drawer = MockCashDrawer()
        let manager = CashDrawerManager(drawer: drawer)

        await manager.handleTender(.check, cashierName: "Alice")

        XCTAssertEqual(drawer.openCallCount, 1)
    }

    func test_handleCashTender_notInTriggerSet_doesNotOpen() async {
        let drawer = MockCashDrawer()
        let manager = CashDrawerManager(drawer: drawer)
        manager.triggerTenders = [] // empty set

        await manager.handleTender(.cash, cashierName: "Bob")

        XCTAssertEqual(drawer.openCallCount, 0)
    }

    // MARK: - Manager override

    func test_managerOverride_validPIN_opensDrawer() async {
        let drawer = MockCashDrawer()
        let validator = MockManagerPinValidator()
        let manager = CashDrawerManager(drawer: drawer, pinValidator: validator)

        let result = await manager.managerOverride(pin: "1234", cashierName: "Manager")

        XCTAssertTrue(result)
        XCTAssertEqual(drawer.openCallCount, 1)
    }

    func test_managerOverride_invalidPIN_rejectsAndDoesNotOpen() async {
        let drawer = MockCashDrawer()
        let validator = MockManagerPinValidator()
        let manager = CashDrawerManager(drawer: drawer, pinValidator: validator)

        let result = await manager.managerOverride(pin: "9999", cashierName: "Manager")

        XCTAssertFalse(result)
        XCTAssertEqual(drawer.openCallCount, 0)
        XCTAssertNotNil(manager.errorMessage)
    }

    // MARK: - Anti-theft

    func test_antiTheft_exceededLimit_setsAlert() async {
        let drawer = MockCashDrawer()
        let validator = MockManagerPinValidator()
        let manager = CashDrawerManager(drawer: drawer, pinValidator: validator)
        manager.antiTheftOpenLimit = 3

        // Open 3 times without sale (manager override)
        for _ in 0..<3 {
            _ = await manager.managerOverride(pin: "1234", cashierName: "Manager")
        }

        XCTAssertNotNil(manager.antiTheftAlert)
    }

    func test_antiTheft_resetBySaleRecorded() async {
        let drawer = MockCashDrawer()
        let validator = MockManagerPinValidator()
        let manager = CashDrawerManager(drawer: drawer, pinValidator: validator)
        manager.antiTheftOpenLimit = 2

        _ = await manager.managerOverride(pin: "1234", cashierName: "Manager")
        _ = await manager.managerOverride(pin: "1234", cashierName: "Manager")
        XCTAssertNotNil(manager.antiTheftAlert)

        // Cash sale resets counter via handleTender → recordAsSale=true.
        await manager.handleTender(.cash)
        XCTAssertNil(manager.antiTheftAlert)
    }

    // MARK: - Status

    func test_markClosed_setsStatusToClosed() async {
        let drawer = MockCashDrawer()
        let manager = CashDrawerManager(drawer: drawer)

        await manager.handleTender(.cash)
        XCTAssertEqual(manager.status, .open)

        manager.markClosed()
        XCTAssertEqual(manager.status, .closed)
    }

    // MARK: - Drawer error

    func test_drawerThrows_setsErrorMessage() async {
        let drawer = MockCashDrawer()
        drawer.shouldThrow = true
        let manager = CashDrawerManager(drawer: drawer)

        await manager.handleTender(.cash)

        XCTAssertNotNil(manager.errorMessage)
        if case .warning = manager.status { /* expected */ } else {
            XCTFail("Expected .warning status on failure, got \(manager.status)")
        }
    }

    // MARK: - Audit logging

    func test_auditLogger_calledOnOpen() async {
        let drawer = MockCashDrawer()
        let logger = MockCashDrawerAuditLogger()
        let manager = CashDrawerManager(drawer: drawer, auditLogger: logger)

        await manager.handleTender(.cash, cashierName: "Charlie")

        let events = await logger.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.cashier, "Charlie")
        XCTAssertTrue(events.first?.reason.contains("Cash") == true)
    }
}
