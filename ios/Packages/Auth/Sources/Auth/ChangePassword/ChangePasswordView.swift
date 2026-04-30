#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - §2.9 Change password — Settings → Security

/// Lets an authenticated user update their account password.
///
/// **Integration (Settings → Security row):**
/// ```swift
/// NavigationLink("Change password") {
///     ChangePasswordView(api: apiClient)
/// }
/// ```
public struct ChangePasswordView: View {

    @State private var viewModel: ChangePasswordViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient) {
        self._viewModel = State(wrappedValue: ChangePasswordViewModel(api: api))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // §2.13 — Password fields must carry .privacySensitive() so that
                // iOS blurs them in the app-switcher snapshot and when the system
                // captures the screen for accessibility / screen-recording.
                secureField("Current password", text: $viewModel.currentPassword, systemImage: "lock")
                    .privacySensitive()

                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    secureField("New password", text: $viewModel.newPassword, systemImage: "lock.rotation")
                        .privacySensitive()

                    if !viewModel.newPassword.isEmpty {
                        PasswordStrengthMeter(evaluation: viewModel.evaluation)
                            .padding(.horizontal, BrandSpacing.xxs)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(BrandMotion.snappy, value: viewModel.newPassword.isEmpty)

                secureField("Confirm new password", text: $viewModel.confirmPassword, systemImage: "lock.rotation")
                    .privacySensitive()

                Group {
                    if viewModel.mismatch {
                        HStack(spacing: BrandSpacing.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.bizarreWarning)
                                .imageScale(.small)
                            Text("Passwords don't match yet.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreWarning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .animation(BrandMotion.snappy, value: viewModel.mismatch)

                if let err = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: BrandSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                        Text(err)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreError)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("changePassword.error")
                }

                if let ok = viewModel.successMessage {
                    HStack(alignment: .top, spacing: BrandSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                        Text(ok)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreSuccess)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("changePassword.success")
                }

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.bizarreOnOrange)
                        }
                        Text("Update password")
                            .font(.brandTitleMedium()).bold()
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .foregroundStyle(.bizarreOnOrange)
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("changePassword.submit")
            }
            .padding(BrandSpacing.lg)
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .onChange(of: viewModel.successMessage) { _, new in
            guard new != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            }
        }
    }

    // MARK: - Private helpers

    @ViewBuilder
    private func secureField(_ label: String, text: Binding<String>, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            RevealableSecureField(placeholder: label, text: text, systemImage: systemImage)
        }
    }
}

// MARK: - Revealable secure field (eye-toggle, §2.2)

private struct RevealableSecureField: View {
    let placeholder: String
    @Binding var text: String
    let systemImage: String
    @State private var reveal: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: systemImage).foregroundStyle(.bizarreOnSurfaceMuted)
            Group {
                if reveal {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .focused($focused)
            .frame(maxWidth: .infinity, minHeight: 28)

            Button { reveal.toggle() } label: {
                Image(systemName: reveal ? "eye.slash" : "eye")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reveal ? "Hide password" : "Show password")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.base)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .background(Color.bizarreSurface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5)
        )
    }
}

#endif
