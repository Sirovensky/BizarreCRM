import Foundation

/// §2.3 — Offline password strength evaluator for the Set-Password step.
///
/// Pure math / string checks. No I/O, no network. A small top-common
/// passwords list is embedded so the UI can reject obvious picks without
/// a round-trip (HIBP k-anonymity would be a server concern).
///
/// The evaluator is **deliberately separate from UI** so it can be unit
/// tested and reused by a future password-change flow in Settings.
public enum PasswordStrength: Int, Sendable, Comparable, CaseIterable {
    case veryWeak  = 0
    case weak      = 1
    case fair      = 2
    case strong    = 3
    case veryStrong = 4

    public static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short human label — shown under the meter.
    public var label: String {
        switch self {
        case .veryWeak:   return "Very weak"
        case .weak:       return "Weak"
        case .fair:       return "Fair"
        case .strong:     return "Strong"
        case .veryStrong: return "Very strong"
        }
    }
}

/// Rule outcomes — `true` means the rule is satisfied.
public struct PasswordRules: Equatable, Sendable {
    public var hasMinLength: Bool   // ≥ 8 chars
    public var hasMixedCase: Bool   // upper + lower
    public var hasDigit: Bool       // at least one 0-9
    public var hasSymbol: Bool      // at least one non-alphanumeric
    public var notCommon: Bool      // not in the embedded breach shortlist

    /// Rules that MUST be satisfied before the CTA unlocks.
    /// All five are required — weak breach-list picks are blocked even if
    /// length/class rules pass.
    public var allPassed: Bool {
        hasMinLength && hasMixedCase && hasDigit && hasSymbol && notCommon
    }
}

public struct PasswordEvaluation: Equatable, Sendable {
    public let rules: PasswordRules
    public let strength: PasswordStrength
    public let entropyBits: Double
}

public enum PasswordStrengthEvaluator {

    /// Top-100 most common passwords from public breach dumps. Stored
    /// lowercased — compare against `input.lowercased()`. Intentionally
    /// short; the server does real HIBP checks.
    static let commonPasswords: Set<String> = [
        "password", "password1", "password123", "passw0rd",
        "123456", "12345678", "123456789", "1234567890", "qwerty",
        "qwerty123", "qwertyuiop", "admin", "admin123", "administrator",
        "welcome", "welcome1", "welcome123", "letmein", "login",
        "abc123", "iloveyou", "monkey", "dragon", "master", "sunshine",
        "princess", "superman", "batman", "trustno1", "111111",
        "000000", "666666", "555555", "777777", "888888",
        "123123", "654321", "121212", "zaq12wsx", "qazwsx",
        "football", "baseball", "hockey", "soccer", "michael",
        "jordan23", "jesus", "jesus1", "shadow", "hello", "hello1",
        "pokemon", "starwars", "freedom", "whatever", "killer",
        "harley", "ranger", "hunter", "buster", "thomas",
        "robert", "soccer1", "charlie", "andrew", "matthew",
        "access", "access1", "access123", "flower", "hottie",
        "loveme", "zaq1xsw2", "changeme", "changeme1", "changeme123",
        "summer", "summer1", "winter", "spring", "fall2024",
        "bizarre", "bizarrecrm", "bizarrecrm1", "bizarrecrm123",
        "repair", "repair1", "repairshop", "repairshop1",
        "tech", "tech1", "support", "support1", "helpdesk",
        "p@ssw0rd", "p@ssword", "pa$$word", "pa$$w0rd",
        "admin@123", "admin@1", "root", "root123", "toor",
        "12qwaszx", "1q2w3e", "1q2w3e4r", "1q2w3e4r5t", "qwe123"
    ]

    /// Main entry point. Always returns an evaluation — even for empty
    /// input (all rules fail, entropy 0, strength `.veryWeak`).
    public static func evaluate(_ password: String) -> PasswordEvaluation {
        let rules = PasswordRules(
            hasMinLength: password.count >= 8,
            hasMixedCase: password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase),
            hasDigit:     password.contains(where: \.isNumber),
            hasSymbol:    password.contains(where: { !$0.isLetter && !$0.isNumber }),
            notCommon:    !commonPasswords.contains(password.lowercased())
        )

        let entropy = entropyBits(for: password)
        let strength = strength(for: entropy, rules: rules, password: password)

        return PasswordEvaluation(rules: rules, strength: strength, entropyBits: entropy)
    }

    /// Shannon-style character-class entropy: `log2(poolSize ^ length)`.
    /// Not cryptographically rigorous — good enough to rank UI feedback.
    static func entropyBits(for password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        var pool = 0
        if password.contains(where: \.isLowercase) { pool += 26 }
        if password.contains(where: \.isUppercase) { pool += 26 }
        if password.contains(where: \.isNumber)    { pool += 10 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 33 }
        guard pool > 0 else { return 0 }
        return Double(password.count) * log2(Double(pool))
    }

    static func strength(for entropy: Double, rules: PasswordRules, password: String) -> PasswordStrength {
        // Common-list hit forces .veryWeak regardless of entropy — a long
        // "password123" is still trivially guessable.
        if !rules.notCommon { return .veryWeak }
        if password.isEmpty { return .veryWeak }

        switch entropy {
        case ..<28:  return .veryWeak
        case ..<40:  return .weak
        case ..<56:  return .fair
        case ..<72:  return .strong
        default:     return .veryStrong
        }
    }
}
