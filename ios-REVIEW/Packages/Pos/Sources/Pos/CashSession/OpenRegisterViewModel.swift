import Foundation
import Persistence

/// §39 — ViewModel that drives `OpenRegisterSheet`.
///
/// Validates the float input, calls `CashSessionRepository.openSession`,
/// and exposes a typed result state. Designed for injection-based testing
/// without UIKit or a live DB.
///
/// All state mutations happen on `@MainActor` so bindings are safe from
/// SwiftUI views.
@Observable
@MainActor
public final class OpenRegisterViewModel {

    // MARK: - State

    /// Raw text bound to the float `TextField`.
    public var floatText: String = "0.00"

    /// `true` while the async open call is in flight.
    public private(set) var isSubmitting: Bool = false

    /// Non-nil when an error should be surfaced to the user.
    public private(set) var errorMessage: String?

    /// Non-nil after a successful open — drives the parent's `onOpened` callback.
    public private(set) var openedSession: CashSessionRecord?

    // MARK: - Dependencies

    private let repository: CashSessionRepository
    private let userId: Int64

    // MARK: - Init

    public init(userId: Int64, repository: CashSessionRepository) {
        self.userId = userId
        self.repository = repository
    }

    // MARK: - Derived

    /// `true` when the float field holds a valid non-negative Decimal.
    public var isValid: Bool {
        guard let value = parsedFloat else { return false }
        return value >= 0
    }

    /// Parsed Decimal value of `floatText`, or `nil` if unparseable.
    public var parsedFloat: Decimal? {
        Decimal(string: floatText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Opening float in cents, derived from `floatText`.
    public var floatCents: Int {
        guard let d = parsedFloat else { return 0 }
        return CartMath.toCents(d)
    }

    // MARK: - Actions

    /// Validate and open a new session. On success `openedSession` is set.
    /// On failure `errorMessage` is populated with a user-friendly string.
    public func submit() async {
        guard !isSubmitting else { return }
        guard isValid else {
            errorMessage = "Enter a valid non-negative amount."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        do {
            let record = try await repository.openSession(
                openingFloatCents: floatCents,
                userId: userId
            )
            openedSession = record
        } catch CashRegisterError.alreadyOpen {
            // Surface current session so the host can continue.
            let current = try? await repository.currentSession()
            if let current {
                openedSession = current
            } else {
                errorMessage = "A session is already open."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clear any pending error (e.g., on text change).
    public func clearError() {
        errorMessage = nil
    }
}
