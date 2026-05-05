#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - PasskeyRegisterFlow
//
// Settings → Security → Passkeys → "+ Register new passkey"
// Flow: nickname entry → register/begin → OS sheet → register/complete → dismiss + refresh.

public struct PasskeyRegisterFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var nickname: String = ""
    @State private var showingNicknameHint: Bool = false

    private let vm: PasskeyViewModel
    private let username: String
    private let displayName: String

    public init(viewModel: PasskeyViewModel, username: String, displayName: String) {
        self.vm = viewModel
        self.username = username
        self.displayName = displayName
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                formContent
            }
            .navigationTitle("Add Passkey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.reset()
                        dismiss()
                    }
                    .accessibilityIdentifier("passkeyRegister.cancel")
                }
            }
            .onChange(of: vm.state) { _, new in
                if case .done = new {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Icon
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreTeal)
                    .padding(.top, DesignTokens.Spacing.xxl)
                    .accessibilityHidden(true)

                // Explanation
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Add a Passkey")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityAddTraits(.isHeader)

                    Text("Passkeys let you sign in with Face ID or Touch ID — no password needed.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                }

                // Nickname field
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Nickname")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "tag")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        TextField("e.g. iPhone 15, MacBook Pro", text: $nickname)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { startRegistration() }
                            .accessibilityLabel("Passkey nickname")
                            .accessibilityHint("A label to identify this device")
                            .accessibilityIdentifier("passkeyRegister.nicknameField")
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .frame(minHeight: 52)
                    .background(Color.bizarreSurface2.opacity(0.7),
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(Color.bizarreOutline.opacity(0.6), lineWidth: 0.5)
                    )

                    Text("You'll see this name when managing your passkeys.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                // Error
                if case .failed(let err) = vm.state {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                        Text(err.localizedDescription ?? "Registration failed")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreError)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .accessibilityIdentifier("passkeyRegister.error")
                }

                // CTA
                Button {
                    startRegistration()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.bizarreOnOrange)
                                .controlSize(.small)
                                .transition(reduceMotion ? .identity : .opacity)
                        }
                        Text(isLoading ? "Registering…" : "Register Passkey")
                            .font(.brandTitleMedium()).bold()
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .foregroundStyle(.bizarreOnOrange)
                .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .accessibilityIdentifier("passkeyRegister.submit")
                .animation(reduceMotion ? nil : BrandMotion.snappy, value: isLoading)
            }
            .padding(.bottom, DesignTokens.Spacing.xxl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func startRegistration() {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }
        Task {
            await vm.register(username: username, displayName: displayName, nickname: trimmed)
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
