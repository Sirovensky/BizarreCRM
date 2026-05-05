import Foundation

// MARK: - Validation result

public struct ValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let errorMessage: String?

    public static let valid = ValidationResult(isValid: true, errorMessage: nil)

    public static func invalid(_ message: String) -> ValidationResult {
        ValidationResult(isValid: false, errorMessage: message)
    }
}

// MARK: - CompanyInfoValidator

/// Pure value-type validator for Step 2 (Company Info) fields.
/// Stateless — all methods are static so they're trivially testable.
public enum CompanyInfoValidator {

    // MARK: Name

    public static func validateName(_ name: String) -> ValidationResult {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid("Company name is required.")
        }
        guard trimmed.count >= 2 else {
            return .invalid("Company name must be at least 2 characters.")
        }
        guard trimmed.count <= 200 else {
            return .invalid("Company name is too long (max 200 characters).")
        }
        return .valid
    }

    // MARK: Phone  (XXX) XXX-XXXX

    /// Returns formatted phone string if valid, nil otherwise.
    public static func formatPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        switch digits.count {
        case 10:
            let area   = digits.prefix(3)
            let prefix = digits.dropFirst(3).prefix(3)
            let line   = digits.dropFirst(6).prefix(4)
            return "(\(area)) \(prefix)-\(line)"
        case 11 where digits.first == "1":
            // Strip leading country code
            let stripped = String(digits.dropFirst())
            return formatPhone(stripped)
        default:
            return raw
        }
    }

    public static func validatePhone(_ phone: String) -> ValidationResult {
        let digits = phone.filter(\.isNumber)
        let normalised = digits.count == 11 && digits.first == "1" ? String(digits.dropFirst()) : digits
        guard normalised.count == 10 else {
            return .invalid("Enter a 10-digit US phone number, e.g. (555) 123-4567.")
        }
        return .valid
    }

    // MARK: Website / URL

    public static func validateWebsite(_ url: String) -> ValidationResult {
        guard !url.isEmpty else { return .valid } // optional field
        let lowered = url.lowercased()
        let prefixed = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
            ? url
            : "https://\(url)"
        guard let parsed = URL(string: prefixed), parsed.host != nil else {
            return .invalid("Enter a valid website URL, e.g. https://example.com.")
        }
        return .valid
    }

    // MARK: EIN  (optional — XX-XXXXXXX)

    public static func validateEIN(_ ein: String) -> ValidationResult {
        guard !ein.isEmpty else { return .valid } // optional
        let digits = ein.filter(\.isNumber)
        guard digits.count == 9 else {
            return .invalid("EIN must be 9 digits (e.g. 12-3456789).")
        }
        return .valid
    }

    // MARK: Aggregate

    public struct CompanyInfoFields: Sendable {
        public let name: String
        public let phone: String
        public let website: String
        public let ein: String

        public init(name: String, phone: String, website: String, ein: String) {
            self.name = name
            self.phone = phone
            self.website = website
            self.ein = ein
        }
    }

    public static func validate(_ fields: CompanyInfoFields) -> [String: ValidationResult] {
        [
            "name":    validateName(fields.name),
            "phone":   validatePhone(fields.phone),
            "website": validateWebsite(fields.website),
            "ein":     validateEIN(fields.ein)
        ]
    }

    public static func isNextEnabled(name: String, phone: String) -> Bool {
        validateName(name).isValid && (phone.isEmpty || validatePhone(phone).isValid)
    }
}
