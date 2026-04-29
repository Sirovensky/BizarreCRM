import SwiftUI

// MARK: - SectionDivider (§91.16 list-section divider tokens)
//
// A one-line separator that uses the canonical divider color tokens from
// `DesignTokens.SectionDividerWeight` so every list section boundary in
// the app shares a single source of truth.
//
// Usage:
//   SectionDivider()                            // .subtle (default)
//   SectionDivider(.strong)                     // major section break
//   SectionDivider(.hairline, leadingInset: 52) // after a row with 20pt icon + 16+16 padding

/// A semantically-weighted horizontal rule for list and settings screens.
///
/// The three weights map to opacity values defined in
/// `DesignTokens.SectionDividerWeight` — callers never hard-code a raw opacity.
///
/// ```swift
/// // Between two settings sections:
/// SectionDivider(.strong)
///
/// // Under a row whose leading icon is 52 pt wide (inset matches List inset):
/// SectionDivider(.subtle, leadingInset: 52)
/// ```
public struct SectionDivider: View {

    // MARK: - Stored properties

    public let weight: DesignTokens.SectionDividerWeight
    /// Optional leading inset in points. When non-zero, the divider is indented
    /// to align with the text of a row that has a leading icon (mimics the
    /// native `List` separator inset).
    public let leadingInset: CGFloat

    // MARK: - Init

    public init(
        _ weight: DesignTokens.SectionDividerWeight = .subtle,
        leadingInset: CGFloat = 0
    ) {
        self.weight = weight
        self.leadingInset = max(0, leadingInset)
    }

    // MARK: - Body

    public var body: some View {
        Divider()
            .overlay(DesignTokens.SemanticColor.borderSubtle.opacity(weight.opacity))
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

// MARK: - View extension sugar

public extension View {
    /// Appends a `SectionDivider` below this view inside a `VStack`.
    ///
    /// ```swift
    /// rowView.sectionDivider()
    /// rowView.sectionDivider(.strong, leadingInset: 52)
    /// ```
    func sectionDivider(
        _ weight: DesignTokens.SectionDividerWeight = .subtle,
        leadingInset: CGFloat = 0
    ) -> some View {
        VStack(spacing: 0) {
            self
            SectionDivider(weight, leadingInset: leadingInset)
        }
    }
}
