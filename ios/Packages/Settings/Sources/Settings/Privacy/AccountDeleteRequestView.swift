import SwiftUI
import Core
import DesignSystem
import Networking

// §28.13 GDPR Compliance — account-delete request copy + soft-delete flow
//
// Surface: Settings → Privacy → "Delete my account"
//
// Distinction from DangerZone "Delete tenant":
//   - Delete tenant: hard-deletes the whole shop (owner/admin only, PIN-gated).
//   - Delete my account: GDPR/CCPA personal-data erasure request for the
//     signed-in staff member. Tombstones PII; preserves financial records
//     (legal retention). Processed async by the server; user receives email.
//
// 30-day grace period: server sets status = "pending_deletion". User can
// cancel within 30 days by signing in. After 30 days, server runs the wipe.

// MARK: - ViewModel

@Observable
@MainActor
public final class AccountDeleteRequestViewModel {

    // MARK: State

    public private(set) var isSubmitting: Bool = false
    public private(set) var isSubmitted: Bool = false
    public private(set) var errorMessage: String? = nil

    public var confirmationText: String = ""

    // MARK: Dependencies

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    // MARK: Computed

    /// Required confirmation phrase the user must type before submitting.
    public static let requiredPhrase = "DELETE"

    public var canSubmit: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == Self.requiredPhrase
    }

    // MARK: Actions

    public func submitDeletionRequest() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await api?.requestAccountDeletion()
            isSubmitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearError() { errorMessage = nil }
}

// MARK: - API extension

private extension APIClient {
    func requestAccountDeletion() async throws {
        struct EmptyBody: Encodable {}
        _ = try await post(
            "/auth/request-account-deletion",
            body: EmptyBody(),
            as: EmptyResponse.self
        )
    }

    private struct EmptyResponse: Decodable {}
}

// MARK: - View

/// Settings → Privacy → "Delete my account"
///
/// Submits a GDPR/CCPA right-to-erasure request for the signed-in user.
/// A 30-day grace period applies; the user receives a confirmation email.
public struct AccountDeleteRequestView: View {

    @State private var vm: AccountDeleteRequestViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: AccountDeleteRequestViewModel(api: api))
    }

    public var body: some View {
        if vm.isSubmitted {
            submittedState
        } else {
            requestForm
        }
    }

    // MARK: - Submitted state

    private var submittedState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Deletion Request Received")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Your personal data will be erased within 30 days. You will receive a confirmation email. If you change your mind, sign in to cancel the request before the 30-day period ends.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle("Account Deletion")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Request form

    private var requestForm: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What gets deleted", systemImage: "trash.circle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    deletionScopeRows
                }
                .padding(.vertical, 4)
            } header: {
                Text("Erasure scope")
            } footer: {
                Text("Financial records (invoices, receipts) are retained for legal compliance. All other personal data is permanently erased.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grace period")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Text("Your request will be processed within **30 days**. During this time you can cancel by signing in to your account. After 30 days, deletion is irreversible.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type \"\(AccountDeleteRequestViewModel.requiredPhrase)\" to confirm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField(
                        AccountDeleteRequestViewModel.requiredPhrase,
                        text: $vm.confirmationText
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .accessibilityLabel("Type DELETE to confirm account deletion")
                    .accessibilityIdentifier("privacy.deleteConfirmField")
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    Task { await vm.submitDeletionRequest() }
                } label: {
                    if vm.isSubmitting {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Submitting…")
                        }
                    } else {
                        Label("Submit deletion request", systemImage: "person.crop.circle.badge.minus")
                    }
                }
                .disabled(!vm.canSubmit || vm.isSubmitting)
                .accessibilityLabel("Submit account deletion request")
                .accessibilityHint("Permanently erases your personal data after a 30-day grace period. This cannot be undone.")
                .accessibilityIdentifier("privacy.submitDeleteRequest")
            } header: {
                Text("Confirm")
            } footer: {
                Text("Under GDPR Article 17 and CCPA §1798.105, you have the right to erasure of personal data. This does not close the shop — contact your administrator to delete the tenant.")
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Delete My Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Helpers

    private var deletionScopeRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            deletionRow(included: true,  text: "Your profile: name, email, phone, avatar")
            deletionRow(included: true,  text: "Login history and active sessions")
            deletionRow(included: true,  text: "Personal preferences and settings")
            deletionRow(included: false, text: "Invoices and financial records (legal retention)")
            deletionRow(included: false, text: "Anonymised audit log entries")
        }
    }

    private func deletionRow(included: Bool, text: String) -> some View {
        Label {
            Text(text)
                .font(.callout)
                .foregroundStyle(included ? .primary : .secondary)
        } icon: {
            Image(systemName: included ? "trash.fill" : "archivebox.fill")
                .foregroundStyle(included ? .bizarreError : .bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("\(included ? "Will be deleted" : "Retained"): \(text)")
    }
}
