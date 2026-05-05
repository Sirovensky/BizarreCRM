#if canImport(UIKit)
import SwiftUI
import LocalAuthentication
import DesignSystem
import Core

// MARK: - §2.13 Sensitive-screen re-auth gate

/// Screens that handle sensitive operations must immediately prompt for biometric
/// re-authentication on appear, regardless of the current idle timer state.
///
/// **Covered screens (§2.13):**
/// - Payment / charge flows
/// - Settings → Billing
/// - Settings → Danger Zone (data wipe / tenant delete)
///
/// Usage:
/// ```swift
/// PaymentView()
///     .sensitiveScreenReauth(reason: "Confirm your identity to process a payment.")
/// ```
///
/// The modifier presents a biometric prompt on appear. If biometrics are unavailable
/// or fail, the user is shown a blocking overlay with a "Try again" button and a
/// "Sign out instead" fallback.
public struct SensitiveScreenReauthModifier: ViewModifier {

    public let reason: String
    public var onDenied: (() -> Void)?

    @State private var state: ReauthState = .pending
    @Environment(\.dismiss) private var dismiss

    public func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(state == .granted)
                .opacity(state == .granted ? 1 : 0)

            if state != .granted {
                reauthOverlay
                    .transition(.opacity)
            }
        }
        .task { await attemptReauth() }
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    // MARK: - Overlay

    @ViewBuilder
    private var reauthOverlay: some View {
        ZStack {
            Color.bizarreSurfaceBase
                .ignoresSafeArea()

            VStack(spacing: BrandSpacing.xxl) {
                Spacer()

                Image(systemName: BiometricGate.kind.sfSymbol)
                    .font(.system(size: 52))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(spacing: BrandSpacing.sm) {
                    Text("Identity required")
                        .font(.brandTitleLarge())
                        .foregroundStyle(Color.bizarreOnSurface)

                    Text(reason)
                        .font(.brandBodySmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }

                if state == .failed {
                    Text("Authentication failed. Please try again.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreError)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: BrandSpacing.md) {
                    Button {
                        Task { await attemptReauth() }
                    } label: {
                        Text("Try again")
                            .font(.brandTitleMedium().bold())
                    }
                    .buttonStyle(.brandGlassProminent)
                    .tint(Color.bizarreOrange)
                    .foregroundStyle(Color.bizarreOnOrange)
                    .disabled(state == .pending)
                    .accessibilityIdentifier("sensitiveReauth.retry")

                    Button("Go back") {
                        if let onDenied { onDenied() } else { dismiss() }
                    }
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("sensitiveReauth.back")
                }

                Spacer()
            }
            .padding(BrandSpacing.xxxl)
        }
    }

    // MARK: - Auth

    private func attemptReauth() async {
        state = .pending
        let granted = await BiometricGate.tryUnlock(reason: reason)
        state = granted ? .granted : .failed
    }
}

// MARK: - State enum

private enum ReauthState: Equatable {
    case pending  // Waiting for the biometric prompt
    case granted  // Biometric succeeded
    case failed   // Biometric failed/cancelled
}

// MARK: - View extension

public extension View {
    /// Requires immediate biometric re-authentication before showing this screen.
    ///
    /// - Parameters:
    ///   - reason:    Human-readable string shown in the biometric prompt and overlay.
    ///   - onDenied:  Called if the user cancels repeatedly. Defaults to `dismiss()`.
    func sensitiveScreenReauth(
        reason: String,
        onDenied: (() -> Void)? = nil
    ) -> some View {
        modifier(SensitiveScreenReauthModifier(reason: reason, onDenied: onDenied))
    }
}

#endif
