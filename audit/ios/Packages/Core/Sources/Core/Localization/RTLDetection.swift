// Core/Localization/RTLDetection.swift
//
// §27 i18n groundwork — RTL layout direction detection + SwiftUI environment key.
//
// Usage (SwiftUI):
//   @Environment(\.layoutDirection) var dir
//   // or inject our custom key:
//   @Environment(\.rtlEnabled) var isRTL
//
//   // Override for a subtree (e.g. a preview):
//   MyView()
//       .environment(\.rtlEnabled, true)
//
// Usage (programmatic):
//   if RTLDetection.isRTL(locale: Locale(identifier: "ar_SA")) { ... }
//   if RTLDetection.isRTL(languageCode: "he") { ... }

import Foundation
import SwiftUI

// MARK: - RTLDetection

/// Pure utility that wraps `NSLocale.characterDirection(forLanguage:)`.
///
/// Sendable / enum-based so it produces no instances and has no mutable state.
public enum RTLDetection {

    // MARK: Core detection

    /// Returns `true` when the language associated with `locale` is written
    /// right-to-left (Arabic, Hebrew, Persian, Urdu, etc.).
    public static func isRTL(locale: Locale) -> Bool {
        let language = languageCode(from: locale)
        return isRTL(languageCode: language)
    }

    /// Returns `true` when `languageCode` is a known RTL language.
    ///
    /// Delegates to `NSLocale.characterDirection(forLanguage:)` which covers the
    /// full Unicode CLDR language list.
    public static func isRTL(languageCode: String) -> Bool {
        let direction = NSLocale.characterDirection(forLanguage: languageCode)
        return direction == .rightToLeft
    }

    /// Converts the detection result to a SwiftUI `LayoutDirection`.
    public static func layoutDirection(for locale: Locale) -> LayoutDirection {
        isRTL(locale: locale) ? .rightToLeft : .leftToRight
    }

    /// Converts the detection result to a SwiftUI `LayoutDirection` for a language code.
    public static func layoutDirection(forLanguageCode code: String) -> LayoutDirection {
        isRTL(languageCode: code) ? .rightToLeft : .leftToRight
    }

    // MARK: Current device locale

    /// Returns `true` when the *current device locale* is RTL.
    public static var currentLocaleIsRTL: Bool {
        isRTL(locale: Locale.current)
    }

    // MARK: Helpers

    /// Extracts the ISO 639-1 / 639-2 language code from a `Locale`.
    ///
    /// On iOS 16+ uses `Locale.Language.languageCode`; falls back to the
    /// pre-iOS 16 `languageCode` property for iOS 17 floor compatibility
    /// (the newer API is available from iOS 16 but we keep the fallback for
    /// simulation on macOS 14 where the availability guard may differ).
    private static func languageCode(from locale: Locale) -> String {
        if #available(iOS 16, macOS 13, *) {
            return locale.language.languageCode?.identifier ?? ""
        } else {
            return locale.languageCode ?? ""
        }
    }
}

// MARK: - SwiftUI Environment Key

/// Custom SwiftUI environment key that carries an explicit RTL flag.
///
/// Use this when you need a Bool rather than the full `LayoutDirection` enum,
/// or when you want to override the inferred direction for a specific subtree
/// (e.g. to force LTR for code blocks inside an otherwise RTL view).
public struct RTLEnabledKey: EnvironmentKey {
    public static let defaultValue: Bool = RTLDetection.currentLocaleIsRTL
}

public extension EnvironmentValues {
    /// Whether the current layout context is right-to-left.
    ///
    /// Injected automatically from `RTLDetection.currentLocaleIsRTL` by default.
    /// Override with `.environment(\.rtlEnabled, true/false)`.
    var rtlEnabled: Bool {
        get { self[RTLEnabledKey.self] }
        set { self[RTLEnabledKey.self] = newValue }
    }
}

// MARK: - View modifier convenience

public extension View {
    /// Applies the correct `LayoutDirection` to this view based on `locale`.
    ///
    /// ```swift
    /// TextField("", text: $text)
    ///     .rtlLayout(for: Locale(identifier: "ar_SA"))
    /// ```
    func rtlLayout(for locale: Locale) -> some View {
        let dir = RTLDetection.layoutDirection(for: locale)
        return self
            .environment(\.layoutDirection, dir)
            .environment(\.rtlEnabled, dir == .rightToLeft)
    }
}
