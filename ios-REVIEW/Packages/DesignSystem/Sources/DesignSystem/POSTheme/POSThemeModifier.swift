import SwiftUI

// MARK: - Override enum

/// Explicit theme override that the user can store in `@AppStorage`.
///
/// - `system`: Follow the device `ColorScheme` (`.dark` → dark tokens,
///   `.light` → light tokens). This is the default when no override is stored.
/// - `light`: Always apply light tokens regardless of device appearance.
/// - `dark`: Always apply dark tokens regardless of device appearance.
public enum POSThemeOverride: String, Sendable, CaseIterable {
    case system
    case light
    case dark
}

// MARK: - Modifier

/// Resolves the active `POSThemeTokens` and injects them into the
/// SwiftUI environment.
///
/// **Precedence** (highest → lowest):
/// 1. The `override` parameter passed directly to `.posTheme(override:)`.
/// 2. `@AppStorage("pos.theme.override")` — persisted user preference.
/// 3. `@Environment(\.colorScheme)` — system appearance.
///
/// Usage:
/// ```swift
/// WindowGroup { RootView() }
///     .posTheme()              // system default
/// WindowGroup { RootView() }
///     .posTheme(override: .dark)  // forced dark
/// ```
public struct POSThemeModifier: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pos.theme.override") private var storedOverride: String = POSThemeOverride.system.rawValue

    /// Call-site override — takes precedence over AppStorage.
    private let callSiteOverride: POSThemeOverride?

    public init(override: POSThemeOverride? = nil) {
        self.callSiteOverride = override
    }

    public func body(content: Content) -> some View {
        content.environment(\.posTheme, resolvedTokens)
    }

    // MARK: - Resolution

    private var resolvedTokens: POSThemeTokens {
        let effective = effectiveOverride
        switch effective {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return colorScheme == .dark ? .dark : .light
        }
    }

    private var effectiveOverride: POSThemeOverride {
        // 1. Call-site wins.
        if let callSiteOverride {
            return callSiteOverride
        }
        // 2. Persisted user preference (ignores unknown raw values → falls through).
        if let persisted = POSThemeOverride(rawValue: storedOverride) {
            return persisted
        }
        // 3. System default.
        return .system
    }
}

// MARK: - View convenience

public extension View {

    /// Injects the resolved `POSThemeTokens` into the environment.
    ///
    /// - Parameter override: Optional explicit override. When `nil` the
    ///   modifier checks `@AppStorage("pos.theme.override")` and then
    ///   falls through to the device `ColorScheme`.
    func posTheme(override: POSThemeOverride? = nil) -> some View {
        modifier(POSThemeModifier(override: override))
    }
}
