#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - §2.5 Forgot PIN — email reset flow

/// Presented when a staff member taps "Forgot PIN" on the PIN entry screen.
/// Sends a reset link to the tenant-registered email for this account.
///
/// Flow:
/// 1. User taps "Forgot PIN" — this view appears as a sheet.
/// 2. App calls `POST /auth/pin-reset-request` with the user's ID.
/// 3. Server emails a one-time link to the staff member's registered email.
/// 4. Staff follows the link (web), sets a new PIN, then re-enters the app.
///
/// **Security:** The link is tied to the tenant account email. The iOS side
/// only triggers the server-side email; no PIN data flows through this view.
public struct PinForgotView: View {

    // MARK: - State

    @State private var viewModel: PinForgotViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    public init(userId: String, userName: String, api: APIClient) {
        _viewModel = State(wrappedValue: PinForgotViewModel(userId: userId, userName: userName, api: api))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            headerIcon

            VStack(spacing: BrandSpacing.sm) {
                Text("Forgot your PIN?")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text("We'll send a reset link to the email address registered for \(viewModel.userName). Follow the link to set a new PIN.")
                    .font(.brandBodySmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if viewModel.isSent {
                sentConfirmation
            } else {
                sendButton
            }

            if let error = viewModel.errorMessage {
                errorLabel(error)
            }

            Button("Cancel") { dismiss() }
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .padding(.bottom, BrandSpacing.base)
        }
        .padding(BrandSpacing.xxxl)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Sub-views

    private var headerIcon: some View {
        Image(systemName: "envelope.badge.shield.half.filled")
            .font(.system(size: 48))
            .foregroundStyle(Color.bizarreOrange)
            .padding(.top, BrandSpacing.xxxl)
            .accessibilityHidden(true)
    }

    private var sentConfirmation: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.bizarreSuccess)

            Text("Reset link sent.")
                .font(.brandTitleMedium().bold())
                .foregroundStyle(Color.bizarreOnSurface)

            Text("Check your email and follow the link to choose a new PIN.")
                .font(.brandBodySmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reset link sent. Check your email to set a new PIN.")
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.sendResetLink() }
        } label: {
            HStack {
                if viewModel.isSending {
                    ProgressView().tint(Color.bizarreOnOrange)
                }
                Text("Send Reset Link")
                    .font(.brandTitleMedium().bold())
            }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(Color.bizarreOrange)
        .foregroundStyle(Color.bizarreOnOrange)
        .disabled(viewModel.isSending)
        .accessibilityIdentifier("pinForgot.send")
    }

    private func errorLabel(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.bizarreError)
                .imageScale(.small)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreError)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pinForgot.error")
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class PinForgotViewModel {

    let userId: String
    let userName: String

    var isSending = false
    var isSent = false
    var errorMessage: String? = nil

    private let api: APIClient

    init(userId: String, userName: String, api: APIClient) {
        self.userId = userId
        self.userName = userName
        self.api = api
    }

    func sendResetLink() async {
        isSending = true
        errorMessage = nil
        do {
            try await api.pinResetRequest(userId: userId)
            isSent = true
        } catch {
            errorMessage = "Could not send the reset link. Please contact your manager."
        }
        isSending = false
    }
}

#endif
