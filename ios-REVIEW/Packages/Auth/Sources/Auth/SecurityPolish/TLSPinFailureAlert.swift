#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - §2.12 TLS pin failure alert

/// A non-dismissable red glass overlay shown when the server's TLS certificate
/// does not match the pinned certificate.
///
/// This blocks the entire UI — the user must contact their admin. There is no
/// "try again" option because the failure is not transient: either the cert is
/// wrong or the app is being proxied.
///
/// Apply from the root view as an overlay when `isPinFailed == true`:
/// ```swift
/// ZStack {
///     MainContent()
///     if isTLSPinFailed {
///         TLSPinFailureAlert()
///     }
/// }
/// ```
public struct TLSPinFailureAlert: View {

    public init() {}

    public var body: some View {
        ZStack {
            // Full-screen tinted backdrop (non-interactive below)
            Color.bizarreSurfaceBase.opacity(0.92)
                .ignoresSafeArea()

            Group {
                if Platform.isCompact {
                    iPhoneCard
                } else {
                    iPadCard
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("auth.tlsPinFailureAlert")
        // Block all interaction below
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .onTapGesture {} // swallow taps
    }

    // MARK: - iPhone layout (full-width card, bottom-anchored)

    private var iPhoneCard: some View {
        VStack {
            Spacer()
            cardContent
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.xxl)
        }
    }

    // MARK: - iPad layout (centred card, max 480 pt)

    private var iPadCard: some View {
        cardContent
            .frame(maxWidth: 480)
            .padding(.horizontal, BrandSpacing.xxl)
    }

    // MARK: - Card content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            // Icon row
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "shield.slash.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.bizarreError)
                    .accessibilityHidden(true)

                Text("Certificate error")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreError)
            }

            // Body
            Text("This server's certificate doesn't match the pinned certificate.")
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)

            Text("This can indicate a network interception (proxy or man-in-the-middle attack). Contact your admin before continuing.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .background(Color.bizarreError.opacity(0.4))

            // Non-dismissable note
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("App is locked until the issue is resolved.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .italic()
            }
        }
        .padding(BrandSpacing.lg)
        .brandGlass(
            .regular,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl),
            tint: Color.bizarreError.opacity(0.12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                .strokeBorder(Color.bizarreError.opacity(0.5), lineWidth: 1.5)
        )
    }
}

// MARK: - View extension

public extension View {
    /// Overlays a non-dismissable TLS pin failure alert when `isFailed == true`.
    @ViewBuilder
    func tlsPinFailureOverlay(isFailed: Bool) -> some View {
        ZStack {
            self
            if isFailed {
                TLSPinFailureAlert()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isFailed)
    }
}

#endif
