import XCTest
@testable import Hardware

// MARK: - PeripheralReconnectCoordinatorTests
//
// §17 Bluetooth: auto-retry, severity policy, manual reconnect.

@MainActor
final class PeripheralReconnectCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private let deviceId = UUID()

    private func makeCoordinator(
        kind: DeviceKind? = .receiptPrinter,
        reconnect: @escaping @Sendable () async -> Bool
    ) -> PeripheralReconnectCoordinator {
        PeripheralReconnectCoordinator(
            deviceId: deviceId,
            deviceName: "Test Printer",
            kind: kind,
            policy: BluetoothRetryPolicy(
                shortRetryCount: 2,
                shortRetryInterval: 0.01,  // fast for tests
                longRetryInterval: 0.02
            ),
            reconnect: reconnect
        )
    }

    // MARK: - Initial state

    func test_initialState_isOnline() {
        let coord = makeCoordinator(reconnect: { false })
        XCTAssertFalse(coord.offlineState.isOffline)
    }

    // MARK: - handleDisconnect marks offline

    func test_handleDisconnect_marksOffline() {
        let coord = makeCoordinator(reconnect: { false })
        coord.handleDisconnect()
        XCTAssertTrue(coord.offlineState.isOffline)
    }

    // MARK: - Severity policy

    func test_printerKind_severity_isBanner() {
        let coord = makeCoordinator(kind: .receiptPrinter, reconnect: { false })
        XCTAssertEqual(DeviceKind.receiptPrinter.offlineSeverity, .banner)
    }

    func test_cardReaderKind_severity_isBlocker() {
        XCTAssertEqual(DeviceKind.cardReader.offlineSeverity, .blocker)
    }

    func test_scannerKind_severity_isSilent() {
        XCTAssertEqual(DeviceKind.scanner.offlineSeverity, .silent)
    }

    // MARK: - handleConnect clears offline

    func test_handleConnect_marksOnline() {
        let coord = makeCoordinator(reconnect: { false })
        coord.handleDisconnect()
        XCTAssertTrue(coord.offlineState.isOffline)
        coord.handleConnect()
        XCTAssertFalse(coord.offlineState.isOffline)
    }

    // MARK: - Auto-reconnect succeeds eventually

    func test_retryLoop_succeeds_on_second_attempt() async throws {
        var attemptCount = 0
        let coord = makeCoordinator(reconnect: {
            attemptCount += 1
            return attemptCount >= 2
        })
        coord.handleDisconnect()
        // Wait for retry loop to complete (short intervals in tests)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(coord.offlineState.isOffline)
    }

    // MARK: - Manual reconnect bypasses backoff

    func test_manualReconnect_callsReconnect() async throws {
        var called = false
        let coord = makeCoordinator(reconnect: {
            called = true
            return true
        })
        coord.manualReconnect()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(called)
    }

    func test_manualReconnect_onSuccess_marksOnline() async throws {
        let coord = makeCoordinator(reconnect: { true })
        coord.handleDisconnect()
        coord.manualReconnect()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(coord.offlineState.isOffline)
    }

    // MARK: - Banner message

    func test_bannerMessage_whenPrinterOffline_containsOffline() {
        let coord = makeCoordinator(kind: .receiptPrinter, reconnect: { false })
        coord.handleDisconnect()
        XCTAssertTrue(coord.offlineState.bannerMessage.contains("offline") ||
                      coord.offlineState.bannerMessage.contains("Offline"))
    }

    func test_bannerMessage_whenOnline_isEmpty() {
        let coord = makeCoordinator(reconnect: { true })
        XCTAssertTrue(coord.offlineState.bannerMessage.isEmpty)
    }

    // MARK: - BluetoothRetryPolicy

    func test_retryPolicy_shortInterval_returnsShortInterval() {
        let policy = BluetoothRetryPolicy(
            shortRetryCount: 6,
            shortRetryInterval: 5,
            longRetryInterval: 60
        )
        XCTAssertEqual(policy.interval(for: 1), 5)
        XCTAssertEqual(policy.interval(for: 6), 5)
    }

    func test_retryPolicy_longInterval_afterShortCount() {
        let policy = BluetoothRetryPolicy(
            shortRetryCount: 6,
            shortRetryInterval: 5,
            longRetryInterval: 60
        )
        XCTAssertEqual(policy.interval(for: 7), 60)
        XCTAssertEqual(policy.interval(for: 100), 60)
    }

    func test_retryPolicy_shouldContinue_isAlwaysTrue() {
        let policy = BluetoothRetryPolicy()
        XCTAssertTrue(policy.shouldContinue)
    }
}
