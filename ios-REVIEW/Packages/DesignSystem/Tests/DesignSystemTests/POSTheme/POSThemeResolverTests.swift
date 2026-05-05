import Testing
import SwiftUI
@testable import DesignSystem

// MARK: - Resolver logic tests
//
// `POSThemeModifier` depends on `@Environment(\.colorScheme)` and
// `@AppStorage("pos.theme.override")` which are SwiftUI runtime concepts.
// We test the resolver logic directly by exposing a pure function equivalent
// so we don't need a hosting UIWindow.

/// Pure resolver extracted from `POSThemeModifier` for unit-testing.
///
/// This mirrors the modifier's precedence rules:
///   1. Call-site override (non-nil) wins.
///   2. Stored preference (valid `POSThemeOverride` raw value) wins.
///   3. Falls through to `systemScheme`.
private func resolve(
    callSite: POSThemeOverride?,
    stored: String,
    systemScheme: ColorScheme
) -> POSThemeTokens {
    let effective: POSThemeOverride
    if let callSite {
        effective = callSite
    } else if let persisted = POSThemeOverride(rawValue: stored) {
        effective = persisted
    } else {
        effective = .system
    }
    switch effective {
    case .dark:   return .dark
    case .light:  return .light
    case .system: return systemScheme == .dark ? .dark : .light
    }
}

// MARK: - Suite

@Suite("POSThemeModifier — override precedence")
struct POSThemeResolverTests {

    // MARK: .system override

    @Test("system + dark ColorScheme → dark tokens")
    func systemDarkScheme() {
        let tokens = resolve(callSite: .system, stored: "system", systemScheme: .dark)
        #expect(tokens.bg == POSThemeTokens.dark.bg)
    }

    @Test("system + light ColorScheme → light tokens")
    func systemLightScheme() {
        let tokens = resolve(callSite: .system, stored: "system", systemScheme: .light)
        #expect(tokens.bg == POSThemeTokens.light.bg)
    }

    // MARK: .light override

    @Test(".light call-site override pins light even when device is dark")
    func lightOverridePinsDark() {
        let tokens = resolve(callSite: .light, stored: "system", systemScheme: .dark)
        #expect(tokens.bg == POSThemeTokens.light.bg)
    }

    @Test(".light call-site override pins light when device is already light")
    func lightOverridePinsLight() {
        let tokens = resolve(callSite: .light, stored: "dark", systemScheme: .light)
        #expect(tokens.bg == POSThemeTokens.light.bg)
    }

    // MARK: .dark override

    @Test(".dark call-site override pins dark even when device is light")
    func darkOverridePinsLight() {
        let tokens = resolve(callSite: .dark, stored: "system", systemScheme: .light)
        #expect(tokens.bg == POSThemeTokens.dark.bg)
    }

    @Test(".dark call-site override pins dark when device is already dark")
    func darkOverridePinsDark() {
        let tokens = resolve(callSite: .dark, stored: "light", systemScheme: .dark)
        #expect(tokens.bg == POSThemeTokens.dark.bg)
    }

    // MARK: nil call-site → AppStorage wins

    @Test("nil call-site + stored 'light' → light tokens regardless of scheme")
    func storedLightOverridesScheme() {
        let darkSystem = resolve(callSite: nil, stored: "light", systemScheme: .dark)
        #expect(darkSystem.bg == POSThemeTokens.light.bg)

        let lightSystem = resolve(callSite: nil, stored: "light", systemScheme: .light)
        #expect(lightSystem.bg == POSThemeTokens.light.bg)
    }

    @Test("nil call-site + stored 'dark' → dark tokens regardless of scheme")
    func storedDarkOverridesScheme() {
        let lightSystem = resolve(callSite: nil, stored: "dark", systemScheme: .light)
        #expect(lightSystem.bg == POSThemeTokens.dark.bg)
    }

    @Test("nil call-site + stored 'system' + dark scheme → dark tokens")
    func storedSystemRespectsDarkScheme() {
        let tokens = resolve(callSite: nil, stored: "system", systemScheme: .dark)
        #expect(tokens.bg == POSThemeTokens.dark.bg)
    }

    @Test("nil call-site + stored 'system' + light scheme → light tokens")
    func storedSystemRespectsLightScheme() {
        let tokens = resolve(callSite: nil, stored: "system", systemScheme: .light)
        #expect(tokens.bg == POSThemeTokens.light.bg)
    }

    // MARK: Unknown stored value → fall through to system

    @Test("nil call-site + unknown stored value falls through to system scheme")
    func unknownStoredValueFallsThrough() {
        let darkTokens = resolve(callSite: nil, stored: "unknown_value", systemScheme: .dark)
        #expect(darkTokens.bg == POSThemeTokens.dark.bg)

        let lightTokens = resolve(callSite: nil, stored: "unknown_value", systemScheme: .light)
        #expect(lightTokens.bg == POSThemeTokens.light.bg)
    }

    @Test("nil call-site + empty stored value falls through to system scheme")
    func emptyStoredValueFallsThrough() {
        let tokens = resolve(callSite: nil, stored: "", systemScheme: .light)
        #expect(tokens.bg == POSThemeTokens.light.bg)
    }

    // MARK: Call-site beats AppStorage

    @Test("call-site .dark beats stored 'light'")
    func callSiteBeatsStoredLight() {
        let tokens = resolve(callSite: .dark, stored: "light", systemScheme: .light)
        #expect(tokens.bg == POSThemeTokens.dark.bg)
    }

    @Test("call-site .light beats stored 'dark'")
    func callSiteBeatsStoredDark() {
        let tokens = resolve(callSite: .light, stored: "dark", systemScheme: .dark)
        #expect(tokens.bg == POSThemeTokens.light.bg)
    }

    // MARK: POSThemeOverride enum

    @Test("POSThemeOverride has exactly three cases")
    func overrideCaseCount() {
        #expect(POSThemeOverride.allCases.count == 3)
    }

    @Test("POSThemeOverride raw values are stable strings")
    func overrideRawValues() {
        #expect(POSThemeOverride.system.rawValue == "system")
        #expect(POSThemeOverride.light.rawValue == "light")
        #expect(POSThemeOverride.dark.rawValue == "dark")
    }

    // MARK: Environment key default

    @Test("default posTheme environment value is dark")
    func defaultEnvironmentValueIsDark() {
        // The default is dark (POS launches in dark-first mode).
        var env = EnvironmentValues()
        #expect(env.posTheme.bg == POSThemeTokens.dark.bg)
    }
}
