import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §19.1 Change email — server emits verify-email link; banner until verified.
//
// Flow:
//  1. User taps "Change email" in Profile settings.
//  2. Sheet opens: enter new email + current password for verification.
//  3. POST /auth/change-email { newEmail, password }
//  4. Server sends a verification email to the new address.
//  5. Sheet dismisses with a success banner: "Check your inbox to confirm new email."
//  6. Unverified banner stays in Profile until the user clicks the link (server
//     flips verified flag; iOS sees it next `GET /auth/me` refresh).

// MARK: - ViewModel

@MainActor
@Observable
final class ChangeEmailViewModel {
    var newEmail: String = ""
    var currentPassword: String = ""
    var isSaving: Bool = false
    var errorMessage: String?

    var canSubmit: Bool {
        !newEmail.trimmingCharacters(in: .whitespaces).isEmpty
            && newEmail.contains("@")
            && !currentPassword.isEmpty
    }

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func submit() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            try await api.settingsRequestEmailChange(newEmail: newEmail, currentPassword: currentPassword)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Sheet View

struct ChangeEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ChangeEmailViewModel

    /// Called with `true` when the server accepted the request (verification email sent).
    var onComplete: (Bool) -> Void

    init(api: APIClient, onComplete: @escaping (Bool) -> Void) {
        _vm = State(wrappedValue: ChangeEmailViewModel(api: api))
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your new email address and current password. We'll send a verification link to the new address.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .listRowBackground(Color.clear)
                }

                Section("New email") {
                    TextField("new@example.com", text: $vm.newEmail)
                        #if canImport(UIKit)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif
                        .accessibilityLabel("New email address")
                        .accessibilityIdentifier("changeEmail.newEmail")
                }

                Section("Confirm identity") {
                    SecureField("Current password", text: $vm.currentPassword)
                        #if canImport(UIKit)
                        .textContentType(.password)
                        #endif
                        .accessibilityLabel("Current password")
                        .accessibilityIdentifier("changeEmail.currentPassword")
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                            .accessibilityLabel("Error: \(err)")
                    }
                    .listRowBackground(Color.bizarreError.opacity(0.08))
                }

                Section {
                    Button {
                        Task {
                            let ok = await vm.submit()
                            if ok {
                                dismiss()
                                onComplete(true)
                            }
                        }
                    } label: {
                        if vm.isSaving {
                            HStack {
                                ProgressView().tint(.white)
                                Text("Sending verification…")
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Send verification link")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Color.bizarreOrange.opacity(vm.canSubmit ? 1 : 0.5))
                    .disabled(!vm.canSubmit || vm.isSaving)
                    .accessibilityIdentifier("changeEmail.submit")
                }
            }
            .navigationTitle("Change email")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("changeEmail.cancel")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Unverified email banner (displayed in ProfileSettingsPage after request sent)

/// Glass banner shown after a change-email request is pending.
/// Dismissed automatically on next profile refresh if verified.
struct PendingEmailVerificationBanner: View {
    let newEmail: String
    var onResend: (() -> Void)?

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "envelope.badge")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Verify your new email")
                    .font(.brandBodyLarge().weight(.semibold))
                    .foregroundStyle(.bizarreOnSurface)
                Text("Check \(newEmail) for a verification link.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }

            Spacer()

            if let resend = onResend {
                Button("Resend") { resend() }
                    .font(.brandLabelSmall().weight(.semibold))
                    .foregroundStyle(.bizarreOrange)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreWarning.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Email change pending. Check \(newEmail) for a verification link.")
    }
}
