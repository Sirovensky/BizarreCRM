import SwiftUI
import DesignSystem

// MARK: - SearchLoadingSkeleton

/// Full-page shimmer skeleton displayed while search results are loading.
///
/// Replaces the plain `SkeletonRow` list inside `GlobalSearchView.skeletonView`
/// with a richer multi-section card layout that more closely mirrors the final
/// result list, reducing layout shift when real results arrive.
///
/// **Usage (drop-in replacement for `skeletonView` in `GlobalSearchView`):**
/// ```swift
/// } else if vm.isLoading && vm.mergedRows.isEmpty {
///     SearchLoadingSkeleton()
/// }
/// ```
public struct SearchLoadingSkeleton: View {

    // MARK: - Init

    /// - Parameter rowCount: Total skeleton rows to render (defaults to 6).
    public init(rowCount: Int = 6) {
        self.rowCount = rowCount
    }

    // MARK: - Private

    private let rowCount: Int
    @State private var shimmerPhase: CGFloat = 0

    // MARK: - Body

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    SkeletonResultCard(
                        shimmerPhase: shimmerPhase,
                        // Vary widths so consecutive rows don't look identical.
                        titleWidth: titleWidths[index % titleWidths.count],
                        subtitleWidth: subtitleWidths[index % subtitleWidths.count]
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, index == 0 ? BrandSpacing.base : BrandSpacing.xs)

                    if index < rowCount - 1 {
                        Divider()
                            .padding(.horizontal, BrandSpacing.base + 44)
                    }
                }
                // Bottom spacing for overscroll feel
                Color.clear.frame(height: BrandSpacing.lg)
            }
        }
        .scrollDisabled(true)
        .background(Color.bizarreSurfaceBase)
        .onAppear { startShimmer() }
        .accessibilityLabel("Loading search results")
        .accessibilityHidden(false)
    }

    // MARK: - Shimmer animation

    private func startShimmer() {
        withAnimation(
            .linear(duration: 1.4)
            .repeatForever(autoreverses: false)
        ) {
            shimmerPhase = 1
        }
    }

    // MARK: - Width variation tables

    private let titleWidths: [CGFloat]    = [160, 200, 140, 180, 120, 190]
    private let subtitleWidths: [CGFloat] = [100, 130, 90,  110, 140, 80]
}

// MARK: - SkeletonResultCard

private struct SkeletonResultCard: View {
    let shimmerPhase: CGFloat
    let titleWidth: CGFloat
    let subtitleWidth: CGFloat

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            // Icon placeholder
            SkeletonShape(shimmerPhase: shimmerPhase)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                // Title line
                SkeletonShape(shimmerPhase: shimmerPhase)
                    .frame(width: titleWidth, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Subtitle line
                SkeletonShape(shimmerPhase: shimmerPhase)
                    .frame(width: subtitleWidth, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Entity badge pill
                SkeletonShape(shimmerPhase: shimmerPhase)
                    .frame(width: 54, height: 10)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityHidden(true)
    }
}

// MARK: - SkeletonShape

/// A rectangle filled with a horizontally-sweeping shimmer gradient.
///
/// `shimmerPhase` (0…1, animated via `.repeatForever`) drives the gradient
/// offset so the highlight moves left-to-right continuously.
private struct SkeletonShape: View {
    let shimmerPhase: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Rectangle()
                .fill(shimmerGradient(width: width))
        }
    }

    private func shimmerGradient(width: CGFloat) -> some ShapeStyle {
        let baseColor   = Color.bizarreOnSurface.opacity(0.07)
        let shineColor  = Color.bizarreOnSurface.opacity(0.15)
        // Shift the highlight from -100% to +200% of the view width
        let startX = width * (shimmerPhase * 3 - 1)
        return LinearGradient(
            stops: [
                .init(color: baseColor,  location: 0.0),
                .init(color: shineColor, location: 0.4),
                .init(color: baseColor,  location: 0.8)
            ],
            startPoint: UnitPoint(x: (startX - width * 0.5) / max(width, 1), y: 0.5),
            endPoint:   UnitPoint(x: (startX + width * 1.5) / max(width, 1), y: 0.5)
        )
    }
}
