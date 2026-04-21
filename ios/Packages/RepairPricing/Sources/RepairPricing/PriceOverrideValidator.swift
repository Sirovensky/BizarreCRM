import Foundation

// MARK: - §43.3 Validation

/// Validates PriceOverride editor form fields.
/// All methods are pure / static — easy to unit test.
public enum PriceOverrideValidator {

    public enum ValidationError: LocalizedError, Equatable {
        case priceEmpty
        case priceInvalid
        case priceNotPositive
        case customerIdRequiredForCustomerScope

        public var errorDescription: String? {
            switch self {
            case .priceEmpty:
                return "Please enter a price."
            case .priceInvalid:
                return "Price must be a valid number (e.g. 29.99)."
            case .priceNotPositive:
                return "Price must be greater than zero."
            case .customerIdRequiredForCustomerScope:
                return "A customer ID is required for customer-scoped overrides."
            }
        }
    }

    /// Returns `.success(priceCents)` or `.failure(ValidationError)`.
    /// `rawPrice` is the user-typed string (e.g. "29.99" or "2999").
    /// `scope` and `customerId` validate cross-field constraints.
    public static func validate(
        rawPrice: String,
        scope: OverrideScope,
        customerId: String?
    ) -> Result<Int, ValidationError> {
        let trimmed = rawPrice.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(.priceEmpty)
        }

        guard let dollars = Double(trimmed) else {
            return .failure(.priceInvalid)
        }

        guard dollars > 0 else {
            return .failure(.priceNotPositive)
        }

        if scope == .customer {
            let cid = customerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cid.isEmpty else {
                return .failure(.customerIdRequiredForCustomerScope)
            }
        }

        let cents = Int((dollars * 100).rounded())
        return .success(cents)
    }
}
