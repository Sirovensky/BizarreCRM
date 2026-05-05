import SwiftUI

// MARK: - SkeletonGrid

/// An adaptive grid of `SkeletonCard` placeholders for catalog / gallery screens.
///
/// Columns adapt to the available width using `LazyVGrid` with adaptive sizing,
/// matching the same layout logic used by real catalog grids in the app.
///
/// Supports both iPhone (1-2 columns) and iPad (3+ columns) without
/// additional branching at call sites — `LazyVGrid` with `.adaptive` handles it.
///
/// ```swift
/// // While loading the product catalog:
/// if viewModel.isLoading {
///     SkeletonGrid()
/// } else {
///     actualCatalogGrid
/// }
///
/// // Larger minimum column width for a 2-up iPhone layout:
/// SkeletonGrid(minimumCardWidth: 160, cardCount: 6)
/// ```
public struct SkeletonGrid: View {

    // MARK: - Constants

    /// Default minimum card width. `LazyVGrid` will fit as many columns as possible.
    public static let defaultMinimumCardWidth: CGFloat = 150
    /// Default number of skeleton cards rendered.
    public static let defaultCardCount: Int = 6
    /// Minimum allowed card count (avoids empty grids).
    public static let minimumCardCount: Int = 1
    /// Maximum allowed card count (guards against runaway renders).
    public static let maximumCardCount: Int = 24
    /// Default body-line count forwarded to each `SkeletonCard`.
    public static let defaultCardBodyLines: Int = 2
    /// Default spacing between grid columns and rows.
    public static let defaultSpacing: CGFloat = DesignTokens.Spacing.md

    // MARK: - Stored properties

    /// Minimum column width in points. `LazyVGrid` uses `.adaptive`.
    public let minimumCardWidth: CGFloat
    /// Number of `SkeletonCard` instances rendered. Clamped 1...24.
    public let cardCount: Int
    /// Number of body lines inside each card placeholder.
    public let cardBodyLines: Int
    /// Spacing between cards (horizontal and vertical).
    public let spacing: CGFloat
    /// When `true`, each card shows a footer strip.
    public let showCardFooter: Bool

    // MARK: - Init

    public init(
        minimumCardWidth: CGFloat = defaultMinimumCardWidth,
        cardCount: Int = defaultCardCount,
        cardBodyLines: Int = defaultCardBodyLines,
        spacing: CGFloat = defaultSpacing,
        showCardFooter: Bool = true
    ) {
        self.minimumCardWidth = max(80, minimumCardWidth)
        self.cardCount = cardCount.clamped(to: Self.minimumCardCount ... Self.maximumCardCount)
        self.cardBodyLines = cardBodyLines
        self.spacing = max(0, spacing)
        self.showCardFooter = showCardFooter
    }

    // MARK: - Body

    public var body: some View {
        let columns = [GridItem(.adaptive(minimum: minimumCardWidth), spacing: spacing)]

        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(0 ..< cardCount, id: \.self) { _ in
                    SkeletonCard(bodyLines: cardBodyLines, showFooter: showCardFooter)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .accessibilityLabel("Loading")
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - Comparable clamp (local file scope)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
