@preconcurrency import CoreBluetooth
import Foundation
import Core

// MARK: - PeripheralReconnectCoordinator
//
// §17 Bluetooth auto-retry + severity-aware banner:
//   - Attempts 1-6 every 5s (30s window) then exponential backoff (every 60s).
//   - Scanner offline: silent (badge only).
//   - Printer offline: surfaces banner.
//   - Terminal offline: blocker.
//   - Manual "Reconnect" button bypasses backoff and retries immediately.
//   - Each peripheral gets its own `PeripheralOfflineState` for UI binding.
//
// Usage: instantiate one coordinator per connected peripheral (held by the
// `BluetoothManager` or a higher-level service). Call `handleDisconnect()` when
// the peripheral drops; call `handleConnect()` on success; call `manualReconnect()`
// from the UI "Reconnect" button.

@MainActor
public final class PeripheralReconnectCoordinator {

    // MARK: - Published state (drives UI)

    public let offlineState: PeripheralOfflineState

    // MARK: - Dependencies

    private let policy: BluetoothRetryPolicy
    private let reconnect: @Sendable () async -> Bool  // returns true = connected
    private var retryTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - deviceId: `CBPeripheral.identifier`.
    ///   - deviceName: Human-readable name shown in banners.
    ///   - kind: Optional device kind — drives severity policy.
    ///   - policy: Retry backoff parameters (default: 6×5s, then 60s).
    ///   - reconnect: Async closure that attempts reconnection.
    ///     Return `true` on success, `false` on failure.
    public init(
        deviceId: UUID,
        deviceName: String,
        kind: DeviceKind?,
        policy: BluetoothRetryPolicy = BluetoothRetryPolicy(),
        reconnect: @escaping @Sendable () async -> Bool
    ) {
        self.offlineState = PeripheralOfflineState(
            deviceId: deviceId,
            deviceName: deviceName,
            kind: kind
        )
        self.policy = policy
        self.reconnect = reconnect
    }

    // MARK: - Lifecycle

    /// Call when the peripheral disconnects unexpectedly.
    /// Starts the retry loop automatically.
    public func handleDisconnect() {
        cancelRetry()
        self.offlineState.markOffline(attempt: 0)
        let name = self.offlineState.deviceName
        AppLog.hardware.warning("PeripheralReconnectCoordinator[\(name, privacy: .public)]: disconnected — starting retry loop")
        startRetryLoop()
    }

    /// Call when the peripheral reconnects (after a retry or manual reconnect).
    public func handleConnect() {
        cancelRetry()
        self.offlineState.markOnline()
        let name = self.offlineState.deviceName
        AppLog.hardware.info("PeripheralReconnectCoordinator[\(name, privacy: .public)]: reconnected")
    }

    /// Manual reconnect triggered by the user (bypasses current backoff).
    /// Cancels any running retry loop and attempts immediately.
    public func manualReconnect() {
        cancelRetry()
        let name = self.offlineState.deviceName
        AppLog.hardware.info("PeripheralReconnectCoordinator[\(name, privacy: .public)]: manual reconnect requested")
        retryTask = Task { @MainActor [weak self] in
            await self?.attemptOnce(attemptNumber: 0)
        }
    }

    // MARK: - Retry loop

    private func startRetryLoop() {
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var attempt = 1
            while !Task.isCancelled {
                let interval = self.policy.interval(for: attempt)
                AppLog.hardware.info("PeripheralReconnectCoordinator[\(self.offlineState.deviceName, privacy: .public)]: retry #\(attempt) in \(Int(interval))s")
                self.offlineState.markOffline(attempt: attempt)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                let connected = await self.reconnect()
                if connected {
                    self.handleConnect()
                    break
                }
                attempt += 1
            }
        }
    }

    private func attemptOnce(attemptNumber: Int) async {
        offlineState.markOffline(attempt: attemptNumber)
        let connected = await reconnect()
        if connected {
            handleConnect()
        } else {
            // Restart the full retry loop from the next attempt.
            startRetryLoop()
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    deinit {
        retryTask?.cancel()
    }
}
