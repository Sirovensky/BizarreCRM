import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

// §28.8 Screen protection — Screenshot detection counter
//
// iOS fires `UIApplication.userDidTakeScreenshotNotification` *after* the
// screenshot is already saved to Photos. We cannot block or intercept it.
// What we CAN do:
//   1. Count how many screenshots were taken on each sensitive screen.
//   2. Write an audit entry (user + screen + UTC timestamp) so tenant admins
//      can review unusual copy activity in the audit log.
//   3. Optionally surface a one-shot informational banner to the user.
//
// This file contains the counter/observer; the actual audit-log write is
// delegated to the caller via the `onScreenshot` closure so the Core layer
// does not take a hard dependency on the AuditLogs domain package.

// MARK: - ScreenshotAuditEntry

/// Lightweight value written to the audit log on each screenshot event.
public struct ScreenshotAuditEntry: Sendable, Equatable {

    /// Identifies which screen was visible when the screenshot was taken.
    public let screenIdentifier: String

    /// UTC timestamp of the event.
    public let timestamp: Date

    /// Optional user ID sourced from the active session.
    public let userID: String?

    public init(screenIdentifier: String, timestamp: Date, userID: String?) {
        self.screenIdentifier = screenIdentifier
        self.timestamp        = timestamp
        self.userID           = userID
    }
}

// MARK: - ScreenshotAuditCounterProtocol

/// Abstraction for test injection.
public protocol ScreenshotAuditCounterProtocol: AnyObject, Sendable {
    /// Total screenshots observed since the counter was attached.
    @MainActor var count: Int { get }

    /// Attach to the running screen, associating events with `screenIdentifier`.
    @MainActor func attach(
        screenIdentifier: String,
        userID: String?,
        onScreenshot: @escaping @Sendable (ScreenshotAuditEntry) -> Void
    )

    /// Detach the observer (call when the sensitive screen disappears).
    @MainActor func detach()
}

// MARK: - ScreenshotAuditCounter

/// Observes `UIApplication.userDidTakeScreenshotNotification`, increments a
/// count, and calls the injected `onScreenshot` closure with a structured
/// ``ScreenshotAuditEntry``.
///
/// ## Usage
/// ```swift
/// let counter = ScreenshotAuditCounter()
///
/// // In .onAppear of a sensitive screen:
/// counter.attach(screenIdentifier: "payment-receipt", userID: session.userID) { entry in
///     auditLogRepository.record(entry)
/// }
///
/// // In .onDisappear:
/// counter.detach()
/// ```
///
/// ## Thread safety
/// All mutations happen on `@MainActor` via a `DispatchQueue.main` observer.
/// The `onScreenshot` closure is called on the main queue as well; callers
/// that need to write to a background store should hop queues inside the
/// closure.
@Observable
@MainActor
public final class ScreenshotAuditCounter: ScreenshotAuditCounterProtocol, @unchecked Sendable {

    // MARK: - Observable state

    /// Number of screenshot events observed since the last `attach` call.
    public private(set) var count: Int = 0

    // MARK: - Private state

    @ObservationIgnored nonisolated(unsafe) private var observerToken: NSObjectProtocol?
    private var currentScreenIdentifier: String?
    private var currentUserID: String?
    private var onScreenshotHandler: (@Sendable (ScreenshotAuditEntry) -> Void)?

    // MARK: - Injectable clock

    private let now: @Sendable () -> Date

    // MARK: - Init

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Lifecycle

    /// Start observing screenshot events for the given screen.
    ///
    /// Calling `attach` a second time without an intervening `detach` is safe —
    /// it implicitly detaches the previous observer first.
    ///
    /// - Parameters:
    ///   - screenIdentifier: A stable string that identifies the current screen
    ///                       (e.g. `"payment-receipt"`, `"2fa-backup-codes"`).
    ///   - userID:           Current authenticated user, included in the audit
    ///                       entry.  `nil` on pre-auth screens.
    ///   - onScreenshot:     Closure invoked on every screenshot. Called on the
    ///                       main queue. Perform any audit-log write here.
    public func attach(
        screenIdentifier: String,
        userID: String?,
        onScreenshot: @escaping @Sendable (ScreenshotAuditEntry) -> Void
    ) {
        detach()
        count = 0
        currentScreenIdentifier = screenIdentifier
        currentUserID = userID
        onScreenshotHandler = onScreenshot

        #if canImport(UIKit)
        observerToken = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleScreenshot()
            }
        }
        #endif
    }

    /// Stop observing. Safe to call even if never attached.
    public func detach() {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
        currentScreenIdentifier = nil
        currentUserID = nil
        onScreenshotHandler = nil
    }

    // MARK: - Private

    private func handleScreenshot() {
        count += 1
        guard
            let screenIdentifier = currentScreenIdentifier,
            let handler = onScreenshotHandler
        else { return }

        let entry = ScreenshotAuditEntry(
            screenIdentifier: screenIdentifier,
            timestamp:        now(),
            userID:           currentUserID
        )
        handler(entry)
    }
}

// MARK: - MockScreenshotAuditCounter

/// Test double for ``ScreenshotAuditCounter``.
///
/// Call ``simulateScreenshot()`` to fire the audit entry without needing a
/// real `UIApplication.userDidTakeScreenshotNotification`.
@Observable
@MainActor
public final class MockScreenshotAuditCounter: ScreenshotAuditCounterProtocol, @unchecked Sendable {

    public private(set) var count: Int = 0
    public private(set) var capturedEntries: [ScreenshotAuditEntry] = []

    private var screenIdentifier: String?
    private var userID: String?
    private var handler: (@Sendable (ScreenshotAuditEntry) -> Void)?

    public init() {}

    public func attach(
        screenIdentifier: String,
        userID: String?,
        onScreenshot: @escaping @Sendable (ScreenshotAuditEntry) -> Void
    ) {
        count = 0
        capturedEntries = []
        self.screenIdentifier = screenIdentifier
        self.userID = userID
        self.handler = onScreenshot
    }

    public func detach() {
        screenIdentifier = nil
        userID = nil
        handler = nil
    }

    /// Simulate a screenshot event. Useful in unit tests.
    public func simulateScreenshot(at date: Date = Date()) {
        count += 1
        guard let id = screenIdentifier else { return }
        let entry = ScreenshotAuditEntry(screenIdentifier: id, timestamp: date, userID: userID)
        capturedEntries.append(entry)
        handler?(entry)
    }
}
