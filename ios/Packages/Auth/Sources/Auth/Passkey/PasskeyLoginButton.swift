#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - PasskeyLoginButton
//
// Reusable "Sign in with Passkey" button for LoginFlowView (credentials panel).
// On tap: authenticate/begin → OS sheet → authenticate/complete → onSuccess(token).
// iPhone + iPad: identical appearance — OS sheet handles layout differences.

public struct PasskeyLoginButton: View {
    @State private var vm: PasskeyViewModel
    private let username: String?
    private let onSuccess: @MainActor (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        viewModel: PasskeyViewModel,
        username: String? = nil,
        onSuccess: @escaping @MainActor (String) -> Void
    ) {
        self._vm = State(wrappedValue: viewModel)
        self.username = username
        self.onSuccess = onSuccess
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                Task { await vm.signIn(username: username) }
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .tint(.bizarreOnSurface)
                            .controlSize(.small)
                            .transition(reduceMotion ? .identity : .opacity)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                            .imageScale(.medium)
                            .accessibilityHidden(true)
                    }
                    Text("Sign in with Passkey")
                        .font(.brandTitleMedium())
                }
            }
            .buttonStyle(.brandGlass)
            .tint(.bizarreTeal)
            .foregroundStyle(.bizarreOnSurface)
            .disabled(isLoading)
            .accessibilityLabel("Sign in with Passkey")
            .accessibilityHint("Uses Face ID or Touch ID with your saved passkey")
            .accessibilityIdentifier("passkey.loginButton")
            .animation(reduceMotion ? nil : BrandMotion.snappy, value: isLoading)

            if case .failed(let err) = vm.state {
                Text(err.localizedDescription ?? "Passkey sign-in failed")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("passkey.loginError")
            }
        }
        .onChange(of: vm.state) { _, new in
            if case .done(let token) = new, !token.isEmpty {
                onSuccess(token)
            }
        }
    }

    private var isLoading: Bool {
        switch vm.state {
        case .challenging, .waitingForOS, .verifying: return true
        default: return false
        }
    }
}
#endif
