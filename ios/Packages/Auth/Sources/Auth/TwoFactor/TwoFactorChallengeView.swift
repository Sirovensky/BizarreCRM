#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - TwoFactorChallengeView
// Shown post-password when server responds with 2fa_required.
// 6-field segmented input, auto-advance. "Use recovery code" link.

public struct TwoFactorChallengeView: View {

    @Bindable var vm: TwoFactorChallengeViewModel
    @FocusState private var focusedField: Int?
    @State private var showRecovery = false

    public init(vm: TwoFactorChallengeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        if Platform.isCompact {
            phoneLayout
        } else {
            padLayout
        }
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Verification")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showRecovery) {
                    TwoFactorRecoveryInputView(vm: vm, onBack: { showRecovery = false })
                }
        }
    }

    private var padLayout: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Verification")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showRecovery) {
                    TwoFactorRecoveryInputView(vm: vm, onBack: { showRecovery = false })
                }
        }
        .frame(width: 520)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                headerSection
                segmentedDigitInput
                lockoutBanner
                errorSection
                submitButton
                recoveryLink
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOrange)
                .padding(.top, BrandSpacing.lg)
                .accessibilityHidden(true)

            Text("Enter your 2FA code")
                .font(.brandHeadlineMedium())

            Text("Open your authenticator app and enter the 6-digit code.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 6-field segmented input

    private var segmentedDigitInput: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(0..<6, id: \.self) { index in
                digitCell(index: index)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { focusedField = 0 }
    }

    private func digitCell(index: Int) -> some View {
        TextField("", text: $vm.digits[index])
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(.title, design: .monospaced).bold())
            .frame(width: 44, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                focusedField == index ? Color.bizarreOrange : Color.bizarreOutline,
                                lineWidth: focusedField == index ? 2 : 1
                            )
                    )
            )
            .focused($focusedField, equals: index)
            .accessibilityLabel("Digit \(index + 1) of 6")
            .onChange(of: vm.digits[index]) { _, newValue in
                handleDigitChange(index: index, newValue: newValue)
            }
    }

    private func handleDigitChange(index: Int, newValue: String) {
        let digit = newValue.filter(\.isNumber)
        if digit.count > 1 {
            // Paste: distribute across fields
            let digits = Array(digit.prefix(6 - index))
            for (offset, char) in digits.enumerated() {
                if index + offset < 6 {
                    vm.digits[index + offset] = String(char)
                }
            }
            let nextField = min(index + digits.count, 5)
            focusedField = nextField
        } else {
            vm.digits[index] = digit
            if !digit.isEmpty && index < 5 {
                focusedField = index + 1
            } else if digit.isEmpty && index > 0 {
                focusedField = index - 1
            }
        }

        // Auto-submit when all 6 filled
        if vm.isTOTPComplete && !vm.isLoading {
            Task { await vm.submitTOTP() }
        }
    }

    // MARK: - Lockout banner

    @ViewBuilder
    private var lockoutBanner: some View {
        if vm.isLockedOut {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "timer")
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityHidden(true)
                Text("Too many attempts. Try again in \(vm.lockoutSecondsRemaining)s.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreWarning)
            }
            .padding(BrandSpacing.md)
            .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                vm.clearLockoutIfExpired()
            }
            .accessibilityLabel("Locked out for \(vm.lockoutSecondsRemaining) seconds")
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let err = vm.errorMessage {
            Text(err)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Error: \(err)")
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button("Verify") {
            Task { await vm.submitTOTP() }
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(!vm.canSubmit || !vm.isTOTPComplete)
        .overlay {
            if vm.isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Recovery link

    private var recoveryLink: some View {
        Button("Use recovery code") {
            vm.switchToRecovery()
            showRecovery = true
        }
        .font(.brandBodyMedium())
        .foregroundStyle(.bizarreTeal)
        .accessibilityLabel("Use a one-time backup recovery code instead")
    }
}
#endif
