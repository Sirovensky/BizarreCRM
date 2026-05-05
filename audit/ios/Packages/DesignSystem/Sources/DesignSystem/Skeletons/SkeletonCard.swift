import SwiftUI

// MARK: - SkeletonCard

/// A full-card skeleton with a header (avatar + two lines), a body region
/// (configurable line count), and a footer (two short buttons / tags).
///
/// Matches the visual rhythm of CRM entity cards (contact cards, deal cards,
/// ticket summaries) without coupling to domain models.
///
/// ```swift
/// SkeletonCard()
/// SkeletonCard(bodyLines: 4, showFooter: false)
/// ```
public struct SkeletonCard: View {

    // MARK: - Constants

    public static let headerAvatarDiameter: CGFloat = 36
    public static let bodyLineHeight: CGFloat = 12
    public static let footerChipWidth: CGFloat = 72
    public static let footerChipHeight: CGFloat = 22
    public static let cardCornerRadius: CGFloat = DesignTokens.Radius.lg
    public static let minimumBodyLines: Int = 1
    public static let maximumBodyLines: Int = 8

    // MARK: - Stored properties

    /// Number of body text-line placeholders. Clamped 1...8.
    public let bodyLines: Int
    /// When `true`, the footer strip with two chip placeholders is shown.
    public let showFooter: Bool

    // MARK: - Init

    public init(bodyLines: Int = 3, showFooter: Bool = true) {
        self.bodyLines = bodyLines.clamped(to: Self.minimumBodyLines ... Self.maximumBodyLines)
        self.showFooter = showFooter
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
                .padding(DesignTokens.Spacing.lg)

            Divider()
                .opacity(0.1)

            // Body
            bodySection
                .padding(DesignTokens.Spacing.lg)

            if showFooter {
                Divider()
                    .opacity(0.1)

                // Footer
                footer
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.md)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
        .accessibilityHidden(true)
        .accessibilityElement(children: .ignore)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            SkeletonShape(.circle, size: CGSize(width: Self.headerAvatarDiameter,
                                               height: Self.headerAvatarDiameter))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                SkeletonTextLine(widthFraction: 0.60, lineHeight: 14)
                SkeletonTextLine(widthFraction: 0.35, lineHeight: 11)
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            ForEach(0 ..< bodyLines, id: \.self) { index in
                // Last line is shorter to simulate natural text wrap
                let fraction: CGFloat = index == bodyLines - 1 ? 0.55 : 1.0
                SkeletonTextLine(widthFraction: fraction, lineHeight: Self.bodyLineHeight)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            SkeletonShape(.capsule, size: CGSize(width: Self.footerChipWidth,
                                                height: Self.footerChipHeight))
            SkeletonShape(.capsule, size: CGSize(width: Self.footerChipWidth * 0.75,
                                                height: Self.footerChipHeight))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Comparable clamp (local file scope)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
