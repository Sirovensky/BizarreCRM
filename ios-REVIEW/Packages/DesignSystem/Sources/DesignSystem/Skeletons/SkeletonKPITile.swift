import SwiftUI

// MARK: - SkeletonKPITile (§91.16 KPI tile placeholder skeleton)
//
// Shape-matched placeholder for a KPI cell (icon + label + large value +
// optional delta badge).  Mirrors the visual rhythm of `SalesKPISummaryCard`
// kpiCell / `pnlMetric` without coupling to any domain model.
//
// Usage:
//   SkeletonKPITile()               // single cell (e.g. inside a 2×2 grid)
//   SkeletonKPITile(showDelta: false)
//
// For a full-card placeholder matching SalesKPISummaryCard:
//   SkeletonKPISummaryCard()        // 2-up iPhone / 4-up iPad layout

/// A single KPI metric cell placeholder — icon chip + label line + large value
/// line + optional trend-delta chip.
public struct SkeletonKPITile: View {

    // MARK: - Constants

    public static let iconSize: CGFloat = DesignTokens.Icon.medium       // 20 pt
    public static let labelLineHeight: CGFloat = 11
    public static let valueLineHeight: CGFloat = 28                      // matches brandKpiValue
    public static let deltaChipWidth: CGFloat = 52
    public static let deltaChipHeight: CGFloat = 16

    // MARK: - Stored properties

    /// When `true` a small delta-badge placeholder is rendered below the value.
    public let showDelta: Bool

    // MARK: - Init

    public init(showDelta: Bool = true) {
        self.showDelta = showDelta
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            // Row: icon chip + label text line
            HStack(spacing: DesignTokens.Spacing.xs) {
                SkeletonShape(.circle, size: CGSize(width: Self.iconSize,
                                                    height: Self.iconSize))
                SkeletonTextLine(widthFraction: 0.55, lineHeight: Self.labelLineHeight)
            }

            // Large value placeholder
            SkeletonTextLine(widthFraction: 0.75, lineHeight: Self.valueLineHeight)

            // Optional delta chip
            if showDelta {
                SkeletonShape(
                    .capsule,
                    size: CGSize(width: Self.deltaChipWidth, height: Self.deltaChipHeight)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - SkeletonKPISummaryCard

/// Full-card skeleton that mirrors `SalesKPISummaryCard` layout:
/// a header label + 2×2 grid on iPhone, single row of 4 on iPad.
public struct SkeletonKPISummaryCard: View {

    // MARK: - Constants

    public static let cardCornerRadius: CGFloat = DesignTokens.Radius.xl

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Section title placeholder
            SkeletonTextLine(widthFraction: 0.40, lineHeight: 16)

            if isCompact {
                // iPhone: 2×2 grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        SkeletonKPITile()
                    }
                }
            } else {
                // iPad: single horizontal row
                HStack(spacing: DesignTokens.Spacing.xl) {
                    ForEach(0 ..< 4, id: \.self) { idx in
                        SkeletonKPITile()
                        if idx < 3 {
                            Divider().frame(height: 48).opacity(0.15)
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: Self.cardCornerRadius)
        )
        .accessibilityLabel("Loading summary")
        .accessibilityElement(children: .ignore)
    }

    // MARK: - Helpers

    /// Compact-width heuristic that avoids importing `Core.Platform` from DesignSystem.
    private var isCompact: Bool {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width < 600
        #else
        return false
        #endif
    }
}
