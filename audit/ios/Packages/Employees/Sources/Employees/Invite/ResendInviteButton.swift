import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ResendInviteButton
//
// §14.4 Resend invite — PUT /api/v1/settings/users/:id with resend_invite: true.
// Admin-only action shown in EmployeeDetailView's admin actions card
// for employees who haven't set their password yet (password_set = 0 or nil).
//
// Note: the server does not yet have a dedicated "resend invite" endpoint.
// When the server adds it (see §74 gap), the endpoint here can be updated.
// For now, this surfaces the UI affordance and calls the best available route.

@MainActor
@Observable
public final class ResendInviteViewModel {
    public private(set) var isSending: Bool = false
    public private(set) var result: ResendResult?
    public internal(set) var errorMessage: String?

    public enum ResendResult { case sent, noEmail }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let userId: Int64
    @ObservationIgnored private let hasEmail: Bool

    public init(api: APIClient, userId: Int64, hasEmail: Bool) {
        self.api = api
        self.userId = userId
        self.hasEmail = hasEmail
    }

    public func resend() async {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await api.resendEmployeeInvite(userId: userId)
            result = hasEmail ? .sent : .noEmail
        } catch {
            AppLog.ui.error("ResendInvite failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func clearResult() { result = nil }
}

/// Button + confirmation flow for the Resend Invite action.
/// Drop this inside EmployeeDetailView's admin actions section.
public struct ResendInviteButton: View {
    @State private var vm: ResendInviteViewModel
    @State private var showConfirm: Bool = false
    @State private var showSuccess: Bool = false
    private let displayName: String

    public init(api: APIClient, userId: Int64, displayName: String, hasEmail: Bool) {
        _vm = State(wrappedValue: ResendInviteViewModel(api: api, userId: userId, hasEmail: hasEmail))
        self.displayName = displayName
    }

    public var body: some View {
        Button {
            showConfirm = true
        } label: {
            if vm.isSending {
                HStack(spacing: BrandSpacing.xs) {
                    ProgressView().scaleEffect(0.8)
                    Text("Sending invite…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                Label("Resend Invite", systemImage: "envelope.arrow.triangle.branch")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.bizarreOrange)
            }
        }
        .disabled(vm.isSending)
        .accessibilityLabel("Resend invite to \(displayName)")
        .confirmationDialog(
            "Resend invite to \(displayName)?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Resend Invite") {
                Task { await vm.resend() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will send a fresh set of login credentials to the employee.")
        }
        .alert(
            isPresented: Binding(
                get: { vm.result != nil },
                set: { if !$0 { vm.clearResult() } }
            )
        ) {
            switch vm.result {
            case .sent:
                Alert(
                    title: Text("Invite Sent"),
                    message: Text("Login credentials have been emailed to \(displayName)."),
                    dismissButton: .default(Text("OK"))
                )
            case .noEmail:
                Alert(
                    title: Text("Account Updated"),
                    message: Text("\(displayName) has no email on file. Share credentials manually."),
                    dismissButton: .default(Text("OK"))
                )
            case .none:
                Alert(title: Text(""))
            }
        }
        .alert("Resend failed", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
