// DesignSystem/RTL/RTLPreviewModifier.swift
//
// SwiftUI preview modifier that forces right-to-left layout for RTL regression testing.
// §27 RTL layout rules.
//
// Usage in Previews:
//   #Preview("RTL") {
//       MyView()
//           .rtlPreview()
//   }

import SwiftUI

// MARK: - Modifier

/// Forces the SwiftUI environment into right-to-left layout direction.
/// Use exclusively in `#Preview` / `PreviewProvider` targets — never in production code.
public struct RTLPreviewModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
    }
}

// MARK: - View extension

extension View {

    /// Wraps the view in a right-to-left layout environment for preview testing.
    ///
    /// Validates:
    /// - Logical edge usage (leading/trailing, not left/right)
    /// - Directional icon mirroring
    /// - Text alignment in RTL context
    /// - No visual clipping or truncation from expansion
    ///
    /// Example:
    /// ```swift
    /// #Preview("Dashboard RTL") {
    ///     DashboardView()
    ///         .rtlPreview()
    /// }
    /// ```
    public func rtlPreview() -> some View {
        modifier(RTLPreviewModifier())
    }

    /// Renders side-by-side LTR + RTL previews in a `VStack`.
    /// Useful for snapshot tests that must cover both directions.
    public func bothDirectionsPreviews(spacing: CGFloat = 16) -> some View {
        VStack(spacing: spacing) {
            self
                .environment(\.layoutDirection, .leftToRight)

            Divider()
                .overlay(Text("RTL ↓").font(.caption).foregroundStyle(.secondary))

            self
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }
}
