import Foundation
import Observation
import Networking
import Core

// MARK: - §2.9 Change password view model

@MainActor
@Observable
public final class ChangePasswordViewModel {

    // MARK: State

    public var currentPassword: String = ""
    public var newPassword: String = ""
    public var confirmPassword: String = ""
    public var isSubmitting: Bool = false
    public var errorMessage: String? = nil
    public var successMessage: String? = nil

    // MARK: Derived

    public var evaluation: PasswordEvaluation {
        PasswordStrengthEvaluator.evaluate(newPassword)
    }

    public var mismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    public var canSubmit: Bool {
        !currentPassword.isEmpty &&
        evaluation.rules.allPassed &&
        newPassword == confirmPassword &&
        !isSubmitting
    }

    // MARK: Dependencies

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: Actions

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            try await api.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            successMessage = "Password updated. Other sessions will be signed out."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch APITransportError.httpStatus(let code, _) where code == 401 {
            errorMessage = "Current password is incorrect."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
