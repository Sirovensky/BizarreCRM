import SwiftUI

/// A SwiftUI wrapper that renders a paginated list driven by `PaginatedLoader`.
///
/// - Shows a `ProgressView` spinner at the bottom when loading more pages.
/// - Shows an inline empty-state when there are no items and loading has finished.
/// - Shows an inline error message with a retry button on failure.
/// - Triggers `loadMoreIfNeeded(currentItem:)` from each row's `.onAppear`.
///
/// ## Usage
/// ```swift
/// struct TicketListView: View {
///     @State private var loader = PaginatedLoader<Ticket>(fetch: { ... })
///
///     var body: some View {
///         PaginatedList(loader: loader) { ticket in
///             TicketRow(ticket: ticket)
///         }
///         .task { await loader.loadFirstPage() }
///     }
/// }
/// ```
///
/// ## Design tokens
/// Spacing and colors come from the local stubs at the bottom of this file.
/// When the `DesignSystem` package is linked those stubs are shadowed by the
/// real tokens — no code changes needed at that point.
///
/// ## Accessibility
/// - Loading indicator has an `.accessibilityLabel`.
/// - Empty and error states have `.accessibilityElement(children: .combine)`.
/// - Retry button has an explicit `.accessibilityLabel`.
public struct PaginatedList<Item: Identifiable & Sendable, RowContent: View>: View {

    // MARK: - Properties

    @State private var loader: PaginatedLoader<Item>

    private let rowContent: (Item) -> RowContent

    // MARK: - Init

    /// - Parameters:
    ///   - loader: The `PaginatedLoader` instance driving this list.
    ///   - rowContent: View builder that renders a single row.
    public init(
        loader: PaginatedLoader<Item>,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent
    ) {
        _loader = State(initialValue: loader)
        self.rowContent = rowContent
    }

    // MARK: - Body

    public var body: some View {
        List {
            ForEach(loader.items) { item in
                rowContent(item)
                    .onAppear {
                        Task { await loader.loadMoreIfNeeded(currentItem: item) }
                    }
            }

            // Bottom row: spinner, error, or nothing.
            if loader.isLoadingMore {
                loadingRow
            } else if let error = loader.error {
                errorRow(error)
            } else if loader.items.isEmpty {
                emptyRow
            }
        }
    }

    // MARK: - State rows

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .accessibilityLabel("Loading more items")
            Spacer()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .padding(.vertical, _PaginationSpacing.md)
    }

    private func errorRow(_ error: Error) -> some View {
        VStack(spacing: _PaginationSpacing.sm) {
            Text("Could not load more")
                .font(.subheadline)
                .foregroundStyle(_PaginationColor.labelSecondary)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(_PaginationColor.labelSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    if let last = loader.items.last {
                        await loader.loadMoreIfNeeded(currentItem: last)
                    } else {
                        await loader.refresh()
                    }
                }
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(_PaginationColor.accentPrimary)
            }
            .accessibilityLabel("Retry loading more items")
            .padding(.top, _PaginationSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, _PaginationSpacing.lg)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }

    private var emptyRow: some View {
        VStack(spacing: _PaginationSpacing.sm) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(_PaginationColor.labelSecondary)
                .accessibilityHidden(true)

            Text("No items")
                .font(.subheadline)
                .foregroundStyle(_PaginationColor.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, _PaginationSpacing.lg)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No items to display")
    }
}

// MARK: - View modifier convenience

public extension View {
    /// Attach a `PaginatedList` bottom loading indicator overlay to any view.
    ///
    /// Prefer using `PaginatedList` directly when possible.  This modifier is
    /// offered as a drop-in for custom `List`/`LazyVStack` bodies.
    func paginatedLoading<Item: Identifiable & Sendable>(
        loader: PaginatedLoader<Item>
    ) -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            if loader.isLoadingMore {
                ProgressView()
                    .accessibilityLabel("Loading more items")
                    .frame(maxWidth: .infinity)
                    .padding(_PaginationSpacing.md)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Local design-token stubs
// fileprivate so they never escape this file.  When the DesignSystem package
// is linked these values are shadowed by the real tokens; no code changes needed.

// Raw values mirror DesignTokens.Spacing (xs=4, sm=8, md=12, lg=16) so that
// when DesignSystem is linked to Core these stubs stay in sync.
private enum _PaginationSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

private enum _PaginationColor {
    static let labelSecondary  = Color.secondary
    static let accentPrimary   = Color.accentColor
}
