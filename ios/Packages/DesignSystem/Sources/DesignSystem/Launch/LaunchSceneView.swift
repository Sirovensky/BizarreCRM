import SwiftUI

// §68.1 — LaunchSceneView
// Branded splash: logo centered over brand gradient, identical in light/dark.
// No loading spinners — state restore completes before this view is dismissed.

// MARK: - LaunchSceneView

/// Branded splash screen shown during cold-start resolution (≤200ms).
///
/// Identical appearance in light and dark mode (dark base + orange logo).
/// Uses design tokens from `BrandColors` so colors track any rebrand.
public struct LaunchSceneView: View {

    public init() {}

    public var body: some View {
        ZStack {
            // Brand gradient background — same in both appearances.
            LinearGradient(
                colors: [
                    Color.bizarreSurfaceBase,
                    Color.bizarreSurfaceBase.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "bolt.fill")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.bizarreOrange)
                    .frame(width: 64, height: 64)
                    .accessibilityLabel("Bizarre CRM")
                    .accessibilityAddTraits(.isImage)

                Text("Bizarre CRM")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(Color.bizarreOrange.opacity(0.9))
            }
        }
        // Force dark color scheme so gradient reads correctly in light mode too.
        .colorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    LaunchSceneView()
}
#endif
