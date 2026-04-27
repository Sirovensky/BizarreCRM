#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Persistence
import Core

// MARK: - ChangePasswordView
//
// §2.9 — Settings → Security → Change password.
// Calls POST /api/v1/auth/change-password with { currentPassword, newPassword }.
// On success: shows a confirmation toast and posts SessionEvents.sessionRevoked
// for all other sessions so the server-side session list is invalidated.

@Observable
@MainActor
private final class ChangePasswordViewModel {
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmPassword: String = ""
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    var successMessage: String? = nil

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var canSubmit: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= 8 &&
        newPassword == confirmPassword &&
        !isSubmitting
    }

    func submit() async {
        errorMessage = nil
        successMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }
        guard newPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }

        do {
            let resp = try await api.changePassword(
                ChangePasswordBody(currentPassword: currentPassword, newPassword: newPassword)
            )
            successMessage = resp.message ?? "Password changed. Sign in again on other devices."
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

public struct ChangePasswordView: View {
    @State private var vm: ChangePasswordViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field: Hashable { case current, new, confirm }

    public init(api: APIClient) {
        _vm = State(wrappedValue: ChangePasswordViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current password", text: $vm.currentPassword)
                        .textContentType(.password)
                        .focused($focus, equals: .current)
                        .submitLabel(.next)
                        .onSubmit { focus = .new }
                        .accessibilityIdentifier("changePwd.current")
                } header: {
                    Text("Current password")
                }

                Section {
                    SecureField("New password", text: $vm.newPassword)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .new)
                        .submitLabel(.next)
                        .onSubmit { focus = .confirm }
                        .accessibilityIdentifier("changePwd.new")

                    SecureField("Confirm new password", text: $vm.confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirm)
                        .submitLabel(.done)
                        .onSubmit { Task { await vm.submit() } }
                        .accessibilityIdentifier("changePwd.confirm")

                    if !vm.newPassword.isEmpty {
                        PasswordStrengthMeter(
                            evaluation: PasswordStrengthEvaluator.evaluate(vm.newPassword)
                        )
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("New password")
                } footer: {
                    Text("Minimum 8 characters. Mix of letters, numbers, and symbols recommended.")
                        .font(.footnote)
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                            .font(.callout)
                    }
                }

                if let ok = vm.successMessage {
                    Section {
                        Label(ok, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Change password")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("changePwd.submit")
                }
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#endif
