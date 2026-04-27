// §77 Environment & Build Flavor helpers
// EnvironmentBanner — SwiftUI view that shows a coloured pill/bar in
// staging and development builds. Hidden completely in production.
//
// Usage (apply as an overlay on the root scene):
//
//   ContentView()
//       .overlay(alignment: .top) { EnvironmentBanner() }
//
// Or use the `.environmentBanner()` view modifier for convenience.

#if canImport(SwiftUI)
import SwiftUI

// MARK: - EnvironmentBanner

/// A coloured banner that identifies the current build flavor.
///
/// Renders nothing (zero-size) in production builds, so it is safe to
/// leave in place in all configurations without a conditional import.
public struct EnvironmentBanner: View {
    private let flavor: BuildFlavor

    /// Creates a banner driven by `BuildFlavor.current`.
    public init() {
        self.init(flavor: .current)
    }

    /// Creates a banner for the given flavor (injectable for Previews/tests).
    public init(flavor: BuildFlavor) {
        self.flavor = flavor
    }

    public var body: some View {
        if flavor.isNonProduction {
            bannerContent
        }
    }

    private var bannerContent: some View {
        Text(flavor.label)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(bannerColor, in: Capsule())
            .padding(.top, 4)
            .accessibilityLabel("Build environment: \(flavor.label)")
    }

    private var bannerColor: Color {
        switch flavor {
        case .staging:     return .orange
        case .development: return .purple
        case .production:  return .clear
        }
    }
}

// MARK: - View modifier convenience

extension View {
    /// Overlays a `EnvironmentBanner` at the top of this view.
    ///
    /// Adds no visual chrome in production builds.
    @ViewBuilder
    public func environmentBanner(flavor: BuildFlavor = .current) -> some View {
        overlay(alignment: .top) {
            EnvironmentBanner(flavor: flavor)
        }
    }
}

// MARK: - Previews

#Preview("Staging") {
    Rectangle()
        .fill(Color.primary.opacity(0.05))
        .frame(width: 300, height: 200)
        .environmentBanner(flavor: .staging)
}

#Preview("Development") {
    Rectangle()
        .fill(Color.primary.opacity(0.05))
        .frame(width: 300, height: 200)
        .environmentBanner(flavor: .development)
}

#Preview("Production (invisible)") {
    Rectangle()
        .fill(Color.primary.opacity(0.05))
        .frame(width: 300, height: 200)
        .environmentBanner(flavor: .production)
}
#endif
