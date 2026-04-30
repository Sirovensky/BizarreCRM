import Foundation
import UserNotifications
import Core

// MARK: - §70 Push token retry with exponential backoff + manual "Re-register" trigger

/// Manages APNs token registration retries with exponential backoff.
///
/// When `PushRegistrationService.registerIfAuthorized()` fails (network down,
/// server error), this service retries with doubling delays up to `maxDelay`.
///
/// Wire from `PushRegistrationService` or app-shell after a network error.
/// The manual "Re-register" trigger in Settings → Notifications calls `retryNow()`.
public actor PushTokenRetryService {

    // MARK: - Shared

    nonisolated(unsafe) public static let shared = PushTokenRetryService()

    // MARK: - Constants

    public static let initialDelay: TimeInterval = 5    // 5 s
    public static let maxDelay: TimeInterval     = 300  // 5 min
    public static let maxAttempts                = 8

    // MARK: - State

    public private(set) var attemptCount: Int = 0
    public private(set) var lastError: String?
    public private(set) var nextRetryAt: Date?
    public private(set) var isRetrying: Bool = false

    private var retryTask: Task<Void, Never>?
    private let registrationService: PushRegistrationService

    // MARK: - Init

    public init(registrationService: PushRegistrationService = .shared) {
        self.registrationService = registrationService
    }

    // MARK: - Public API

    /// Start the retry loop after an initial failure.
    /// No-op if a retry is already in progress.
    public func startRetryLoop() {
        guard !isRetrying else { return }
        isRetrying = true
        retryTask = Task { [weak self] in
            await self?.run()
        }
    }

    /// Cancel any in-flight retry loop.
    public func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        isRetrying = false
    }

    /// Manual "Re-register" trigger — resets counters and immediately attempts
    /// one registration.  Called from Settings → Notifications button.
    public func retryNow() async {
        attemptCount = 0
        lastError = nil
        nextRetryAt = nil
        cancelRetry()
        await attempt()
    }

    /// Reset all state (call on successful registration).
    public func reset() {
        cancelRetry()
        attemptCount = 0
        lastError = nil
        nextRetryAt = nil
    }

    // MARK: - Private

    private func run() async {
        while attemptCount < Self.maxAttempts {
            let delay = Self.backoffDelay(attempt: attemptCount)
            nextRetryAt = Date(timeIntervalSinceNow: delay)
            AppLog.ui.info("PushTokenRetry: attempt \(self.attemptCount + 1)/\(Self.maxAttempts) in \(delay, format: .fixed(precision: 1))s")
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                // Cancelled — stop.
                isRetrying = false
                return
            }
            await attempt()
            if !isRetrying { return } // Successful → reset() called.
            attemptCount += 1
        }
        AppLog.ui.error("PushTokenRetry: exhausted \(Self.maxAttempts) attempts")
        isRetrying = false
    }

    private func attempt() async {
        do {
            _ = try await registrationService.registerIfAuthorized()
            AppLog.ui.info("PushTokenRetry: registration succeeded")
            reset()
        } catch {
            lastError = error.localizedDescription
            AppLog.ui.error("PushTokenRetry: attempt failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Backoff helper

    /// Returns exponential delay for the given `attempt` (0-based).
    /// Formula: `min(initialDelay × 2^attempt, maxDelay)` with ±10% jitter.
    public static func backoffDelay(attempt: Int) -> TimeInterval {
        let base = min(initialDelay * pow(2.0, Double(attempt)), maxDelay)
        let jitter = base * 0.1 * (Double.random(in: -1...1))
        return max(1, base + jitter)
    }
}
