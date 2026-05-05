#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - LoginSplitPanelLayout
//
// §22 iPad polish — larger-screen split login.
//
// Left panel: brand identity (logo, tagline, animated gradient orbs).
// Right panel: the existing login form, passed in as content.
//
// Pluggable — the app-shell opts in for regular horizontal size class.
// Compact / iPhone always renders the content directly (no split).
//
// Usage:
//   LoginSplitPanelLayout {
//       LoginFlowView()
//   }

public struct LoginSplitPanelLayout<FormContent: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let formContent: FormContent

    public init(@ViewBuilder formContent: () -> FormContent) {
        self.formContent = formContent()
    }

    public var body: some View {
        if horizontalSizeClass == .regular {
            splitLayout
        } else {
            formContent
        }
    }

    // MARK: - Split (iPad / Regular width)

    private var splitLayout: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(maxWidth: .infinity)
            Divider()
                .frame(width: 0.5)
                .background(Color.bizarreOutline.opacity(0.25))
            formPanel
                .frame(maxWidth: .infinity)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    // MARK: - Left brand panel

    private var brandPanel: some View {
        ZStack {
            brandGradientBackground
            brandOrbs
            brandContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var brandGradientBackground: some View {
        LinearGradient(
            colors: [
                Color.bizarreOrange.opacity(0.30),
                Color.bizarreMagenta.opacity(0.20),
                Color.bizarreSurfaceBase.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var brandOrbs: some View {
        ZStack {
            // Primary warm orb — top-left
            Circle()
                .fill(Color.bizarreOrange.opacity(0.28))
                .blur(radius: 100)
                .frame(width: 420, height: 420)
                .offset(x: -120, y: -180)
            // Secondary magenta orb — bottom-right
            Circle()
                .fill(Color.bizarreMagenta.opacity(0.20))
                .blur(radius: 130)
                .frame(width: 360, height: 360)
                .offset(x: 140, y: 260)
            // Teal accent — mid
            Circle()
                .fill(Color.bizarreTeal.opacity(0.12))
                .blur(radius: 80)
                .frame(width: 220, height: 220)
                .offset(x: 60, y: 40)
        }
        .allowsHitTesting(false)
    }

    private var brandContent: some View {
        VStack(spacing: BrandSpacing.xl) {
            Spacer()
            logoLockup
            tagline
            Spacer()
            brandFootnote
        }
        .padding(.horizontal, BrandSpacing.xxl)
        .padding(.vertical, BrandSpacing.xxxl)
    }

    private var logoLockup: some View {
        VStack(spacing: BrandSpacing.md) {
            // Monogram badge with Liquid Glass chrome
            ZStack {
                Text("B")
                    .font(.brandDisplayLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .frame(width: 96, height: 96)
                    .brandGlass(.identity, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
            }
            .accessibilityHidden(true)

            Text("Bizarre CRM")
                .font(.brandDisplayMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var tagline: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Work weirder.")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            Text("Your field-service CRM, beautifully tuned for iPad.")
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var brandFootnote: some View {
        Text("bizarrecrm.com")
            .font(.brandLabelSmall())
            .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.6))
    }

    // MARK: - Right form panel

    private var formPanel: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            formContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("iPad Split — Regular") {
    LoginSplitPanelLayout {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Text("Login Form Placeholder")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.xxxl)
            }
            .frame(maxWidth: .infinity)
        }
    }
    .environment(\.horizontalSizeClass, .regular)
}

#Preview("iPhone Compact — passthrough") {
    LoginSplitPanelLayout {
        Text("Compact — form only")
            .font(.brandBodyLarge())
            .foregroundStyle(Color.bizarreOnSurface)
    }
    .environment(\.horizontalSizeClass, .compact)
}
#endif

#endif
