import Foundation
import OSLog

// §29.12 Low Power Mode detection (line 4481).
//
// Observes `NSProcessInfoPowerStateDidChangeNotification` and logs the
// transition via `AppLog.perf`. Call sites (e.g. SyncOrchestrator, image
// prefetch) can subscribe to `isLowPowerMode` via `AsyncStream` or read
// the current value directly via `LowPowerModeObserver.shared.isEnabled`.

/// Observes OS Low Power Mode state and publishes changes via `AppLog.perf`.
///
/// `LowPowerModeObserver` is `@MainActor` because it mutates `isEnabled` which
/// is read by SwiftUI — keeping it on the main actor avoids data races.
///
/// ## Usage
/// ```swift
/// // Start listening (call once, e.g. in AppDelegate / app init):
/// LowPowerModeObserver.shared.start()
///
/// // Read current state:
/// if LowPowerModeObserver.shared.isEnabled { … }
///
/// // Async stream of Bool changes:
/// for await isLow in LowPowerModeObserver.shared.changes { … }
/// ```
@MainActor
public final class LowPowerModeObserver {

    // MARK: - Shared instance

    public static let shared = LowPowerModeObserver()

    // MARK: - Public state

    /// `true` when Low Power Mode is currently active.
    public private(set) var isEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    // MARK: - AsyncStream subscribers

    /// Delivers `true`/`false` on every LPM transition. Callers `break`
    /// or cancel their `Task` when they no longer need updates.
    public var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            _continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?._continuations.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - Private

    private var _continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var _observerToken: NSObjectProtocol?

    private init() {}

    // MARK: - Lifecycle

    /// Starts listening for Low Power Mode changes. Call once at app start.
    ///
    /// Calling `start()` more than once is safe — subsequent calls are no-ops.
    public func start() {
        guard _observerToken == nil else { return }

        _observerToken = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handlePowerStateChange()
            }
        }

        AppLog.perf.info(
            "[LowPowerMode] observer started; current=\(self.isEnabled ? "ON" : "OFF", privacy: .public)"
        )
    }

    /// Stops listening and cancels all outstanding `changes` streams.
    public func stop() {
        if let token = _observerToken {
            NotificationCenter.default.removeObserver(token)
            _observerToken = nil
        }
        _continuations.values.forEach { $0.finish() }
        _continuations.removeAll()
    }

    // MARK: - Private helpers

    private func handlePowerStateChange() {
        let nowEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard nowEnabled != isEnabled else { return }
        isEnabled = nowEnabled

        AppLog.perf.info(
            "[LowPowerMode] changed → \(nowEnabled ? "ON" : "OFF", privacy: .public)"
        )

        for continuation in _continuations.values {
            continuation.yield(nowEnabled)
        }
    }
}
