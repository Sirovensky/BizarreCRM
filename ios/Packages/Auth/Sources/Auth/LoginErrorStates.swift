#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// MARK: - LoginErrorStates
//
// §2.12 — Auth-specific error / empty states:
//
//  • Wrong password → inline error + shake animation + `.error` haptic.
//  • Account locked (423) → modal "Contact your admin." + support deep link.
//  • Wrong server URL / unreachable → inline "Can't reach this server."
//  • Rate-limit 429 → glass banner with human-readable countdown.
//  • Network offline during login → "You're offline."
//  • TLS pin failure → non-dismissable red glass alert.

// MARK: - Shake animation

public struct ShakeEffect: GeometryEffect {
    public var amount: CGFloat = 10
    public var shakesPerUnit: CGFloat = 3
    public var animatableData: CGFloat

    public init(_ value: CGFloat) {
        self.animatableData = value
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

public extension View {
    /// Shakes the view on wrong credentials.
    func shake(trigger: Bool) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var shakeProgress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(shakeProgress))
            .onChange(of: trigger) { _, new in
                if new {
                    withAnimation(.linear(duration: 0.4)) {
                        shakeProgress += 1
                    }
                }
            }
    }
}

// MARK: - Rate-limit banner (429)

public struct RateLimitBanner: View {
    public let retryAfter: Date
    @State private var remaining: Int = 0
    @State private var timer: Task<Void, Never>? = nil

    public init(retryAfter: Date) {
        self.retryAfter = retryAfter
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Too many attempts. Try again in \(remaining)s.")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreWarning.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, BrandSpacing.base)
        .onAppear { startTimer() }
        .onDisappear { timer?.cancel() }
        .accessibilityLabel("Rate limited. Try again in \(remaining) seconds.")
    }

    private func startTimer() {
        timer?.cancel()
        remaining = max(0, Int(retryAfter.timeIntervalSinceNow.rounded(.up)))
        timer = Task { @MainActor in
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining = max(0, Int(retryAfter.timeIntervalSinceNow.rounded(.up)))
            }
        }
    }
}

// MARK: - Account locked modal (423)

public struct AccountLockedAlert: View {
    let supportEmail: String?
    let onDismiss: () -> Void

    public init(supportEmail: String?, onDismiss: @escaping () -> Void) {
        self.supportEmail = supportEmail
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            Text("Account locked")
                .font(.brandHeadlineMedium())
                .accessibilityAddTraits(.isHeader)

            Text("Your account has been locked. Contact your admin to unlock it.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)

            if let email = supportEmail, !email.isEmpty {
                Link(destination: URL(string: "mailto:\(email)")!) {
                    Label("Email admin", systemImage: "envelope")
                        .font(.brandTitleMedium())
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .foregroundStyle(.bizarreOnOrange)
                .frame(maxWidth: .infinity)
            }

            Button("Back to sign-in", action: onDismiss)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.xl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - TLS pin failure alert

/// §2.12 — Non-dismissable red glass alert for TLS pin failures.
public struct TLSPinFailureAlert: View {
    public init() {}

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "shield.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            Text("Certificate mismatch")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Text("This server's certificate doesn't match the pinned certificate. Contact your admin. The app cannot connect until this is resolved.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.bizarreError.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.bizarreError.opacity(0.5), lineWidth: 1)
                )
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding(BrandSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Offline login notice

/// §2.12 — Shown when user tries to log in without network access.
public struct OfflineLoginNotice: View {
    public init() {}

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Connect to sign in — auth requires a network connection.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're offline. Connect to sign in.")
    }
}

#endif
