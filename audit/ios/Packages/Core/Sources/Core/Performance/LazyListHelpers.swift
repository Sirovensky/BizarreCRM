import SwiftUI

// §29.4 Pagination — lazy list helpers.
//
// Three reusable building-blocks for cursor-paginated lists:
//
//   1. `LoadMoreTrigger`   — invisible view placed at the bottom of a List.
//      When it appears inside the viewport it fires `onTrigger`. Call sites
//      wire this to `viewModel.loadNextPage()`.
//
//   2. `ListLoadMoreFooter` — four-state footer row (§29.4):
//      • .loading        → "Loading…"
//      • .partial(n, ~m) → "Showing N of ~M"
//      • .end            → "End of list"
//      • .offline(n, age) → "Offline — N cached, last synced Xh ago"
//
//   3. `View.onNearBottom(_:threshold:)` — modifier that fires `action` when
//      the GeometryReader-based scroll percentage crosses `threshold` (default
//      80 %, matching the §29.4 "prefetch at 80% scroll" rule).
//
// All types are intentionally free of any import beyond SwiftUI so they can
// be used from any feature package that imports Core.

// MARK: - LoadMoreTrigger (§29.4)

/// An invisible `Color.clear` view that calls `onTrigger` the first time it
/// appears on screen.  Place it as the last item in a `List` or `LazyVStack`.
///
/// ```swift
/// List {
///     ForEach(items) { … }
///     LoadMoreTrigger(onTrigger: { viewModel.loadNextPage() })
/// }
/// ```
public struct LoadMoreTrigger: View {

    public let onTrigger: () -> Void

    public init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    public var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear { onTrigger() }
            .accessibilityHidden(true)
    }
}

// MARK: - ListLoadMoreFooter (§29.4)

/// The four pagination states a list footer can be in, per §29.4.
public enum ListPaginationState: Equatable, Sendable {
    /// A page fetch is in progress.
    case loading
    /// More pages exist.  `shown` = rows in cache; `total` = server estimate.
    case partial(shown: Int, total: Int)
    /// All server rows have been fetched.
    case end
    /// Device is offline.  `cached` = rows available locally;
    /// `lastSyncedAgo` = human-readable age string (e.g. "2h ago").
    case offline(cached: Int, lastSyncedAgo: String)
}

/// A standard list footer that renders the current ``ListPaginationState``.
///
/// Never shows an ambiguous blank — every state has a description per §29.4.
///
/// ```swift
/// List {
///     ForEach(rows) { … }
///     ListLoadMoreFooter(state: viewModel.paginationState)
/// }
/// ```
public struct ListLoadMoreFooter: View {

    public let state: ListPaginationState

    public init(state: ListPaginationState) {
        self.state = state
    }

    public var body: some View {
        Group {
            switch state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }

            case let .partial(shown, total):
                Text("Showing \(shown) of ~\(total)")
                    .foregroundStyle(.secondary)

            case .end:
                Text("End of list")
                    .foregroundStyle(.tertiary)

            case let .offline(cached, age):
                Label(
                    "Offline — \(cached) cached, last synced \(age)",
                    systemImage: "wifi.slash"
                )
                .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - onNearBottom modifier (§29.4 prefetch at 80%)

private struct NearBottomModifier: ViewModifier {

    let threshold: Double   // 0.0 … 1.0; default 0.80
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: proxy.frame(in: .global).maxY
                )
            }
        )
        .onPreferenceChange(ScrollOffsetKey.self) { maxY in
            // `maxY` is the bottom edge of the content in global coords.
            // When it is at or above `threshold * screenHeight` the user has
            // scrolled past the threshold fraction of the list.
            let screenHeight = UIScreen.main.bounds.height
            if maxY <= screenHeight * (1.0 - threshold) {
                action()
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public extension View {
    /// Fires `action` once when the bottom of this view is within
    /// `threshold` (default `0.80`) of the visible scroll area.
    ///
    /// Use on the **last visible row** to trigger prefetch at 80% scroll
    /// per §29.4.
    ///
    /// ```swift
    /// ForEach(rows.indices, id: \.self) { i in
    ///     RowView(row: rows[i])
    ///         .onNearBottom(threshold: 0.8) {
    ///             if i == rows.index(before: rows.endIndex) {
    ///                 viewModel.loadNextPage()
    ///             }
    ///         }
    /// }
    /// ```
    func onNearBottom(threshold: Double = 0.80, perform action: @escaping () -> Void) -> some View {
        modifier(NearBottomModifier(threshold: threshold, action: action))
    }
}
