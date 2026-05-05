import SwiftUI

// §30.12 Theme choice — user-selectable via Setup Wizard step + Settings → Appearance.
//
// Design decisions:
// - Default = `.system` so the app never fights iOS auto dark/light.
// - Per-tenant storage: key includes tenant slug so sandbox vs prod can differ.
// - Kiosk / CFD modes override this externally; see §16.
// - Never expose a "Force Reduce Motion / Reduce Transparency" equivalent
//   for theme — that would duplicate iOS system settings.

// MARK: - AppTheme

/// User-selectable color scheme preference.
public enum AppTheme: String, CaseIterable, Sendable, Identifiable {
    /// Follow the iOS system dark/light mode toggle. Recommended default.
    case system
    /// Always dark (OLED-friendly surface `bizarreSurfaceBase`).
    case dark
    /// Always light (paper-feel surface for counter-bright environments).
    case light

    public var id: String { rawValue }

    /// Human-readable label for Settings → Appearance → Theme picker.
    public var label: String {
        switch self {
        case .system: return "System (recommended)"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }

    /// The `ColorScheme?` SwiftUI value to pass to `.preferredColorScheme`.
    /// `nil` means "follow system" — SwiftUI's default behaviour.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}

// MARK: - ThemeStore

/// Persists the per-tenant theme preference in `UserDefaults`.
///
/// Key convention: `theme.<tenantSlug>` so switching tenants restores the
/// preference for that tenant.  Falls back to `.system` when no key exists.
///
/// Usage:
/// ```swift
/// let store = ThemeStore()
/// store.set(.dark, for: "acme-repair")
/// let theme = store.theme(for: "acme-repair")   // → .dark
/// ```
public struct ThemeStore: Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for tenantSlug: String) -> String {
        "theme.\(tenantSlug)"
    }

    public func theme(for tenantSlug: String) -> AppTheme {
        guard let raw = defaults.string(forKey: key(for: tenantSlug)),
              let theme = AppTheme(rawValue: raw) else {
            return .system
        }
        return theme
    }

    public func set(_ theme: AppTheme, for tenantSlug: String) {
        defaults.set(theme.rawValue, forKey: key(for: tenantSlug))
    }

    /// Remove the stored preference (resets to `.system` on next read).
    public func remove(for tenantSlug: String) {
        defaults.removeObject(forKey: key(for: tenantSlug))
    }
}

// MARK: - View extension

public extension View {
    /// Apply the stored theme as a preferred color scheme.
    ///
    /// Attach at the root of the view hierarchy (RootView).
    ///
    /// ```swift
    /// ContentView()
    ///     .themedColorScheme(ThemeStore().theme(for: tenantSlug))
    /// ```
    func themedColorScheme(_ theme: AppTheme) -> some View {
        self.preferredColorScheme(theme.colorScheme)
    }
}
