// Core/Localization/PseudoLocaleGenerator.swift
//
// §27 i18n groundwork — dev-only pseudo-locale helper.
//
// Wraps every translated string in a visually distinctive wrapper so that:
//   1. Truncation / layout bugs become obvious immediately.
//   2. Untranslated hard-coded strings stand out (they keep their original form).
//   3. Expansion headroom can be measured programmatically.
//
// Usage:
//   let wrapped = PseudoLocaleGenerator.wrap("Save")
//   // → "[¡Śàvé!]"
//
//   let ratio = PseudoLocaleGenerator.expansionRatio(for: "Save")
//   // → 1.5 (or higher)
//
// Enabled only in DEBUG builds.  In Release builds every method is a no-op
// that returns the original string unchanged, so there is zero production
// overhead and no risk of shipping pseudo strings.

import Foundation

// MARK: - PseudoLocaleGenerator

/// Dev-only helper that wraps strings with diacritics and brackets to surface
/// i18n issues during development.
public enum PseudoLocaleGenerator {

    // MARK: Configuration

    /// Prefix appended before the transformed content.
    public static let prefix = "[¡"
    /// Suffix appended after the transformed content.
    public static let suffix = "!]"

    // MARK: - Core transformation

    /// Wraps `string` in the pseudo-locale markers and replaces ASCII characters
    /// with accented equivalents so that:
    ///   - Layout bugs (truncation) are visible.
    ///   - Untranslated strings are easy to spot at a glance.
    ///
    /// In Release builds this is a no-op and returns `string` unchanged.
    public static func wrap(_ string: String) -> String {
#if DEBUG
        let accented = string.map { pseudoChar($0) }.joined()
        return "\(prefix)\(accented)\(suffix)"
#else
        return string
#endif
    }

    /// Returns the expansion ratio of the wrapped string relative to the original.
    ///
    /// Useful in unit tests to confirm that wrapped strings expand enough to
    /// surface truncation bugs (typically ≥ 1.3×).
    ///
    /// In Release builds returns 1.0 (no expansion).
    public static func expansionRatio(for string: String) -> Double {
#if DEBUG
        guard !string.isEmpty else { return 1.0 }
        let wrapped = wrap(string)
        return Double(wrapped.count) / Double(string.count)
#else
        return 1.0
#endif
    }

    // MARK: - Batch transformation

    /// Wraps every value in a `[String: String]` dictionary (e.g. a parsed
    /// `.strings` file) and returns a new dictionary with the same keys.
    ///
    /// In Release builds returns `dictionary` unchanged.
    public static func wrap(dictionary: [String: String]) -> [String: String] {
#if DEBUG
        return dictionary.mapValues { wrap($0) }
#else
        return dictionary
#endif
    }

    // MARK: - Character mapping (DEBUG only)

#if DEBUG
    /// Maps an ASCII character to a Unicode lookalike with diacritics.
    /// Non-ASCII characters (already accented, CJK, Arabic, etc.) are returned as-is.
    private static func pseudoChar(_ char: Character) -> String {
        switch char {
        case "a": return "à"
        case "b": return "ƀ"
        case "c": return "ć"
        case "d": return "ď"
        case "e": return "é"
        case "f": return "ƒ"
        case "g": return "ĝ"
        case "h": return "ĥ"
        case "i": return "î"
        case "j": return "ĵ"
        case "k": return "ķ"
        case "l": return "ĺ"
        case "m": return "m̈"
        case "n": return "ñ"
        case "o": return "ô"
        case "p": return "p̈"
        case "q": return "q̈"
        case "r": return "ŕ"
        case "s": return "ś"
        case "t": return "ţ"
        case "u": return "û"
        case "v": return "v̈"
        case "w": return "ŵ"
        case "x": return "x̂"
        case "y": return "ŷ"
        case "z": return "ź"
        case "A": return "À"
        case "B": return "Ɓ"
        case "C": return "Ć"
        case "D": return "Ď"
        case "E": return "É"
        case "F": return "Ƒ"
        case "G": return "Ĝ"
        case "H": return "Ĥ"
        case "I": return "Î"
        case "J": return "Ĵ"
        case "K": return "Ķ"
        case "L": return "Ĺ"
        case "M": return "M̈"
        case "N": return "Ñ"
        case "O": return "Ô"
        case "P": return "P̈"
        case "Q": return "Q̈"
        case "R": return "Ŕ"
        case "S": return "Ś"
        case "T": return "Ţ"
        case "U": return "Û"
        case "V": return "V̈"
        case "W": return "Ŵ"
        case "X": return "X̂"
        case "Y": return "Ŷ"
        case "Z": return "Ź"
        default:  return String(char)
        }
    }
#endif
}
