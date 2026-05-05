import Foundation

// §64 — Plain-Swift tone validator for UI copy strings.
//
// Design notes:
//  - Active only in DEBUG builds via `assert` — zero overhead in release.
//  - Call `ToneGuidelines.assertTone(_:context:)` when constructing UI strings
//    from dynamic data (e.g. server messages shown as-is, not from this catalog).
//  - Catalog strings (ErrorCopy, EmptyStateCopy, etc.) are pre-validated at
//    file creation time; they do not need runtime checks.
//  - Violations are listed in `ToneViolation` for testability and documentation.
//  - Pure enum — no stored state, no side effects.

/// Documents and enforces the BizarreCRM copy tone guidelines.
///
/// ## Rules
/// - No ALL CAPS words (shouting at the user).
/// - No exclamation marks (pushy, not calm).
/// - No filler apologies: "please", "sorry", "we apologize".
/// - No technical jargon as lead words: "error:", "exception:", "failed:".
/// - No passive "there was a problem" hedging as the entire message.
/// - No trailing ellipsis in titles/labels (signals incompleteness).
///
/// ## Usage
/// ```swift
/// // In DEBUG builds only — release builds are no-ops.
/// ToneGuidelines.assertTone(serverMessage, context: "Server banner body")
/// ```
public enum ToneGuidelines {

    // MARK: — Violation types

    /// A specific tone rule that was violated.
    public enum ToneViolation: Sendable, Equatable, CaseIterable {
        /// One or more words are written entirely in uppercase letters (e.g. "ERROR").
        case allCapsWord
        /// The string contains an exclamation mark.
        case exclamationMark
        /// The string contains an unnecessary filler apology word.
        case fillerApology
        /// The string starts with a technical jargon lead word such as "Error:" or "Exception:".
        case technicalJargonLead
        /// The entire string is a vague passive hedge with no actionable detail.
        case passiveHedge
        /// A title or short label ends with "…" (U+2026) or "..." (three periods).
        case trailingEllipsis
    }

    // MARK: — Validation

    /// Returns all tone violations found in `string`.
    ///
    /// Call this from tests or in `assertTone(_:context:)` to enumerate issues.
    public static func violations(in string: String) -> [ToneViolation] {
        var found: [ToneViolation] = []

        if containsAllCapsWord(string)          { found.append(.allCapsWord) }
        if containsExclamationMark(string)      { found.append(.exclamationMark) }
        if containsFillerApology(string)        { found.append(.fillerApology) }
        if startsWithTechnicalJargon(string)    { found.append(.technicalJargonLead) }
        if isPassiveHedge(string)               { found.append(.passiveHedge) }
        if hasTrailingEllipsis(string)          { found.append(.trailingEllipsis) }

        return found
    }

    /// Asserts (DEBUG-only) that `string` passes all tone guidelines.
    ///
    /// - Parameters:
    ///   - string:  The copy string to validate.
    ///   - context: A human-readable label identifying where this string is used,
    ///              shown in the assertion message (e.g. `"Server banner body"`).
    public static func assertTone(_ string: String, context: String = "") {
        #if DEBUG
        let found = violations(in: string)
        if !found.isEmpty {
            let label = context.isEmpty ? "Copy string" : context
            let violationList = found.map { "\($0)" }.joined(separator: ", ")
            assertionFailure(
                "[ToneGuidelines] \(label) violates: \(violationList)\n  String: \"\(string)\""
            )
        }
        #endif
    }

    // MARK: — Individual rule checks (internal for testability)

    /// Returns `true` when any word in `string` is entirely uppercase and longer than one character.
    ///
    /// Single uppercase letters (e.g. "I", "A") and acronyms that are 2 characters long
    /// are excluded because they are grammatically normal.
    static func containsAllCapsWord(_ string: String) -> Bool {
        let words = string.components(separatedBy: .whitespacesAndNewlines)
        return words.contains { word in
            // Strip leading/trailing punctuation before checking
            let stripped = word.trimmingCharacters(in: .punctuationCharacters)
            guard stripped.count > 2 else { return false }
            return stripped == stripped.uppercased()
        }
    }

    /// Returns `true` when `string` contains an exclamation mark character.
    static func containsExclamationMark(_ string: String) -> Bool {
        string.contains("!")
    }

    /// Returns `true` when `string` contains a filler apology word.
    ///
    /// Matched words (case-insensitive): "please", "sorry", "we apologize", "we're sorry",
    /// "apologies".
    static func containsFillerApology(_ string: String) -> Bool {
        let lower = string.lowercased()
        let patterns = ["please", "sorry", "we apologize", "we're sorry", "apologies"]
        return patterns.contains { lower.contains($0) }
    }

    /// Returns `true` when `string` starts with a technical jargon lead word.
    ///
    /// Matched prefixes (case-insensitive): "error:", "exception:", "failed:",
    /// "warning:", "critical:".
    static func startsWithTechnicalJargon(_ string: String) -> Bool {
        let lower = string.lowercased()
        let jargonPrefixes = ["error:", "exception:", "failed:", "warning:", "critical:"]
        return jargonPrefixes.contains { lower.hasPrefix($0) }
    }

    /// Returns `true` when `string` is a standalone vague passive hedge.
    ///
    /// Detects strings that consist entirely of one of these phrases (trimmed, case-insensitive):
    /// "there was a problem", "something went wrong", "an error occurred",
    /// "an error has occurred", "a problem occurred".
    static func isPassiveHedge(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = trimmed.lowercased()
        let hedges = [
            "there was a problem",
            "something went wrong",
            "an error occurred",
            "an error has occurred",
            "a problem occurred"
        ]
        return hedges.contains(lower)
    }

    /// Returns `true` when `string` ends with a trailing ellipsis.
    ///
    /// Detects both the Unicode ellipsis character (…) and three consecutive periods (...).
    static func hasTrailingEllipsis(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix("…") || trimmed.hasSuffix("...")
    }
}
