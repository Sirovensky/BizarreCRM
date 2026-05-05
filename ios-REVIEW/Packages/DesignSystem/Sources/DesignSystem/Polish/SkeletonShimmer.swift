import SwiftUI

// MARK: - SkeletonShimmer modifier

/// Applies a shimmering placeholder animation to any view.
///
/// Uses `.redacted(reason: .placeholder)` combined with a sweeping
/// gradient mask for the "shimmer" effect on iOS 17+.
///
/// Reduce Motion: gradient sweep is disabled; only `.redacted` is applied.
///
/// **Usage (row placeholder):**
/// ```swift
/// if isLoading {
///     ForEach(0..<5, id: \.self) { _ in
///         TicketRowPlaceholder()
///             .skeletonShimmer()
///     }
/// }
/// ```
public struct SkeletonShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        if reduceMotion {
            content
                .redacted(reason: .placeholder)
        } else {
            content
                .redacted(reason: .placeholder)
                .overlay {
                    ShimmerOverlay()
                }
                .clipped()
        }
    }
}

// MARK: - ShimmerOverlay

private struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1.0

    private let shimmerColors: [Color] = [
        .white.opacity(0),
        .white.opacity(0.3),
        .white.opacity(0)
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: shimmerColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 2)
            .offset(x: phase * width)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - View extension

public extension View {
    /// Applies skeleton shimmer — placeholder redaction + animated sweep.
    /// Automatically disables sweep when Reduce Motion is on.
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmerModifier())
    }
}

// MARK: - SkeletonRow

/// Generic single-row skeleton placeholder matching typical list rows.
/// Use inside `ForEach(0..<count, id: \.self)` while loading.
public struct SkeletonRow: View {
    /// Whether to show a leading circle avatar placeholder.
    public let showAvatar: Bool
    /// Number of lines to simulate.
    public let lines: Int

    public init(showAvatar: Bool = false, lines: Int = 2) {
        self.showAvatar = showAvatar
        self.lines = max(1, lines)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            if showAvatar {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                // First line — wider (title)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)

                // Additional lines — shorter
                if lines > 1 {
                    ForEach(1..<lines, id: \.self) { i in
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 11)
                            .frame(maxWidth: i == lines - 1 ? 180 : .infinity)
                    }
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityHidden(true)
    }
}

// MARK: - SkeletonList

/// Drop-in replacement for a `List` during initial loading.
///
/// ```swift
/// if viewModel.isLoading {
///     SkeletonList(rowCount: 6, showAvatars: true)
/// } else {
///     actualList
/// }
/// ```
public struct SkeletonList: View {
    public let rowCount: Int
    public let showAvatars: Bool
    public let linesPerRow: Int

    public init(rowCount: Int = 5, showAvatars: Bool = false, linesPerRow: Int = 2) {
        self.rowCount = max(1, rowCount)
        self.showAvatars = showAvatars
        self.linesPerRow = linesPerRow
    }

    public var body: some View {
        List {
            ForEach(0..<rowCount, id: \.self) { _ in
                SkeletonRow(showAvatar: showAvatars, lines: linesPerRow)
                    .skeletonShimmer()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Loading")
        .accessibilityElement(children: .ignore)
    }
}
