import SwiftUI

// MARK: - MaxContentWidthModifier

/// A view modifier that caps content width at a configurable maximum,
/// centres the content horizontally, and applies symmetric horizontal padding.
///
/// Ideal for detail panes on 13" iPad landscape where unconstrained text
/// becomes hard to read. Default cap is 720 pt, matching §22.1.
///
/// ```swift
/// ScrollView {
///     DetailContent()
///         .maxContentWidth()           // caps at 720 pt, 16 pt padding
///         .maxContentWidth(560)        // compact override
///         .maxContentWidth(680, padding: 24)
/// }
/// ```
public struct MaxContentWidthModifier: ViewModifier {

    // MARK: - Stored properties

    /// Hard cap in points.
    public let maxWidth: CGFloat
    /// Horizontal padding applied inside the capped frame (bleed space).
    public let horizontalPadding: CGFloat

    // MARK: - Init

    /// - Parameters:
    ///   - maxWidth: Maximum content width in points. Default `720`.
    ///   - horizontalPadding: Symmetric horizontal padding added inside the
    ///     capped frame. Default `BrandSpacing.base` (16 pt).
    public init(maxWidth: CGFloat = 720, horizontalPadding: CGFloat = BrandSpacing.base) {
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
    }

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - View extension

public extension View {

    /// Caps the receiver's width at `width` points, centres it, and applies
    /// `padding` as horizontal bleed space.
    ///
    /// - Parameters:
    ///   - width: Maximum width in points. Default `720`.
    ///   - padding: Horizontal padding inside the cap. Default `BrandSpacing.base`.
    /// - Returns: A view limited to `width` points, centred in available space.
    func maxContentWidth(
        _ width: CGFloat = 720,
        padding: CGFloat = BrandSpacing.base
    ) -> some View {
        modifier(MaxContentWidthModifier(maxWidth: width, horizontalPadding: padding))
    }
}
