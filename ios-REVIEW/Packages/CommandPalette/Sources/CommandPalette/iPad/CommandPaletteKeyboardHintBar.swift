import SwiftUI
import DesignSystem

// MARK: - CommandPaletteKeyboardHintBar

/// Footer legend showing keyboard shortcuts for the iPad ⌘K overlay.
///
/// Displays: ↑↓ Navigate · ⏎ Execute · ⎋ Dismiss · ⌘K Re-open
///
/// Each glyph is rendered in a rounded monospaced chip backed by
/// `.ultraThinMaterial` to look like a keycap legend.
///
/// Accessibility: the entire bar is hidden from VoiceOver (it only
/// describes hardware keyboard shortcuts irrelevant to pointer/touch).
public struct CommandPaletteKeyboardHintBar: View {

    public init() {}

    // MARK: - Hint model

    private let hints: [KeyHint] = [
        KeyHint(keys: ["↑", "↓"],  label: "Navigate"),
        KeyHint(keys: ["⏎"],        label: "Execute"),
        KeyHint(keys: ["⎋"],        label: "Dismiss"),
        KeyHint(keys: ["⌘", "K"],   label: "Re-open"),
    ]

    // MARK: - Body

    public var body: some View {
        HStack(spacing: BrandSpacing.base) {
            ForEach(hints.indices, id: \.self) { index in
                hintGroup(hints[index])
                if index < hints.count - 1 {
                    separatorDot
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)  // hardware keyboard hints only
    }

    // MARK: - Hint group

    private func hintGroup(_ hint: KeyHint) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            ForEach(hint.keys, id: \.self) { key in
                keyChip(key)
            }
            Text(hint.label)
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Key chip

    private func keyChip(_ glyph: String) -> some View {
        Text(glyph)
            .font(.brandMono(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }

    // MARK: - Separator

    private var separatorDot: some View {
        Text("·")
            .font(.brandLabelSmall())
            .foregroundStyle(.quaternary)
    }
}

// MARK: - KeyHint model

private struct KeyHint {
    let keys: [String]
    let label: String
}

// MARK: - Preview

#if DEBUG
struct CommandPaletteKeyboardHintBar_Previews: PreviewProvider {
    static var previews: some View {
        CommandPaletteKeyboardHintBar()
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .background(.ultraThinMaterial)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Keyboard Hint Bar")
    }
}
#endif
