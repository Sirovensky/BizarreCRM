import Foundation
import Observation
import Core

/// §2 Magic-link login — view model.
///
/// State machine:
/// ```
/// .idle → .sending → .sent → [user taps deep link] → .verifying → .success
///                    .sent → .failed(AppError)
///       → .failed(AppError)
/// ```
@MainActor
@Observable
public final class MagicLinkViewModel {

    // MARK: - State

    public enum State: Equatable, Sendable {
        case idle
        case sending
        case sent
        case verifying
        case success(authToken: String)
        case failed(AppError)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.sending, .sending), (.sent, .sent),
                 (.verifying, .verifying): return true
            case (.success(let a), .success(let b)): return a == b
            case (.failed, .failed): return true
            default: return false
            }
        }
    }

    public var state: State = .idle
    public var email: String = ""
    public var errorMessage: String? = nil

    // MARK: - Resend cooldown (60 s)

    public private(set) var resendCooldownRemaining: Int = 0
    private var cooldownTask: Task<Void, Never>? = nil

    // MARK: - Dependencies

    private let repository: MagicLinkRepository

    public init(repository: MagicLinkRepository) {
        self.repository = repository
    }

    // MARK: - Actions

    /// Request a magic link for the current email address.
    public func sendMagicLink() async {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter your email address."
            return
        }
        guard email.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard state != .sending else { return }

        errorMessage = nil
        state = .sending

        do {
            _ = try await repository.requestLink(email: email)
            state = .sent
            startResendCooldown()
        } catch let appError as AppError {
            state = .failed(appError)
            errorMessage = userMessage(for: appError)
        } catch {
            let wrapped = AppError.from(error)
            state = .failed(wrapped)
            errorMessage = userMessage(for: wrapped)
        }
    }

    /// Called by DeepLinkRouter when a magic-link URL is opened.
    public func handleIncomingToken(_ token: String) async {
        guard state == .sent || state == .idle else { return }
        errorMessage = nil
        state = .verifying

        do {
            let response = try await repository.verifyToken(token)
            state = .success(authToken: response.authToken)
        } catch let appError as AppError {
            state = .failed(appError)
            errorMessage = userMessage(for: appError)
        } catch {
            let wrapped = AppError.from(error)
            state = .failed(wrapped)
            errorMessage = userMessage(for: wrapped)
        }
    }

    /// Restart from the failed / sent state — back to idle so user can edit email.
    public func reset() {
        cooldownTask?.cancel()
        cooldownTask = nil
        resendCooldownRemaining = 0
        state = .idle
        errorMessage = nil
    }

    // MARK: - Private helpers

    private func startResendCooldown() {
        cooldownTask?.cancel()
        resendCooldownRemaining = 60
        cooldownTask = Task { [weak self] in
            var remaining = 60
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run { self?.resendCooldownRemaining = remaining }
            }
        }
    }

    private func userMessage(for error: AppError) -> String {
        switch error {
        case .network:    return "Network error — check your connection and try again."
        case .offline:    return "You appear to be offline. Connect and try again."
        case .notFound:   return "No account found for that email address."
        case .rateLimited(let after):
            if let secs = after {
                return "Too many attempts. Try again in \(secs) seconds."
            }
            return "Too many attempts. Try again shortly."
        default:          return "Something went wrong. Please try again."
        }
    }
}
