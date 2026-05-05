import Foundation

/// Pure-function IMEI validation. No UIKit/AppKit dependency.
/// Implements Luhn algorithm for 15-digit IMEI numbers.
public enum IMEIValidator {

    /// Returns `true` if `imei` is exactly 15 digits and passes the Luhn checksum.
    public static func isValid(_ imei: String) -> Bool {
        let digits = imei.filter(\.isNumber)
        guard digits.count == 15 else { return false }
        return luhn(digits)
    }

    /// Formats a raw 15-digit string as IMEI groups (e.g. "AA-BBBBBB-CCCCCC-D").
    /// Returns `nil` if the string does not contain exactly 15 digits.
    public static func format(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 15 else { return nil }
        let s = Array(digits)
        // TAC (6) + FAC (2) + SNR (6) + CD (1) => display as 6-6-2-1 visual
        // Most industry tooling shows 15 bare digits; we expose the raw string.
        return "\(String(s[0..<6]))-\(String(s[6..<12]))-\(String(s[12..<15]))"
    }

    // MARK: - Private

    /// Luhn mod-10 check. Accepts exactly a digit-only string.
    private static func luhn(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 15 else { return false }

        var sum = 0
        for (i, digit) in values.reversed().enumerated() {
            if i % 2 == 0 {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum % 10 == 0
    }
}
