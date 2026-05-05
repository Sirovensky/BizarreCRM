import Foundation

// MARK: - CouponValidationResult

/// The outcome of a client-side coupon pre-check.
///
/// This is intentionally non-exhaustive on the server side — the validator
/// only filters obvious local failures. All genuine redemption rules (usage
/// caps, per-customer limits, cart eligibility) are enforced by the server.
public enum CouponValidationResult: Equatable, Sendable {
    /// Passes all local checks; safe to send to the server.
    case valid
    /// Code string failed the format check (too short, too long, bad chars).
    case invalidFormat(String)
    /// Code is past its `expiresAt` timestamp.
    case expired(Date)
    /// Code has no remaining uses (local cache says 0).
    case exhausted
}

// MARK: - CouponValidator

/// Performs **client-side only** validation of a coupon code before the
/// network round-trip to `POST /coupons/apply`.
///
/// ## What it checks (locally)
/// - Format: 3–24 alphanumeric characters, hyphens, or underscores.
///   Accepts the patterns `SAVE20`, `PROMO-2024`, `VIP_TIER1`.
/// - Expiry: if a known `CouponCode` record is provided the `expiresAt`
///   timestamp is compared against `now`.
/// - Exhaustion: if `usesRemaining == 0` the code is locally flagged as
///   used up (server will double-check, but there is no point hitting the
///   network for a code we know is gone).
///
/// ## What it does NOT check
/// - Whether the code exists on the server.
/// - Whether the linked `DiscountRule` is active.
/// - Per-customer usage caps.
/// - Cart eligibility (min subtotal, category scoping, etc.).
public struct CouponValidator: Sendable {

    // MARK: - Constants

    /// Minimum number of non-whitespace characters in a code.
    public static let minCodeLength: Int = 3
    /// Maximum number of non-whitespace characters in a code.
    public static let maxCodeLength: Int = 24

    /// Allowed character set for coupon codes.
    private static let validCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_"))

    public init() {}

    // MARK: - Primary entry point

    /// Validate a raw code string entered by the user.
    ///
    /// - Parameters:
    ///   - rawCode:      The string as typed (case-insensitive; trimmed internally).
    ///   - knownCoupon:  Optional cached `CouponCode` record — used for expiry /
    ///                   exhaustion checks. Pass `nil` when the code has not been
    ///                   fetched from the server yet.
    ///   - now:          Reference time for expiry comparison. Defaults to `Date.now`.
    /// - Returns: `.valid` or a specific failure reason.
    public func validate(
        rawCode: String,
        knownCoupon: CouponCode? = nil,
        now: Date = .now
    ) -> CouponValidationResult {
        let trimmed = rawCode.trimmingCharacters(in: .whitespaces)

        // ── Format checks ────────────────────────────────────────────────
        if trimmed.count < Self.minCodeLength {
            return .invalidFormat(
                "Coupon code must be at least \(Self.minCodeLength) characters."
            )
        }
        if trimmed.count > Self.maxCodeLength {
            return .invalidFormat(
                "Coupon code must not exceed \(Self.maxCodeLength) characters."
            )
        }
        let illegal = trimmed.unicodeScalars.first {
            !Self.validCharacters.contains($0)
        }
        if illegal != nil {
            return .invalidFormat(
                "Coupon code may only contain letters, digits, hyphens, and underscores."
            )
        }

        // ── Expiry check (requires known record) ─────────────────────────
        if let coupon = knownCoupon {
            if coupon.isExpired(at: now) {
                let expiry = coupon.expiresAt ?? now  // expiresAt is always set when expired
                return .expired(expiry)
            }
            if coupon.isExhausted {
                return .exhausted
            }
        }

        return .valid
    }

    /// Convenience overload that accepts an already-canonical (uppercased,
    /// trimmed) code without a `CouponCode` record — useful for format-only
    /// checks in the input field's `onChange` handler.
    public func validateFormat(_ code: String) -> CouponValidationResult {
        validate(rawCode: code, knownCoupon: nil)
    }
}

// MARK: - CouponValidationResult helpers

public extension CouponValidationResult {
    /// `true` when the result is `.valid`.
    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    /// Human-readable failure description, or `nil` when valid.
    var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .invalidFormat(let msg):
            return msg
        case .expired(let date):
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            return "This coupon expired on \(fmt.string(from: date))."
        case .exhausted:
            return "This coupon has no remaining uses."
        }
    }
}
