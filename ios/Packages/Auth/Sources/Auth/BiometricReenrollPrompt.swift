#if canImport(UIKit)
import SwiftUI
import LocalAuthentication
import Persistence
import DesignSystem

// MARK: - §2.6 Biometric re-enroll prompt

/// Detects when the device's biometric enrollment changes (e.g. a new
/// fingerprint is added to Touch ID, or Face ID is re-enrolled) and prompts
/// the user to re-enable biometric unlock for Bizarre CRM.
///
/// **How detection works:** `LAContext.evaluatedPolicyDomainState` returns an
/// opaque `Data` that changes whenever biometric enrollment changes. We persist
/// the last-seen value in `UserDefaults` (not Keychain — this is not sensitive)
/// and compare on each cold start.
///
/// **On mismatch:** biometric unlock is automatically disabled (the Keychain
/// item protected by `.biometryCurrentSet` is already invalidated by iOS), and
/// this prompt appears so the user can re-enable it if they want.
///
/// Wire this as a `.sheet` or `.overlay` from the root navigator:
/// ```swift
/// .sheet(isPresented: $showReenrollPrompt) {
///     BiometricReenrollPromptView(
///         onEnable: { await reenableBiometric() },
///         onSkip: { showReenrollPrompt = false }
///     )
/// }
/// ```
public struct BiometricReenrollDetector {

    private static let domainStateKey = "biometric.last_domain_state"

    /// Returns `true` when a biometric enrollment change is detected.
    /// Also persists the new domain state so subsequent calls return `false`
    /// until the next change.
    @discardableResult
    public static func detectAndUpdate() -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              let current = ctx.evaluatedPolicyDomainState
        else {
            return false
        }

        let stored = UserDefaults.standard.data(forKey: domainStateKey)
        UserDefaults.standard.set(current, forKey: domainStateKey)

        guard let previous = stored else {
            // First-run — no previous state; store current and return false.
            return false
        }

        return current != previous
    }
}

// MARK: - Re-enroll prompt view

/// Full-sheet prompt shown when a biometric enrollment change is detected.
public struct BiometricReenrollPromptView: View {
    let onEnable: @MainActor () async -> Void
    let onSkip: @MainActor () -> Void

    @State private var isEnabling: Bool = false

    private let kind = BiometricGate.kind
    private var kindLabel: String { kind == .none ? "biometrics" : kind.label }

    public init(
        onEnable: @escaping @MainActor () async -> Void,
        onSkip: @escaping @MainActor () -> Void
    ) {
        self.onEnable = onEnable
        self.onSkip = onSkip
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                Spacer()
                Image(systemName: kind.sfSymbol)
                    .font(.system(size: 60))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Re-enable \(kindLabel)")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)

                Text("Your \(kindLabel) enrollment has changed. For your security, biometric unlock was disabled. Re-enable it now?")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)

                Spacer()

                VStack(spacing: BrandSpacing.sm) {
                    Button {
                        isEnabling = true
                        Task { @MainActor in
                            await onEnable()
                            isEnabling = false
                        }
                    } label: {
                        HStack {
                            if isEnabling { ProgressView().tint(.bizarreOnOrange) }
                            Text("Re-enable \(kindLabel)")
                                .font(.brandTitleMedium()).bold()
                        }
                    }
                    .buttonStyle(.brandGlassProminent)
                    .tint(.bizarreOrange)
                    .foregroundStyle(.bizarreOnOrange)
                    .disabled(isEnabling)
                    .accessibilityIdentifier("biometric.reenroll.enable")

                    Button("Not now", action: onSkip)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.top, BrandSpacing.xs)
                        .accessibilityIdentifier("biometric.reenroll.skip")
                }
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.bottom, BrandSpacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#endif
