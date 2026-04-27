#if canImport(UIKit)
import UIKit
import Foundation
import Persistence

// MARK: - §2.5 Lock triggers

/// Monitors app lifecycle and idle-timer events to decide when to require PIN
/// re-entry. Sits in the Auth package so it can reach `PINStore` + `TokenStore`
/// without pulling feature modules.
///
/// **Lock conditions (§2.13):**
/// - **Cold start** — always trigger if a PIN is enrolled and a token exists.
/// - **Background N minutes** — configured by tenant (Settings: 0/1/5/15/never).
/// - **Explicit "Lock now"** — from any lock-now action (Settings / avatar menu).
///
/// **Integration** (wire in `AppState` or `BizarreCRMApp`):
/// ```swift
/// let monitor = LockTriggerMonitor(
///     timeout: .minutes(5),
///     onLockRequired: { await appState.requirePINUnlock() }
/// )
/// monitor.start()
/// ```
///
/// The monitor observes `UIApplication.willResignActiveNotification` for the
/// background timestamp, `UIApplication.didBecomeActiveNotification` to check
/// elapsed time, and `UIApplication.didFinishLaunchingNotification` is handled
/// by the caller — cold-start should always lock if PIN enrolled.
@MainActor
public final class LockTriggerMonitor {

    // MARK: - Public types

    public enum LockTimeout: Sendable {
        case immediate
        case minutes(Int)
        case never

        var seconds: TimeInterval? {
            switch self {
            case .immediate:     return 0
            case .minutes(let m): return TimeInterval(m * 60)
            case .never:         return nil
            }
        }
    }

    // MARK: - Dependencies

    private let onLockRequired: @MainActor () -> Void
    private var timeout: LockTimeout
    private var backgroundedAt: Date? = nil
    private var observers: [NSObjectProtocol] = []

    // MARK: - Init

    /// - Parameters:
    ///   - timeout:   How long in the background before requiring re-lock.
    ///                Default: 5 minutes.
    ///   - onLockRequired: Called on the main actor when the lock should engage.
    public init(
        timeout: LockTimeout = .minutes(5),
        onLockRequired: @escaping @MainActor () -> Void
    ) {
        self.timeout = timeout
        self.onLockRequired = onLockRequired
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Public API

    /// Begin monitoring. Call once from `AppDelegate` / `App.onAppear`.
    public func start() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.backgroundedAt = Date()
        })

        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkLockRequired()
        })
    }

    /// Update the timeout setting (e.g. from Settings).
    public func setLockTimeout(_ newTimeout: LockTimeout) {
        timeout = newTimeout
    }

    /// Explicitly trigger a lock (e.g. "Lock now" from Settings or avatar menu).
    public func lockNow() {
        guard PINStore.shared.isEnrolled else { return }
        onLockRequired()
    }

    // MARK: - Private

    private func checkLockRequired() {
        guard PINStore.shared.isEnrolled else { return }
        guard let bg = backgroundedAt else { return }
        defer { backgroundedAt = nil }

        guard let limitSeconds = timeout.seconds else { return } // .never

        let elapsed = Date().timeIntervalSince(bg)
        if elapsed >= limitSeconds {
            onLockRequired()
        }
    }
}

#endif
