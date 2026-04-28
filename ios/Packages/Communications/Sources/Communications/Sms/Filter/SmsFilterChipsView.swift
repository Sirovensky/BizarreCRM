import SwiftUI
import DesignSystem

// MARK: - SmsFilterChipsView
//
// Horizontal scrollable chip bar for §12.1 Filters — All / Unread / Flagged /
// Pinned / Archived / Assigned to me / Unassigned.
// Chips use Liquid Glass on chrome layer per §30 rules.

public struct SmsFilterChipsView: View {
    @Binding public var selected: SmsListFilterTab
    // Counts supplied by the ViewModel for badge display.
    public let counts: [SmsListFilterTab: Int]

    public init(selected: Binding<SmsListFilterTab>, counts: [SmsListFilterTab: Int] = [:]) {
        self._selected = selected
        self.counts = counts
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(SmsListFilterTab.allCases) { tab in
                    Chip(
                        tab: tab,
                        isSelected: selected == tab,
                        count: counts[tab]
                    ) {
                        withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
                            selected = tab
                        }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    // MARK: - Chip

    private struct Chip: View {
        let tab: SmsListFilterTab
        let isSelected: Bool
        let count: Int?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: tab.icon)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(tab.label)
                        .font(.brandLabelLarge())
                    if let n = count, n > 0 {
                        Text("\(n)")
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.xs)
                            .background(Color.white.opacity(0.25), in: Capsule())
                    }
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(isSelected ? Color.black : Color.bizarreOnSurface)
                .background(isSelected ? Color.bizarreOrange : Color.bizarreSurface1, in: Capsule())
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .keyboardShortcut(tabShortcut ?? "0", modifiers: [.command, .shift])
        }

        private var accessibilityLabel: String {
            if let n = count, n > 0 {
                return "\(tab.label), \(n) conversations"
            }
            return tab.label
        }

        private var tabShortcut: KeyEquivalent? {
            switch tab {
            case .all:        return "1"
            case .unread:     return "2"
            case .flagged:    return "3"
            case .pinned:     return "4"
            case .archived:   return "5"
            case .assignedMe: return "6"
            case .unassigned: return "7"
            case .teamInbox:  return "8"
            }
        }
    }
}
