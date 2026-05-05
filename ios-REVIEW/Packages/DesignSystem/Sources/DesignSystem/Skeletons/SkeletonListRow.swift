import SwiftUI

// MARK: - SkeletonListRow

/// A list-row skeleton with a circular avatar placeholder, two text-line
/// placeholders, and an optional trailing badge placeholder.
///
/// Mirrors the visual weight of a typical CRM list row without coupling
/// to any domain model.
///
/// ```swift
/// // Inside a loading List:
/// ForEach(0..<6, id: \.self) { _ in
///     SkeletonListRow()
/// }
///
/// // With badge visible:
/// SkeletonListRow(showTrailingBadge: true)
/// ```
public struct SkeletonListRow: View {

    // MARK: - Constants

    /// Diameter of the avatar circle placeholder.
    public static let avatarDiameter: CGFloat = 40
    /// Height of the primary (title) text bar.
    public static let titleLineHeight: CGFloat = 14
    /// Height of the secondary (subtitle) text bar.
    public static let subtitleLineHeight: CGFloat = 11
    /// Width of the trailing badge placeholder.
    public static let badgeWidth: CGFloat = 44
    /// Height of the trailing badge placeholder.
    public static let badgeHeight: CGFloat = 20

    // MARK: - Stored properties

    /// When `true`, a rounded-rectangle badge placeholder is shown at the trailing edge.
    public let showTrailingBadge: Bool

    // MARK: - Init

    public init(showTrailingBadge: Bool = false) {
        self.showTrailingBadge = showTrailingBadge
    }

    // MARK: - Body

    public var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            // Avatar
            SkeletonShape(.circle, size: CGSize(width: Self.avatarDiameter,
                                                height: Self.avatarDiameter))

            // Text lines
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                SkeletonTextLine(widthFraction: 0.70, lineHeight: Self.titleLineHeight)
                SkeletonTextLine(widthFraction: 0.45, lineHeight: Self.subtitleLineHeight)
            }

            Spacer(minLength: 0)

            // Trailing badge
            if showTrailingBadge {
                SkeletonShape(
                    .capsule,
                    size: CGSize(width: Self.badgeWidth, height: Self.badgeHeight)
                )
            }
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityHidden(true)
        .accessibilityElement(children: .ignore)
    }
}
