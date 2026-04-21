import SwiftUI

// MARK: - Cross-platform View helpers

extension View {
    /// Applies `.navigationBarTitleDisplayMode(.inline)` on iOS only.
    @ViewBuilder
    func exportInlineTitleMode() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Applies `.toolbarBackground(style, for: .navigationBar)` on iOS only;
    /// on macOS `navigationBar` doesn't exist.
    @ViewBuilder
    func exportToolbarBackground() -> some View {
        #if os(iOS)
        self.toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Applies `.listStyle(.insetGrouped)` on iOS, falls back to `.inset` on macOS.
    @ViewBuilder
    func exportListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}
