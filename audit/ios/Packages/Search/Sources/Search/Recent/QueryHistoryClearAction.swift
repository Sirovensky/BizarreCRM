import SwiftUI
import DesignSystem

// MARK: - QueryHistoryClearAction

/// A toolbar button + confirmation dialog that clears the user's full
/// query history from `RecentSearchStore`.
///
/// **Usage:**
/// ```swift
/// RecentSearchesView(queries: queries, …)
///     .toolbar {
///         QueryHistoryClearAction(store: recentStore) {
///             await loadRecent() // refresh caller state
///         }
///     }
/// ```
public struct QueryHistoryClearAction: ToolbarContent {

    // MARK: - State

    @State private var showingConfirm: Bool = false

    // MARK: - Dependencies

    private let store: RecentSearchStore
    private let onCleared: () async -> Void

    // MARK: - Init

    /// - Parameters:
    ///   - store: The `RecentSearchStore` actor to clear.
    ///   - onCleared: Async callback invoked after the store is cleared so the
    ///     caller can refresh its local `@State` copies of the query list.
    public init(store: RecentSearchStore, onCleared: @escaping () async -> Void) {
        self.store = store
        self.onCleared = onCleared
    }

    // MARK: - ToolbarContent

    public var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                showingConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Clear search history")
            .confirmationDialog(
                "Clear Search History",
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    Task {
                        await store.clear()
                        await onCleared()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all recent searches from this device. It cannot be undone.")
            }
        }
    }
}

// MARK: - QueryHistoryClearButton

/// Standalone destructive button variant for embedding directly in list footers
/// or settings pages rather than a toolbar.
///
/// **Usage:**
/// ```swift
/// Section {
///     QueryHistoryClearButton(store: recentStore) { await loadRecent() }
/// }
/// ```
public struct QueryHistoryClearButton: View {

    @State private var showingConfirm: Bool = false

    private let store: RecentSearchStore
    private let onCleared: () async -> Void

    public init(store: RecentSearchStore, onCleared: @escaping () async -> Void) {
        self.store = store
        self.onCleared = onCleared
    }

    public var body: some View {
        Button(role: .destructive) {
            showingConfirm = true
        } label: {
            Label("Clear Search History", systemImage: "trash")
        }
        .accessibilityLabel("Clear all recent searches")
        .confirmationDialog(
            "Clear Search History",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task {
                    await store.clear()
                    await onCleared()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all recent searches from this device. It cannot be undone.")
        }
    }
}
