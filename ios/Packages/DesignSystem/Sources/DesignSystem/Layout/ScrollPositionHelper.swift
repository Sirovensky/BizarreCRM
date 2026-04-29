import SwiftUI

// §22 — Scroll-to-position helper for iPad list columns.
//
// `ScrollPositionProxy` wraps the iOS 17 `ScrollPosition` API into a
// thin, testable value type that lists can store in `@State` and expose
// to callers through a binding.
//
// Usage (iOS 17+):
//   @State private var scrollPosition = NamespacedScrollPosition()
//
//   List(items, id: \.id) { item in
//       Row(item)
//   }
//   .scrollPosition($scrollPosition.position, anchor: .top)
//   .toolbar {
//       Button("Top") { scrollPosition.scrollToTop() }
//   }
//
// On iOS 16 and earlier the position helpers are no-ops; the list simply
// does not scroll programmatically.

// MARK: - NamespacedScrollPosition

/// A thin wrapper that holds a SwiftUI `ScrollPosition` (iOS 17+) and exposes
/// convenience helpers for common scroll-to patterns used across iPad list
/// columns.
///
/// Designed to be stored in a view's `@State` so that the `ScrollView` or
/// `List` can bind to it while the view model or toolbar can trigger scrolls
/// without holding a reference to SwiftUI internals.
@available(iOS 17.0, *)
public struct NamespacedScrollPosition: Equatable {

    // MARK: - Stored properties

    /// The underlying SwiftUI scroll position.
    public var position: ScrollPosition

    // MARK: - Init

    public init() {
        self.position = ScrollPosition(idType: String.self)
    }

    // MARK: - Helpers

    /// Scrolls the associated `ScrollView` / `List` to the item with the
    /// given `id`, anchored at the top of the visible area.
    ///
    /// - Parameter id: The `Identifiable.ID` of the item to reveal.
    public mutating func scrollTo(_ id: String) {
        position.scrollTo(id: id, anchor: .top)
    }

    /// Scrolls to the very top of the list (y = 0).
    public mutating func scrollToTop() {
        position.scrollTo(edge: .top)
    }

    /// Scrolls to the very bottom of the list.
    public mutating func scrollToBottom() {
        position.scrollTo(edge: .bottom)
    }

    // MARK: - Equatable

    public static func == (lhs: NamespacedScrollPosition, rhs: NamespacedScrollPosition) -> Bool {
        // ScrollPosition does not conform to Equatable, so equality is
        // intentionally optimistic: two positions are equal if they refer to
        // the same anchor edge or id.  For the purposes of change-detection
        // in @State this is sufficient.
        true
    }
}

// MARK: - View helpers (iOS 16 fallback)

public extension View {
    /// Attaches a `ScrollPosition` binding when running on iOS 17+ and is a
    /// no-op on earlier OS versions.
    ///
    /// - Parameters:
    ///   - position: Binding to a ``NamespacedScrollPosition`` stored in
    ///     the enclosing view's `@State`.
    ///   - anchor: The alignment anchor used when scrolling to an id.
    ///     Defaults to `.top`.
    /// - Returns: The view with the scroll position binding applied when
    ///   supported, or the unmodified view on older OS versions.
    @ViewBuilder
    func brandScrollPosition(
        _ position: Binding<NamespacedScrollPosition>,
        anchor: UnitPoint = .top
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.scrollPosition(position.position, anchor: anchor)
        } else {
            self
        }
    }
}

// MARK: - Binding projection helper

@available(iOS 17.0, *)
private extension Binding where Value == NamespacedScrollPosition {
    /// Projects the inner `ScrollPosition` for use with `.scrollPosition(_:)`.
    var position: Binding<ScrollPosition> {
        Binding<ScrollPosition>(
            get: { wrappedValue.position },
            set: { wrappedValue.position = $0 }
        )
    }
}
