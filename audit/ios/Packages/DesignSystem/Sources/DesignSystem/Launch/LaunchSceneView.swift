import SwiftUI

// §68.1 — LaunchSceneView
// Branded splash: logo centered over brand gradient, identical in light/dark.
// No loading spinners — state restore completes before this view is dismissed.
//
// Logo priority:
//   1. `BrandMark` image asset (template-rendered, tinted bizarreOrange).
//      Drop a PDF/SVG into Assets.xcassets/BrandMark.imageset to activate.
//   2. Fallback: `bolt.fill` SF Symbol until the asset ships.
//
// Motion: subtle opacity + scale entrance (§80.6 `smooth` curve, 350ms).
//         Respects Reduce Motion — skips animation when active.

// MARK: - LaunchSceneView

/// Branded splash screen shown during cold-start resolution (≤200ms).
///
/// Identical appearance in light and dark mode (dark base + orange logo).
/// Uses design tokens from `BrandColors` and `DesignTokens` so colors and
/// timings track any rebrand without touching this file.
public struct LaunchSceneView: View {

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            // Dark brand background — forced dark so gradient reads correctly
            // in light mode too (spec: identical appearance in both modes).
            Color.bizarreSurfaceBase
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.xxl) {
                logoMark
                    .accessibilityLabel("Bizarre CRM")
                    .accessibilityAddTraits(.isImage)

                Text("Bizarre CRM")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOrange.opacity(0.9))
                    .accessibilityHidden(true) // logo label already announces the name
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.92)
        }
        .colorScheme(.dark)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(
                .easeOut(duration: DesignTokens.Motion.smooth)
                .delay(0.05)
            ) {
                appeared = true
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var logoMark: some View {
        // Attempt to load the BrandMark vector asset. When the imageset has no
        // actual files (placeholder slot) UIImage returns nil → show fallback.
        if UIImage(named: "BrandMark") != nil {
            Image("BrandMark")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color.bizarreOrange)
                .frame(width: 72, height: 72)
        } else {
            Image(systemName: "bolt.fill")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color.bizarreOrange)
                .frame(width: 60, height: 60)
        }
    }
}

#if DEBUG
#Preview("Launch — light") {
    LaunchSceneView()
        .preferredColorScheme(.light)
}

#Preview("Launch — dark") {
    LaunchSceneView()
        .preferredColorScheme(.dark)
}

#endif
