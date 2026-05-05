import XCTest
@testable import Hardware

// MARK: - FirmwareManagerTests
//
// §17 Firmware management: terminal + printer firmware version check,
// update policy enforcement, and audit logging.

// MARK: - Mock FirmwareProvider

final class MockFirmwareProvider: FirmwareProvider {
    let infoToReturn: FirmwareInfo?
    var updateCallCount = 0
    var rollbackCallCount = 0
    var shouldThrowOnUpdate = false
    var shouldThrowOnRollback = false
    var newVersionOnUpdate = "2.0.0"

    init(infoToReturn: FirmwareInfo? = nil) {
        self.infoToReturn = infoToReturn
    }

    func fetchFirmwareInfo() async throws -> FirmwareInfo? {
        infoToReturn
    }

    func applyUpdate() async throws -> String {
        updateCallCount += 1
        if shouldThrowOnUpdate {
            throw FirmwareUpdateError.updateFailed("Simulated failure")
        }
        return newVersionOnUpdate
    }

    func rollback() async throws -> String {
        rollbackCallCount += 1
        if shouldThrowOnRollback {
            throw FirmwareUpdateError.rollbackFailed("Simulated rollback failure")
        }
        return "1.0.0"
    }
}

// MARK: - Mock Logger

actor MockFirmwareUpdateLogger: FirmwareUpdateLogger {
    var entries: [(kind: FirmwareKind, result: FirmwareUpdateResult)] = []

    func logFirmwareUpdate(
        kind: FirmwareKind,
        deviceName: String,
        fromVersion: String,
        toVersion: String,
        result: FirmwareUpdateResult,
        performedBy: String
    ) async {
        entries.append((kind: kind, result: result))
    }
}

// MARK: - Tests

@MainActor
final class FirmwareManagerTests: XCTestCase {

    // MARK: - refresh

    func test_refresh_populatesFirmwareInfos() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.5.0",
            latestVersion: "1.6.0"
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        let manager = FirmwareManager(providers: [provider])

        await manager.refresh()

        XCTAssertEqual(manager.firmwareInfos.count, 1)
        XCTAssertEqual(manager.firmwareInfos.first?.deviceName, "Counter-1")
    }

    func test_refresh_emptyWhenProviderReturnsNil() async {
        let provider = MockFirmwareProvider(infoToReturn: nil)
        let manager = FirmwareManager(providers: [provider])

        await manager.refresh()

        XCTAssertTrue(manager.firmwareInfos.isEmpty)
    }

    func test_outdatedDevices_filtersUpToDateOnes() async {
        let outdated = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.0.0",
            latestVersion: "2.0.0"
        )
        let upToDate = FirmwareInfo(
            kind: .receiptPrinter,
            deviceName: "Printer-A",
            currentVersion: "3.1.0",
            latestVersion: "3.1.0"
        )
        let p1 = MockFirmwareProvider(infoToReturn: outdated)
        let p2 = MockFirmwareProvider(infoToReturn: upToDate)
        let manager = FirmwareManager(providers: [p1, p2])

        await manager.refresh()

        XCTAssertEqual(manager.outdatedDevices.count, 1)
        XCTAssertEqual(manager.outdatedDevices.first?.deviceName, "Counter-1")
    }

    // MARK: - FirmwareInfo.isUpToDate

    func test_firmwareInfo_isUpToDate_whenVersionsMatch() {
        let info = FirmwareInfo(
            kind: .receiptPrinter,
            deviceName: "Printer-A",
            currentVersion: "3.1.0",
            latestVersion: "3.1.0"
        )
        XCTAssertTrue(info.isUpToDate)
    }

    func test_firmwareInfo_isNotUpToDate_whenVersionsDiffer() {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.0.0",
            latestVersion: "1.1.0"
        )
        XCTAssertFalse(info.isUpToDate)
    }

    // MARK: - applyUpdate

    func test_applyUpdate_succeeds_inClosedHours() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.0.0",
            latestVersion: "2.0.0"
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        provider.newVersionOnUpdate = "2.0.0"
        let manager = FirmwareManager(providers: [provider])

        let result = await manager.applyUpdate(for: info, isOpenHours: false)

        if case .success(let v) = result {
            XCTAssertEqual(v, "2.0.0")
        } else {
            XCTFail("Expected .success, got \(result)")
        }
    }

    func test_applyUpdate_blockedDuringOpenHoursWithAfterHoursPolicy() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.0.0",
            latestVersion: "2.0.0"
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        let manager = FirmwareManager(providers: [provider])
        manager.updatePolicy = .afterHours

        let result = await manager.applyUpdate(for: info, isOpenHours: true)

        XCTAssertNotNil(manager.errorMessage)
        if case .failed = result {
            // expected
        } else {
            XCTFail("Expected .failed when open hours + afterHours policy, got \(result)")
        }
        XCTAssertEqual(provider.updateCallCount, 0, "applyUpdate must not be called when blocked")
    }

    func test_applyUpdate_allowedDuringOpenHoursWithImmediatePolicy() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.0.0",
            latestVersion: "2.0.0"
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        let manager = FirmwareManager(providers: [provider])
        manager.updatePolicy = .immediately

        let result = await manager.applyUpdate(for: info, isOpenHours: true)

        XCTAssertEqual(provider.updateCallCount, 1)
        if case .success = result { /* expected */ } else {
            XCTFail("Expected .success with .immediately policy, got \(result)")
        }
    }

    func test_applyUpdate_returnsFailedOnProviderError() async {
        let info = FirmwareInfo(
            kind: .receiptPrinter,
            deviceName: "Printer-A",
            currentVersion: "2.0.0",
            latestVersion: "3.0.0"
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        provider.shouldThrowOnUpdate = true
        let manager = FirmwareManager(providers: [provider])

        let result = await manager.applyUpdate(for: info, isOpenHours: false)

        XCTAssertNotNil(manager.errorMessage)
        if case .failed = result { /* expected */ } else {
            XCTFail("Expected .failed on provider error, got \(result)")
        }
    }

    // MARK: - rollback

    func test_rollback_returnsNoPreviousVersion_whenNotAvailable() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "2.0.0",
            latestVersion: "2.0.0",
            rollbackAvailable: false
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        let manager = FirmwareManager(providers: [provider])

        let result = await manager.rollback(for: info)

        XCTAssertEqual(result, .noPreviousVersion)
        XCTAssertEqual(provider.rollbackCallCount, 0)
    }

    func test_rollback_succeeds_whenAvailable() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "2.0.0",
            latestVersion: "2.0.0",
            rollbackAvailable: true
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        let manager = FirmwareManager(providers: [provider])

        let result = await manager.rollback(for: info)

        if case .success(let v) = result {
            XCTAssertEqual(v, "1.0.0")
        } else {
            XCTFail("Expected .success, got \(result)")
        }
    }

    // MARK: - Audit logging

    func test_applyUpdate_logsSuccessEntry() async {
        let info = FirmwareInfo(
            kind: .cardTerminal,
            deviceName: "Counter-1",
            currentVersion: "1.0.0",
            latestVersion: "2.0.0"
        )
        let provider = MockFirmwareProvider(infoToReturn: info)
        let loggerActor = MockFirmwareUpdateLogger()
        let loggerWrapper = LoggerWrapper(actor: loggerActor)
        let manager = FirmwareManager(providers: [provider], logger: loggerWrapper)

        await manager.applyUpdate(for: info, isOpenHours: false)

        let entries = await loggerActor.entries
        XCTAssertEqual(entries.count, 1)
        if case .success = entries.first?.result { /* ok */ } else {
            XCTFail("Expected logged success entry")
        }
    }

    // MARK: - FirmwareUpdatePolicy

    func test_firmwareUpdatePolicy_allCasesHaveRawValues() {
        for policy in FirmwareUpdatePolicy.allCases {
            XCTAssertFalse(policy.rawValue.isEmpty)
        }
    }

    // MARK: - FirmwareUpdateError

    func test_firmwareUpdateError_allHaveLocalizedDescriptions() {
        let errors: [FirmwareUpdateError] = [
            .deviceUnreachable,
            .updateNotAvailable,
            .updateFailed("test"),
            .rollbackUnsupported,
            .rollbackFailed("test"),
            .updateDuringOpenHours,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - Wrapper to bridge actor logger to Sendable protocol

/// Thin Sendable wrapper so the actor-based mock can be injected as `FirmwareUpdateLogger`.
private final class LoggerWrapper: FirmwareUpdateLogger {
    private let actor: MockFirmwareUpdateLogger

    init(actor: MockFirmwareUpdateLogger) {
        self.actor = actor
    }

    func logFirmwareUpdate(
        kind: FirmwareKind,
        deviceName: String,
        fromVersion: String,
        toVersion: String,
        result: FirmwareUpdateResult,
        performedBy: String
    ) async {
        await actor.logFirmwareUpdate(
            kind: kind,
            deviceName: deviceName,
            fromVersion: fromVersion,
            toVersion: toVersion,
            result: result,
            performedBy: performedBy
        )
    }
}
