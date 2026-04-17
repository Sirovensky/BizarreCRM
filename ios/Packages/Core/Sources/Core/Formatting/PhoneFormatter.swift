import Foundation

/// Per memory: always format NA numbers as `+1 (XXX)-XXX-XXXX`.
public enum PhoneFormatter {
    public static func format(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let trimmed: String
        if digits.count == 11, digits.hasPrefix("1") {
            trimmed = String(digits.dropFirst())
        } else {
            trimmed = digits
        }
        guard trimmed.count == 10 else { return raw }
        let area = trimmed.prefix(3)
        let mid = trimmed.dropFirst(3).prefix(3)
        let last = trimmed.suffix(4)
        return "+1 (\(area))-\(mid)-\(last)"
    }

    public static func normalize(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return raw
    }
}
