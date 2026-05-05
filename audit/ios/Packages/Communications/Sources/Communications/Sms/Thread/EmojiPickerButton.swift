import SwiftUI
import DesignSystem

// MARK: - EmojiPickerButton
//
// §12.2 Emoji picker — tapping the smiley button in the SMS composer presents
// a compact grid of frequently-used emoji. Tapping an emoji inserts it at the
// cursor position via the parent binding.
//
// Architecture:
//   EmojiPickerButton  — toolbar button that presents EmojiPickerPopover
//   EmojiPickerPopover — compact emoji grid (6 × N rows, most-used defaults)
//
// The system emoji keyboard is NOT used here (would require sacrificing the
// custom chip bar). Instead we ship a curated set; users can always switch to
// the system keyboard via the globe key on hardware keyboards.

private let defaultEmoji: [String] = [
    "😊", "👍", "🙌", "🎉", "✅", "❤️",
    "😂", "🤝", "🔧", "🛠️", "📱", "💵",
    "⚠️", "📦", "🔑", "⏰", "✉️", "📞",
    "🙏", "😎", "🚀", "💯", "🎯", "🤔",
]

public struct EmojiPickerButton: View {
    @Binding var draft: String
    @State private var showPopover = false

    public init(draft: Binding<String>) {
        _draft = draft
    }

    public var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 20))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Open emoji picker")
        .accessibilityIdentifier("emoji.picker.button")
        .popover(isPresented: $showPopover, attachmentAnchor: .point(.top)) {
            EmojiPickerPopover(onSelect: { emoji in
                draft.append(emoji)
                showPopover = false
            })
        }
    }
}

// MARK: - EmojiPickerPopover

private struct EmojiPickerPopover: View {
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 4), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(defaultEmoji, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                        BrandHaptics.tap()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert \(emoji)")
                }
            }
            .padding(BrandSpacing.sm)
        }
        .frame(width: 290, height: 180)
        .background(Color.bizarreSurface1)
    }
}
