// DesignSystem/RTL/RTLHelpers.swift
//
// Utilities for right-to-left layout support.  §27 RTL rules.
//
// Rules (per agent-ownership.md §27):
//   - Use logical properties (leading/trailing) everywhere; never .left / .right.
//   - Directional SF Symbols (arrows, chevrons) receive .imageFlipsForRightToLeft via
//     Image(systemName:).imageScale(.large).environment(\.layoutDirection, ...).
//   - Non-directional symbols (clock, info) must NOT flip.
//   - All custom views must branch on RTLHelpers.isRTL when legacy frame math is unavoidable.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Namespace for RTL-aware layout utilities.
public enum RTLHelpers: Sendable {

    // MARK: - Layout direction detection

    /// True when the current effective layout direction is right-to-left.
    ///
    /// Prefer SwiftUI's `.environment(\.layoutDirection)` in views.
    /// Use this helper for imperative / UIKit code paths.
    @MainActor
    public static var isRTL: Bool {
#if canImport(UIKit)
        UIView.userInterfaceLayoutDirection(for: .unspecified) == .rightToLeft
#else
        false
#endif
    }

    // MARK: - Edge helpers

    /// Returns the logical leading edge set for the given SwiftUI `LayoutDirection`.
    ///
    /// Usage:
    /// ```swift
    /// @Environment(\.layoutDirection) var dir
    /// .padding(RTLHelpers.leadingEdge(for: dir))
    /// ```
    public static func leadingEdge(for direction: LayoutDirection) -> Edge.Set {
        direction == .rightToLeft ? .trailing : .leading
    }

    /// Returns the logical trailing edge set for the given SwiftUI `LayoutDirection`.
    public static func trailingEdge(for direction: LayoutDirection) -> Edge.Set {
        direction == .rightToLeft ? .leading : .trailing
    }

    // MARK: - Horizontal alignment

    /// Returns `.leading` in LTR, `.trailing` in RTL — for use with `HStack` alignment
    /// or `.frame(alignment:)` when the content must always hug the logical start.
    public static func leadingAlignment(for direction: LayoutDirection) -> HorizontalAlignment {
        direction == .rightToLeft ? .trailing : .leading
    }

    /// Returns `.trailing` in LTR, `.leading` in RTL.
    public static func trailingAlignment(for direction: LayoutDirection) -> HorizontalAlignment {
        direction == .rightToLeft ? .leading : .trailing
    }

    // MARK: - Directional SF Symbols

    /// Wraps a directional SF Symbol image so it automatically mirrors in RTL.
    ///
    /// Usage:
    /// ```swift
    /// RTLHelpers.directionalImage("arrow.right")
    ///     .accessibilityLabel("Next")
    /// ```
    public static func directionalImage(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .imageScale(.large)
            // SwiftUI flips images with this modifier in RTL automatically.
            .flipsForRightToLeftLayoutDirection(true)
    }

    /// Non-directional SF Symbol — never flips.
    public static func staticImage(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .imageScale(.large)
    }

    // MARK: - Text alignment

    /// Returns `.leading` alignment in both directions — this is the correct
    /// default for body text (SwiftUI handles bidi automatically).
    public static var bodyTextAlignment: TextAlignment { .leading }
}

// MARK: - View modifier convenience

extension View {

    /// Applies a padding to the logical leading side (start-of-text side).
    public func leadingPadding(_ amount: CGFloat, direction: LayoutDirection) -> some View {
        self.padding(RTLHelpers.leadingEdge(for: direction), amount)
    }

    /// Applies a padding to the logical trailing side.
    public func trailingPadding(_ amount: CGFloat, direction: LayoutDirection) -> some View {
        self.padding(RTLHelpers.trailingEdge(for: direction), amount)
    }
}
