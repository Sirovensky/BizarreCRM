import SwiftUI

// MARK: - Cross-platform View helpers

internal extension View {
    /// Applies `.navigationBarTitleDisplayMode(.inline)` on iOS only.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
