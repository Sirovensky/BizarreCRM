import SwiftUI

// §26.2 — LargeTextAlertLayout
// When `dynamicTypeSize.isAccessibilitySize` is true (AX1–AX5), alert-style
// layouts that place an icon or leading badge beside a text block switch to a
// vertical stack so no primary text is ever truncated.
//
// This modifier requires no app-level toggle; it reads `\.dynamicTypeSize`
// from the SwiftUI environment and reflows automatically when the user changes
// their text-size preference at the OS level.

// MARK: - LargeTextAlertLayout

/// A layout container that places `icon` beside `content` horizontally at
/// normal text sizes, and stacks them vertically at accessibility-large sizes
/// (AX1–AX5, i.e. when `dynamicTypeSize.isAccessibilitySize == true`).
///
/// Primary headings inside `content` are given `.lineLimit(nil)` headroom so
/// they are never truncated regardless of size.
///
/// **Usage:**
/// ```swift
/// LargeTextAlertLayout {
///     Image(systemName: "exclamationmark.triangle.fill")
///         .foregroundStyle(.brandWarning)
/// } content: {
///     VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
///         Text("Payment declined").font(.headline)
///         Text("Check card details and try again.").font(.subheadline)
///     }
/// }
/// ```
public struct LargeTextAlertLayout<Icon: View, Content: View>: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let icon: Icon
    private let content: Content
    private let spacing: CGFloat

    public init(
        spacing: CGFloat = DesignTokens.Spacing.md,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.icon = icon()
        self.content = content()
    }

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) {
                icon
                content
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: spacing) {
                icon
                content
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
