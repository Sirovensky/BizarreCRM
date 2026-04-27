#if canImport(UIKit)
import UIKit
import Observation

/// §16 CFD — Monitors `UIScreen.didConnectNotification` /
/// `UIScreen.didDisconnectNotification` and exposes `isExternalDisplayConnected`
/// so the POS shell can open/close the `"cfd"` `WindowGroup` scene accordingly.
///
/// **Usage (BizarreCRMApp.swift advisory-lock zone — request Agent 10):**
/// ```swift
/// @Environment(CFDExternalDisplayService.self) var cfdDisplay
/// .task { await cfdDisplay.startMonitoring() }
/// ```
///
/// The service is safe to start/stop multiple times; the notification observers
/// are registered once and cleaned up on `deinit`.
///
/// **Thread safety:** `@MainActor` + `@Observable` — SwiftUI can observe
/// `isExternalDisplayConnected` directly from a `@State` or `@Environment` ref.
@MainActor
@Observable
public final class CFDExternalDisplayService {

    // MARK: - Singleton

    public static let shared = CFDExternalDisplayService()

    // MARK: - Observable state

    /// `true` when at least one external screen (HDMI, AirPlay, Sidecar) is
    /// connected. Observe this to conditionally open the `"cfd"` scene.
    public private(set) var isExternalDisplayConnected: Bool = false

    /// Number of currently connected external screens.
    public private(set) var externalScreenCount: Int = 0

    // MARK: - Private

    private var observers: [NSObjectProtocol] = []
    private var isMonitoring = false

    public init() {}

    // MARK: - Lifecycle

    /// Begin observing screen connect / disconnect events.
    /// Idempotent — calling more than once is safe.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Capture current state before registering notifications.
        updateScreenCount()

        let connectObs = NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateScreenCount() }
        }

        let disconnectObs = NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateScreenCount() }
        }

        observers = [connectObs, disconnectObs]
    }

    /// Stop observing and remove all notification observers.
    public func stopMonitoring() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        isMonitoring = false
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Private helpers

    private func updateScreenCount() {
        // UIScreen.screens: index 0 is always the device screen; additional
        // screens represent AirPlay mirrors, HDMI, and Sidecar connections.
        let count = max(0, UIScreen.screens.count - 1)
        externalScreenCount = count
        isExternalDisplayConnected = count > 0
    }
}
#endif
