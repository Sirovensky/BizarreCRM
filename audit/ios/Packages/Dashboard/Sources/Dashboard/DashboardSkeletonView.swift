import SwiftUI
import Core
import DesignSystem

// MARK: - DashboardSkeletonView
//
// §3.1 — Skeleton loading state for the Dashboard.
// Shows shimmer placeholders for the KPI grid + hero card + attention card.
// Glass shimmer appears within ≤300ms of the initial load trigger.
//
// Design rules (CLAUDE.md):
//   - Glass shimmer on content placeholders is acceptable — it's not "glass on
//     content" in the navigation-chrome sense; it's a loading indicator.
//   - Reduce Motion: shimmer animation stops; placeholder shapes remain visible.

/// Shimmering placeholder shown while the dashboard data loads.
public struct DashboardSkeletonView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // Greeting skeleton
                skeletonBar(width: 180, height: 28)
                    .padding(.top, BrandSpacing.sm)

                // Hero KPI skeleton
                skeletonCard(height: 100)

                // Tile grid skeleton (4 tiles)
                let columns: [GridItem] = Platform.isCompact
                    ? [GridItem(.adaptive(minimum: 140), spacing: BrandSpacing.md)]
                    : [
                        GridItem(.flexible(), spacing: BrandSpacing.md),
                        GridItem(.flexible(), spacing: BrandSpacing.md),
                        GridItem(.flexible(), spacing: BrandSpacing.md),
                      ]
                LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
                    ForEach(0..<(Platform.isCompact ? 4 : 6), id: \.self) { _ in
                        skeletonCard(height: 80)
                    }
                }

                // Attention card skeleton
                skeletonCard(height: 140)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.sm)
            .padding(.bottom, BrandSpacing.lg)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: false)
            ) {
                phase = 1.0
            }
        }
        .accessibilityLabel("Loading dashboard")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Skeleton primitives

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
            .fill(shimmerGradient)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private func skeletonCard(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            .fill(shimmerGradient)
            .frame(maxWidth: .infinity, minHeight: height)
            .accessibilityHidden(true)
    }

    private var shimmerGradient: LinearGradient {
        let base = Color.bizarreSurface1
        let highlight = Color.bizarreSurface1.opacity(0.4)
        if reduceMotion {
            return LinearGradient(colors: [base], startPoint: .leading, endPoint: .trailing)
        }
        let startFraction = (phase + 1) / 2       // maps -1…1 → 0…1
        return LinearGradient(
            stops: [
                .init(color: base,      location: max(0, startFraction - 0.3)),
                .init(color: highlight, location: startFraction),
                .init(color: base,      location: min(1, startFraction + 0.3)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
