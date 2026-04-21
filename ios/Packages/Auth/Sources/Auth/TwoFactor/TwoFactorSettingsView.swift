#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - TwoFactorSettingsView
// Shown in Settings → Security.
// If not enrolled: "Enable 2FA" → pushes TwoFactorEnrollView.
// If enrolled: Disable / Regenerate codes.

public struct TwoFactorSettingsView: View {

    @State private var vm: TwoFactorSettingsViewModel

    public init(vm: TwoFactorSettingsViewModel) {
        _vm = State(initialValue: vm)
    }

    public var body: some View {
        List {
            if vm.isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading…")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            } else if vm.isEnrolled {
                enrolledSection
            } else {
                notEnrolledSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Two-Factor Auth")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadStatus() }
        .alert("Disable 2FA", isPresented: $vm.showDisableAlert) {
            disableAlertContent
        }
        .alert("Regenerate Codes", isPresented: $vm.showRegenerateAlert) {
            regenerateAlertContent
        }
        .sheet(isPresented: $vm.showEnrollSheet, onDismiss: {
            Task { await vm.loadStatus() }
        }) {
            TwoFactorEnrollView(vm: TwoFactorEnrollmentViewModel(repository: vm.repository))
        }
        .overlay {
            if let err = vm.errorMessage {
                VStack {
                    Spacer()
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.white)
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreError, in: Capsule())
                        .padding(BrandSpacing.base)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
    }

    // MARK: - Not enrolled

    private var notEnrolledSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Label("2FA is not enabled", systemImage: "lock.open.fill")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                Text("Protect your account with an authenticator app.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                Button("Enable 2FA") {
                    vm.showEnrollSheet = true
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .padding(.top, BrandSpacing.sm)
                .accessibilityLabel("Enable two-factor authentication")
            }
            .padding(.vertical, BrandSpacing.sm)
        }
    }

    // MARK: - Enrolled

    private var enrolledSection: some View {
        Group {
            Section {
                Label("2FA is active", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.bizarreSuccess)
                    .font(.brandBodyLarge())
                    .accessibilityLabel("Two-factor authentication is enabled")
            }

            Section("Recovery codes") {
                if let remaining = vm.codesRemaining {
                    HStack {
                        Text("Codes remaining")
                        Spacer()
                        Text("\(remaining)")
                            .foregroundStyle(remaining <= 2 ? .bizarreWarning : .bizarreOnSurface)
                            .accessibilityLabel("\(remaining) recovery codes remaining")
                    }
                    .font(.brandBodyLarge())
                }

                Button("Regenerate recovery codes") {
                    vm.showRegenerateAlert = true
                }
                .foregroundStyle(.bizarreTeal)
                .accessibilityLabel("Regenerate your ten recovery codes. Requires your current authenticator code.")
            }

            Section("Security") {
                Button(role: .destructive) {
                    vm.showDisableAlert = true
                } label: {
                    Label("Disable 2FA", systemImage: "lock.open.fill")
                }
                .accessibilityLabel("Disable two-factor authentication. Requires current password and authenticator code.")
            }
        }
    }

    // MARK: - Disable alert

    @ViewBuilder
    private var disableAlertContent: some View {
        SecureField("Current password", text: $vm.disablePassword)
        TextField("6-digit code", text: $vm.disableCode)
            .keyboardType(.numberPad)
        Button("Disable", role: .destructive) {
            Task { await vm.disable() }
        }
        Button("Cancel", role: .cancel) {
            vm.disablePassword = ""
            vm.disableCode = ""
        }
    }

    // MARK: - Regenerate alert

    @ViewBuilder
    private var regenerateAlertContent: some View {
        TextField("6-digit code", text: $vm.regenerateCode)
            .keyboardType(.numberPad)
        Button("Regenerate") {
            Task { await vm.regenerateCodes() }
        }
        Button("Cancel", role: .cancel) {
            vm.regenerateCode = ""
        }
    }
}
#endif

// MARK: - TwoFactorSettingsViewModel (not UIKit-gated: pure logic)

import Foundation
import Observation
import Core

@MainActor
@Observable
public final class TwoFactorSettingsViewModel {

    public private(set) var isLoading = false
    public private(set) var isEnrolled = false
    public private(set) var codesRemaining: Int? = nil
    public private(set) var errorMessage: String? = nil
    public private(set) var newCodes: RecoveryCodeList? = nil

    // Alert / sheet state
    public var showDisableAlert = false
    public var showRegenerateAlert = false
    public var showEnrollSheet = false

    // Alert fields
    public var disablePassword = ""
    public var disableCode = ""
    public var regenerateCode = ""

    let repository: TwoFactorRepository

    public init(repository: TwoFactorRepository) {
        self.repository = repository
    }

    public func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let status = try await repository.status()
            isEnrolled = status.enabled
            codesRemaining = status.codesRemaining
        } catch {
            errorMessage = AppError.from(error).errorDescription
        }
    }

    public func disable() async {
        let pwd = disablePassword
        let code = disableCode.filter(\.isNumber)
        disablePassword = ""
        disableCode = ""

        guard !pwd.isEmpty, code.count == 6 else {
            errorMessage = "Password and 6-digit code are required."
            return
        }
        do {
            _ = try await repository.disable(currentPassword: pwd, totpCode: code)
            isEnrolled = false
            codesRemaining = nil
        } catch {
            errorMessage = AppError.from(error).errorDescription
        }
    }

    public func regenerateCodes() async {
        let code = regenerateCode.filter(\.isNumber)
        regenerateCode = ""

        guard code.count == 6 else {
            errorMessage = "Enter your 6-digit authenticator code."
            return
        }
        do {
            let resp = try await repository.regenerateCodes(totpCode: code)
            newCodes = RecoveryCodeList(codes: resp.backupCodes)
            codesRemaining = resp.backupCodes.count
        } catch {
            errorMessage = AppError.from(error).errorDescription
        }
    }
}
