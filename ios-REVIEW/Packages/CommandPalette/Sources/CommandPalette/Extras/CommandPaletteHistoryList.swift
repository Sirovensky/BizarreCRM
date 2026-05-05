import SwiftUI
import DesignSystem

// MARK: - CommandPaletteHistoryList

/// Displays recently executed commands and exposes a clear-history action.
///
/// This view is self-contained: it reads from a `RecentUsageStore` and maps
/// stored IDs back to full `CommandAction` values using the supplied catalog.
/// History clearing is handled by `CommandPaletteHistoryClearer` (see
/// `RecentUsageStore+Clear.swift`) so this file has no dependency on the
/// file-private internals of `RecentUsageStore`.
///
/// Layout:
/// - iPhone: plain `List`, "Clear History" toolbar button (destructive role).
/// - iPad: same list, wider affordances, ⌫ keyboard shortcut for clear.
public struct CommandPaletteHistoryList: View {
    private let store: RecentUsageStore
    private let clearer: CommandPaletteHistoryClearer
    private let allActions: [CommandAction]
    private let onSelect: (CommandAction) -> Void

    @State private var recentIDs: [String] = []

    /// - Parameters:
    ///   - store:      The `RecentUsageStore` instance already wired to
    ///                 `CommandPaletteViewModel`.
    ///   - clearer:    Companion that erases the store's persisted list.
    ///                 Defaults to the canonical UserDefaults key.
    ///   - allActions: Full action catalog used to resolve IDs → titles/icons.
    ///   - onSelect:   Called when the user taps a history row.
    public init(
        store: RecentUsageStore,
        clearer: CommandPaletteHistoryClearer = CommandPaletteHistoryClearer(),
        allActions: [CommandAction],
        onSelect: @escaping (CommandAction) -> Void
    ) {
        self.store = store
        self.clearer = clearer
        self.allActions = allActions
        self.onSelect = onSelect
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if recentIDs.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .navigationTitle("Recent Commands")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !recentIDs.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    clearButton
                }
            }
        }
        .onAppear { recentIDs = store.recentIDs }
    }

    // MARK: - Subviews

    private var historyList: some View {
        List {
            ForEach(resolvedActions, id: \.id) { action in
                HistoryRow(action: action)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(action) }
                    .hoverEffect(.highlight)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(action.title)
                    .accessibilityHint("Double tap to execute")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Recent Commands",
            systemImage: "clock.arrow.circlepath",
            description: Text("Commands you execute will appear here.")
        )
        .accessibilityLabel("No recent commands")
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            clearHistory()
        } label: {
            Label("Clear History", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: [])
        .accessibilityLabel("Clear command history")
    }

    // MARK: - Helpers

    /// Maps stored IDs back to `CommandAction`, preserving recency order.
    /// IDs that no longer exist in the catalog are silently dropped.
    private var resolvedActions: [CommandAction] {
        let catalog = Dictionary(uniqueKeysWithValues: allActions.map { ($0.id, $0) })
        return recentIDs.compactMap { catalog[$0] }
    }

    private func clearHistory() {
        clearer.clearHistory()
        recentIDs = []
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let action: CommandAction

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: action.icon)
                .font(.brandBodyLarge())
                .frame(width: DesignTokens.Touch.minTargetSide, alignment: .center)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(action.title)
                .font(.brandBodyLarge())

            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}
