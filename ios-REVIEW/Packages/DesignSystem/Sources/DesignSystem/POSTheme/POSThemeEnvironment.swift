import SwiftUI

// MARK: - Environment key

private struct POSThemeKey: EnvironmentKey {
    /// Default value is `.dark` (the app launches in dark-first POS mode).
    static let defaultValue: POSThemeTokens = .dark
}

// MARK: - EnvironmentValues extension

public extension EnvironmentValues {

    /// The active POS colour-token set.
    ///
    /// Inject via `.posTheme(override:)` on the root view.
    /// Read via `@Environment(\.posTheme) private var theme`.
    var posTheme: POSThemeTokens {
        get { self[POSThemeKey.self] }
        set { self[POSThemeKey.self] = newValue }
    }
}
