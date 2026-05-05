import SwiftUI

// MARK: - SelectedCardBorderModifier
// §26.5 — Contrast borders on selected cards.
//
// WCAG SC 1.4.1 forbids conveying selection state via color alone; a visible
// border difference must exist.  When "Increase Contrast" is on
// (`colorSchemeContrast == .increased`) the border is thickened and darkened
// so it meets the 3:1 non-text contrast ratio against the card surface.
//
// For regular contrast the border is present (1 pt, brand-primary) only when
// the card is selected; under increased-contrast it becomes 2 pt and opaque.
// Deselected cards carry no border in regular contrast but gain a faint
// separator (0.5 pt) under increased contrast for additional surface depth.
//
// **Usage:**
// ```swift
// CardView(item: item)
//     .selectedCardBorder(isSelected: item.id == selectedID)
// ```

public struct SelectedCardBorderModifier: ViewModifier {

    // MARK: Configuration

    /// Whether the card is currently in a selected state.
    public let isSelected: Bool
    /// Corner radius of the card — must match the card's own radius.
    public let cornerRadius: CGFloat
    /// Color used for the selected border stroke.
    public let selectedColor: Color

    // MARK: Environment

    @Environment(\.colorSchemeContrast) private var contrast

    // MARK: Init

    public init(
        isSelected: Bool,
        cornerRadius: CGFloat = DesignTokens.Radius.lg,
        selectedColor: Color = .bizarrePrimary
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.selectedColor = selectedColor
    }

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            }
    }

    // MARK: Private helpers

    private var isHighContrast: Bool { contrast == .increased }

    /// Stroke color depends on selection state and contrast setting.
    private var strokeColor: Color {
        if isSelected {
            return isHighContrast
                ? selectedColor          // fully opaque
                : selectedColor.opacity(0.85)
        } else {
            return isHighContrast
                ? Color.primary.opacity(0.18)   // faint separator under high-contrast
                : Color.clear
        }
    }

    /// Stroke width: thicker when selected, even more so under increased contrast.
    private var strokeWidth: CGFloat {
        if isSelected {
            return isHighContrast ? 2.5 : 1.5
        } else {
            return isHighContrast ? 0.5 : 0
        }
    }
}

// MARK: - View extension

public extension View {
    /// Applies a selection-state border to a card view.
    ///
    /// - Parameters:
    ///   - isSelected: Whether this card is currently selected.
    ///   - cornerRadius: Must match the card's own corner radius. Default `DesignTokens.Radius.lg`.
    ///   - selectedColor: Brand-primary color used for the selected stroke. Default `.bizarrePrimary`.
    func selectedCardBorder(
        isSelected: Bool,
        cornerRadius: CGFloat = DesignTokens.Radius.lg,
        selectedColor: Color = .bizarrePrimary
    ) -> some View {
        modifier(SelectedCardBorderModifier(
            isSelected: isSelected,
            cornerRadius: cornerRadius,
            selectedColor: selectedColor
        ))
    }
}
