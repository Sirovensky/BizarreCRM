import Foundation
import Core

// MARK: - §2.13 Challenge token expiry (10 min)

/// Tracks when an auth challenge token was issued and signals the caller when
/// the 10-minute window has passed.
///
/// Challenge tokens are short-lived (10 min per §2.13). If the user idles on
/// a 2FA, set-password, or forgot-password step and the token expires, we must
/// prompt them to restart the login flow rather than letting them submit a dead
/// challenge token to the server.
///
/// **Integration in `LoginFlow`:**
/// ```swift
/// private var challengeExpiryTask: Task<Void, Never>? = nil
///
/// func beginChallenge() {
///     challengeExpiryTask?.cancel()
///     challengeExpiryTask = ChallengeTokenExpiry.start {
///         // Token expired — restart to the server step
///         self.step = .credentials
///         self.errorMessage = "Session expired. Please sign in again."
///     }
/// }
/// ```
public enum ChallengeTokenExpiry {

    private static let windowSeconds: UInt64 = 10 * 60  // 10 minutes

    /// Starts a detached task that fires `onExpired` after 10 minutes.
    /// - Parameter onExpired: Closure called on the **main actor** when the
    ///   window elapses. Safe to call UI/state mutations directly.
    /// - Returns: The background `Task`; cancel it if the challenge resolves
    ///   before the timer fires (success / user navigates away).
    @discardableResult
    public static func start(onExpired: @MainActor @escaping () -> Void) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: windowSeconds * 1_000_000_000)
                await MainActor.run { onExpired() }
            } catch {
                // Task was cancelled — challenge resolved in time. No action.
                AppLog.auth.debug("Challenge token expiry task cancelled (resolved early)")
            }
        }
    }
}
