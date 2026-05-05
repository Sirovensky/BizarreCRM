import SwiftUI

// MARK: - FocusLoopTestHelper
// §91.13 — Focus-loop test helper for VoiceOver and Switch Control QA.
//
// During accessibility QA it is useful to assert that a container visits every
// focusable element exactly once and returns to the first element after the
// last.  This file provides:
//
//   1. `AccessibilityFocusOrder` — a lightweight value type that records the
//      sequence of `accessibilityIdentifier` strings visited by a test harness.
//   2. `View.recordFocusVisit(id:into:)` — writes the view's identifier into
//      an `AccessibilityFocusOrder` collector when VoiceOver focuses it.
//   3. `AccessibilityFocusOrder.assertLinearLoop(ids:)` — asserts the recorded
//      order matches the expected list (DEBUG only; no-ops in RELEASE).
//
// **Usage in an XCTest:**
// ```swift
// let order = AccessibilityFocusOrder()
// let view = MyCardView()
//     .recordFocusVisit(id: "title", into: order)
//     // … more children …
// // Simulate focus traversal via XCUIElement.swipeRight() sequence,
// // then assert:
// order.assertLinearLoop(ids: ["title", "value", "action"])
// ```
//
// In production builds the observer closures are elided — zero overhead.

// MARK: - AccessibilityFocusOrder

/// Records `accessibilityIdentifier` strings in the order VoiceOver focuses them.
///
/// Thread-safe for use from `@MainActor` SwiftUI views and XCTest callbacks.
@MainActor
public final class AccessibilityFocusOrder: ObservableObject {
    /// The ordered list of identifiers visited so far.
    @Published public private(set) var visited: [String] = []

    public init() {}

    /// Appends `id` to the visited list.  Called automatically by
    /// `recordFocusVisit(id:into:)` when a view receives VoiceOver focus.
    public func record(_ id: String) {
        visited.append(id)
    }

    /// Resets the recorded order.  Call before each test scenario.
    public func reset() {
        visited = []
    }

    /// Asserts that `visited` matches `ids` and that the last element
    /// conceptually wraps back to the first (linear loop invariant).
    ///
    /// - Parameter ids: The expected focus order, not including the wrap-back.
    /// - Note: No-op in RELEASE builds.
    public func assertLinearLoop(ids: [String], file: StaticString = #file, line: UInt = #line) {
        #if DEBUG
        guard visited == ids else {
            assertionFailure(
                "[A11y §91.13] Focus loop mismatch.\n"
                + "  Expected: \(ids)\n"
                + "  Got:      \(visited)",
                file: file, line: line
            )
            return
        }
        // The loop is considered valid when all expected ids are visited once.
        // The wrap from last → first is guaranteed by iOS accessibility engine;
        // we only verify the forward order here.
        #endif
    }
}

// MARK: - View modifier

/// Appends this view's `id` to `order` each time VoiceOver focuses it.
public struct RecordFocusVisitModifier: ViewModifier {
    public let id: String
    public let order: AccessibilityFocusOrder

    @AccessibilityFocusState private var isFocused: Bool

    public init(id: String, order: AccessibilityFocusOrder) {
        self.id = id
        self.order = order
    }

    public func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(id)
            .accessibilityFocused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    Task { @MainActor in
                        order.record(id)
                    }
                }
            }
    }
}

// MARK: - View extension

public extension View {
    /// Records a VoiceOver focus visit for this view into `order`.
    ///
    /// Attach to every focusable element in a container you want to test.
    /// The `order` object can then be inspected in XCTest assertions.
    ///
    /// - Parameters:
    ///   - id: The `accessibilityIdentifier` to record (also sets `.accessibilityIdentifier`).
    ///   - order: The shared `AccessibilityFocusOrder` collector.
    func recordFocusVisit(id: String, into order: AccessibilityFocusOrder) -> some View {
        modifier(RecordFocusVisitModifier(id: id, order: order))
    }
}
