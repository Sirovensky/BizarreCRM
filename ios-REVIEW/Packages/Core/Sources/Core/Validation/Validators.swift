import Foundation

// MARK: - §31.1 Validators — email, phone, SKU, IMEI
//
// Each validator is a pure function (no side-effects, no network, no state).
// Use in ViewModels and unit tests. Thread-safe by design.

// MARK: - ValidationResult

public enum ValidationResult: Equatable {
    case valid
    case invalid(String)   // Human-readable reason (English; localise at call-site)

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

// MARK: - EmailValidator

/// RFC 5322-compatible email validator (practical subset).
public enum EmailValidator {

    /// Maximum total length per RFC 5321.
    private static let maxLength = 254
    /// Local-part maximum length per RFC 5321.
    private static let maxLocalLength = 64
    /// Allowed characters in local-part (unquoted).
    private static let localAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "!#$%&'*+/=?^_`{|}~.-")
        return cs
    }()

    public static func validate(_ email: String) -> ValidationResult {
        guard !email.isEmpty else {
            return .invalid("Email must not be empty.")
        }
        guard email.count <= maxLength else {
            return .invalid("Email exceeds \(maxLength) characters.")
        }
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return .invalid("Email must contain exactly one '@'.")
        }
        let local = String(parts[0])
        let domain = String(parts[1])

        guard !local.isEmpty, local.count <= maxLocalLength else {
            return .invalid("Email local-part is empty or exceeds \(maxLocalLength) characters.")
        }
        guard !domain.isEmpty else {
            return .invalid("Email domain must not be empty.")
        }
        // Local-part must not start or end with a dot; no consecutive dots.
        guard !local.hasPrefix("."), !local.hasSuffix("."), !local.contains("..") else {
            return .invalid("Email local-part has invalid dot placement.")
        }
        // Local-part must only contain allowed characters.
        guard local.unicodeScalars.allSatisfy({ localAllowed.contains($0) }) else {
            return .invalid("Email local-part contains invalid characters.")
        }
        // Domain must have at least one dot and a non-empty TLD.
        let domainLabels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard domainLabels.count >= 2, domainLabels.last.map({ !$0.isEmpty }) == true else {
            return .invalid("Email domain must have at least one dot and a non-empty TLD.")
        }
        // Each domain label must be non-empty and ≤ 63 characters.
        for label in domainLabels {
            guard !label.isEmpty, label.count <= 63 else {
                return .invalid("Each DNS label in the email domain must be 1–63 characters.")
            }
        }
        return .valid
    }
}

// MARK: - PhoneValidator

/// E.164 and NANP phone validator.
///
/// Accepts:
///  - E.164: `+15551234567` (1–15 digits after `+`)
///  - NANP:  `(555) 123-4567`, `555-123-4567`, `5551234567` (10 digits, area code 200–999)
///
/// Strips common decorators (spaces, dashes, dots, parentheses) before checking.
public enum PhoneValidator {

    public static func validate(_ phone: String) -> ValidationResult {
        guard !phone.isEmpty else {
            return .invalid("Phone number must not be empty.")
        }
        let stripped = phone
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        if stripped.hasPrefix("+") {
            // E.164
            let digits = String(stripped.dropFirst())
            guard digits.allSatisfy(\.isNumber), (1...15).contains(digits.count) else {
                return .invalid("E.164 phone must have 1–15 digits after '+'.")
            }
            return .valid
        }

        // NANP (10 digits)
        guard stripped.count == 10, stripped.allSatisfy(\.isNumber) else {
            return .invalid("Phone must be 10 digits (NANP) or E.164 format.")
        }
        let areaCode = Int(stripped.prefix(3))!
        guard areaCode >= 200 else {
            return .invalid("NANP area code must be 200 or greater.")
        }
        return .valid
    }
}

// MARK: - SKUValidator

/// Stock-keeping unit validator.
///
/// BizarreCRM SKU format: `[A-Z0-9]{2,12}` optionally separated by dashes into segments.
/// Examples of valid SKUs: `WIDGET-001`, `PART42`, `ABC-DEF-0099`.
public enum SKUValidator {

    private static let allowedCharacters: CharacterSet = {
        var cs = CharacterSet.uppercaseLetters
        cs.formUnion(.decimalDigits)
        cs.insert("-")
        return cs
    }()

    public static func validate(_ sku: String) -> ValidationResult {
        guard !sku.isEmpty else {
            return .invalid("SKU must not be empty.")
        }
        let upper = sku.uppercased()
        guard upper.count >= 2, upper.count <= 40 else {
            return .invalid("SKU must be 2–40 characters.")
        }
        guard upper.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return .invalid("SKU may only contain uppercase letters, digits, and dashes.")
        }
        guard !upper.hasPrefix("-"), !upper.hasSuffix("-"), !upper.contains("--") else {
            return .invalid("SKU must not start/end with a dash or contain consecutive dashes.")
        }
        return .valid
    }
}

// MARK: - IMEIValidator

/// International Mobile Equipment Identity (IMEI) validator.
///
/// Uses the Luhn algorithm. Accepts 15-digit strings (with or without dashes in the
/// common `XX-XXXXXX-XXXXXX-X` grouping).
public enum IMEIValidator {

    public static func validate(_ imei: String) -> ValidationResult {
        guard !imei.isEmpty else {
            return .invalid("IMEI must not be empty.")
        }
        // Strip formatting dashes/spaces.
        let stripped = imei
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard stripped.count == 15 else {
            return .invalid("IMEI must be exactly 15 digits (got \(stripped.count)).")
        }
        guard stripped.allSatisfy(\.isNumber) else {
            return .invalid("IMEI must contain only digits.")
        }
        guard luhn(stripped) else {
            return .invalid("IMEI failed Luhn check digit validation.")
        }
        return .valid
    }

    // MARK: Luhn algorithm

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        let reversed = digits.reversed()
        for (index, char) in reversed.enumerated() {
            guard let digit = char.wholeNumberValue else { return false }
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
