#if canImport(UIKit)
import SwiftUI
import LocalAuthentication
import Persistence
import DesignSystem
import Core

// MARK: - BiometricReenrollPrompt
//
// §2.6 — Re-enroll prompt: `LAContext.evaluatedPolicyDomainState` change
// detection. When the enrolled biometry set changes (new finger / face added,
// device reset), the stored `domainState` hash becomes stale. On the next
// app launch / foreground, detect the mismatch and prompt the user to
// re-enable biometric login so the stored credentials stay properly gated.
//
// The persisted `domainState` key lives under `BiometricPreference` in
// Keychain to avoid UserDefaults which could be cleared independently.

// MARK: - Domain-state persistence

public actor BiometricDomainStateStore {

    public static let shared = BiometricDomainStateStore()
    private static let keychainKey = "auth.biometric.domainState"

    private init() {}

    public func save(_ data: Data) {
        let encoded = data.base64EncodedString()
        try? KeychainStore.shared.set(encoded, for: .init(rawValue: BiometricDomainStateStore.keychainKey)!)
    }

    public func load() -> Data? {
        guard let encoded = KeychainStore.shared.get(.init(rawValue: BiometricDomainStateStore.keychainKey)!) else { return nil }
        return Data(base64Encoded: encoded)
    }

    public func clear() {
        try? KeychainStore.shared.remove(.init(rawValue: BiometricDomainStateStore.keychainKey)!)
    }

    // MARK: - Change detection

    /// Returns `true` when the current `LAContext.evaluatedPolicyDomainState`
    /// differs from the persisted snapshot — meaning the enrolled biometry set
    /// has changed since the user last enabled biometric login.
    public func hasEnrollmentChanged() -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
              let current = ctx.evaluatedPolicyDomainState else {
            return false
        }
        guard let stored = load() else {
            // Never saved — snapshot the current state and return false.
            save(current)
            return false
        }
        if current != stored {
            // Update snapshot so we only alert once per enrollment change.
            save(current)
            return true
        }
        return false
    }

    /// Snapshots the current domain state. Call after the user successfully
    /// enables biometric login so subsequent checks have a baseline.
    public func snapshot() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
              let current = ctx.evaluatedPolicyDomainState else { return }
        save(current)
    }
}

// MARK: - Re-enroll sheet

/// Sheet shown when biometry enrollment changed since biometric login was set up.
public struct BiometricReenrollSheet: View {
    let onReenroll: () -> Void
    let onDismiss: () -> Void

    public init(onReenroll: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onReenroll = onReenroll
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "faceid")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("Biometric enrollment changed")
                .font(.brandHeadlineMedium())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Your biometric enrollment has changed since you enabled biometric login. Re-enable it to continue using it for quick sign-in.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.sm)

            Button("Re-enable biometric login", action: onReenroll)
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .foregroundStyle(.bizarreOnOrange)
                .frame(maxWidth: .infinity)

            Button("Not now", action: onDismiss)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.xl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - View modifier

private struct BiometricReenrollModifier: ViewModifier {
    @State private var showPrompt: Bool = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPrompt) {
                BiometricReenrollSheet {
                    // Mark biometric as disabled; user will re-enable via normal flow.
                    BiometricPreference.shared.disable()
                    showPrompt = false
                } onDismiss: {
                    showPrompt = false
                }
            }
            .task {
                // Only check if biometric is currently enabled.
                guard BiometricPreference.shared.isEnabled else { return }
                let changed = await BiometricDomainStateStore.shared.hasEnrollmentChanged()
                if changed {
                    // Disable silently so biometric auth can't unlock with the wrong identity.
                    BiometricPreference.shared.disable()
                    showPrompt = true
                }
            }
    }
}

public extension View {
    /// Detects biometric enrollment changes and prompts the user to re-enable
    /// biometric login if their Face ID / Touch ID enrollment has changed.
    func biometricReenrollCheck() -> some View {
        modifier(BiometricReenrollModifier())
    }
}

#endif
