#if canImport(UIKit)
import Foundation
import UIKit
import Persistence
import Core

// MARK: - LockTriggerManager
//
// §2.5 — Lock triggers:
//   • Cold start: always prompt PIN/biometric on launch if PIN enrolled.
//   • Background for N minutes: configurable threshold (0/1/5/15/never).
//   • Explicit "Lock now" action.
//
// This actor monitors the app lifecycle and publishes a `lockRequired` signal
// that the host (AppDelegate / SessionBootstrapper) observes to show PINUnlockView.

// MARK: - Lock-after threshold

public enum LockAfterMinutes: Int, Sendable, CaseIterable, Identifiable {
    case immediately  = 0
    case oneMinute    = 1
    case fiveMinutes  = 5
    case fifteenMins  = 15
    case never        = -1

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .immediately:  return "Immediately"
        case .oneMinute:    return "After 1 minute"
        case .fiveMinutes:  return "After 5 minutes"
        case .fifteenMins:  return "After 15 minutes"
        case .never:        return "Never"
        }
    }
}

// MARK: - Preference storage

public enum LockThresholdStore {
    private static let key = "auth.lockAfterMinutes"

    public static var threshold: LockAfterMinutes {
        get {
            let raw = UserDefaults.standard.integer(forKey: key)
            return LockAfterMinutes(rawValue: raw) ?? .fifteenMins
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

// MARK: - LockTriggerManager

/// Actor that tracks background transitions and fires the lock callback.
///
/// Wire at startup:
/// ```swift
/// await LockTriggerManager.shared.start { await showPINLock() }
/// ```
@MainActor
public final class LockTriggerManager {
    public static let shared = LockTriggerManager()

    private var backgroundedAt: Date?
    private var lockCallback: (() async -> Void)?
    private var observerTokens: [NSObjectProtocol] = []

    private init() {}

    // MARK: - Start

    public func start(onLock: @escaping () async -> Void) {
        self.lockCallback = onLock
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observerTokens.removeAll()

        let nc = NotificationCenter.default

        observerTokens.append(nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleBackground()
        })

        observerTokens.append(nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleForeground()
            }
        })
    }

    // MARK: - Explicit lock

    public func lockNow() async {
        guard PINStore.shared.isEnrolled else { return }
        await lockCallback?()
    }

    // MARK: - Background tracking

    private func handleBackground() {
        backgroundedAt = Date()
    }

    private func handleForeground() async {
        guard PINStore.shared.isEnrolled else { return }
        let threshold = LockThresholdStore.threshold
        guard threshold != .never else { return }

        if threshold == .immediately {
            await lockCallback?()
            return
        }

        guard let bgAt = backgroundedAt else {
            // Cold start path — always lock.
            await lockCallback?()
            return
        }
        backgroundedAt = nil

        let elapsed = Date().timeIntervalSince(bgAt)
        let thresholdSeconds = Double(threshold.rawValue) * 60
        if elapsed >= thresholdSeconds {
            await lockCallback?()
        }
    }
}

#endif
