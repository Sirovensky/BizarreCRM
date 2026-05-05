#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - TwoFactorRecoveryInputView
// Shows a text field for entering a one-time recovery code.
// Called from TwoFactorChallengeView when the user taps "Use recovery code".

public struct TwoFactorRecoveryInputView: View {

    @Bindable var vm: TwoFactorChallengeViewModel
    let onBack: () -> Void

    public init(vm: TwoFactorChallengeViewModel, onBack: @escaping () -> Void) {
        self.vm = vm
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                headerSection
                inputSection

                if let remaining = vm.codesRemaining {
                    codesRemainingBanner(remaining)
                }

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Error: \(err)")
                }

                submitButton

                Button("Use authenticator code instead") {
                    vm.switchToTOTP()
                    onBack()
                }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreTeal)
                .accessibilityLabel("Switch back to 6-digit authenticator code input")
            }
            .padding(BrandSpacing.base)
        }
        .navigationTitle("Recovery Code")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("Enter a recovery code")
                .font(.brandHeadlineMedium())

            Text("Use one of the 10 backup codes you saved when you enrolled in 2FA. Each code can only be used once.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recovery code")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            TextField("XXXX-XXXXXXXX", text: $vm.recoveryCodeInput)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                .padding(BrandSpacing.md)
                .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Recovery code input field")
                .accessibilityHint("Enter the backup code you saved during 2FA setup")
        }
    }

    private var submitButton: some View {
        Button("Use Recovery Code") {
            Task { await vm.submitRecovery() }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isLoading || vm.recoveryCodeInput.isEmpty)
        .overlay {
            if vm.isLoading {
                ProgressView()
            }
        }
    }

    private func codesRemainingBanner(_ remaining: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: remaining > 2 ? "info.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(remaining > 2 ? Color.bizarreTeal : Color.bizarreWarning)
                .accessibilityHidden(true)

            Text(remaining == 0
                 ? "All recovery codes used. Generate new codes in Settings → Security."
                 : "Codes remaining: \(remaining). Generate new codes soon.")
                .font(.brandBodyMedium())
        }
        .padding(BrandSpacing.md)
        .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Recovery codes remaining: \(remaining)")
    }
}
#endif
