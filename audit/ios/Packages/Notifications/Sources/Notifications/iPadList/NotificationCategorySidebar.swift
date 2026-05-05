import SwiftUI
import DesignSystem

// MARK: - NotificationSidebarCategory
//
// §22 iPad sidebar — five fixed buckets. Server-side flagging / pinning /
// archiving is a future phase; the categories still render with correct
// empty-state messaging when their counts are zero.

public enum NotificationSidebarCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all      = "all"
    case unread   = "unread"
    case flagged  = "flagged"
    case pinned   = "pinned"
    case archived = "archived"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all:      return "All"
        case .unread:   return "Unread"
        case .flagged:  return "Flagged"
        case .pinned:   return "Pinned"
        case .archived: return "Archived"
        }
    }

    public var icon: String {
        switch self {
        case .all:      return "bell"
        case .unread:   return "envelope.badge"
        case .flagged:  return "flag"
        case .pinned:   return "pin"
        case .archived: return "archivebox"
        }
    }

    /// Keyboard shortcut: ⌘1 … ⌘5 in sidebar order.
    public var keyboardShortcut: KeyEquivalent {
        switch self {
        case .all:      return "1"
        case .unread:   return "2"
        case .flagged:  return "3"
        case .pinned:   return "4"
        case .archived: return "5"
        }
    }
}

// MARK: - NotificationCategorySidebar

/// iPad §22 sidebar — category list with badge counts, Liquid Glass header,
/// and ⌘1…⌘5 keyboard shortcuts.
///
/// Liquid Glass is applied to the sidebar header only (navigation chrome).
/// Category rows are plain content — no glass per CLAUDE.md rule.
public struct NotificationCategorySidebar: View {

    // MARK: - Inputs

    @Binding public var selectedCategory: NotificationSidebarCategory
    public let unreadCount: Int
    public let itemCounts: [NotificationSidebarCategory: Int]
    public var onSelect: ((NotificationSidebarCategory) -> Void)?

    // MARK: - Init

    public init(
        selectedCategory: Binding<NotificationSidebarCategory>,
        unreadCount: Int,
        itemCounts: [NotificationSidebarCategory: Int],
        onSelect: ((NotificationSidebarCategory) -> Void)? = nil
    ) {
        _selectedCategory = selectedCategory
        self.unreadCount = unreadCount
        self.itemCounts = itemCounts
        self.onSelect = onSelect
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            categoryList
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Sidebar header (glass chrome)

    private var sidebarHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "bell.badge")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Notifications")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if unreadCount > 0 {
                BrandGlassBadge("\(unreadCount)", variant: .regular, tint: .bizarreOrange)
                    .accessibilityLabel("\(unreadCount) unread")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.top, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unreadCount > 0
            ? "Notifications, \(unreadCount) unread"
            : "Notifications")
    }

    // MARK: - Category list
    // Using List(selection:) with .tag() for native sidebar selection highlight.
    // Keyboard shortcuts are applied via NotificationListKeyboardShortcutsModifier
    // at the root NavigationSplitView level.

    private var categoryList: some View {
        List {
            Section {
                ForEach(NotificationSidebarCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                        onSelect?(category)
                    } label: {
                        categoryRow(category)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Category row

    private func categoryRow(_ category: NotificationSidebarCategory) -> some View {
        let count = itemCounts[category] ?? 0
        let isActive = selectedCategory == category

        return HStack(spacing: BrandSpacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(category.label)
                .font(.brandBodyLarge())
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(.bizarreOnSurface)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .monospacedDigit()
                    .accessibilityLabel("\(count) notifications")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .accessibilityLabel("\(category.label)\(count > 0 ? ", \(count) notifications" : "")")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("notif.ipad.sidebar.\(category.id)")
    }
}
