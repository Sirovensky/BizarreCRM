import Foundation

// MARK: - §2.13 PIN Blocklist

/// Rejects common PINs (sequential runs, all-same, well-known combos,
/// and birthday-shaped patterns) that are trivially guessable.
///
/// Used at PIN setup time — present `BlocklistViolation.message` inline
/// so the staff member can choose a different PIN.
///
/// ```swift
/// if let violation = PINBlocklist.check(pin: entered) {
///     showError(violation.message)
/// }
/// ```
public enum PINBlocklist {

    // MARK: - Violations

    public enum BlocklistViolation: Sendable, Equatable {
        case allSameDigit
        case sequentialAscending
        case sequentialDescending
        case commonPattern(pattern: String)

        public var message: String {
            switch self {
            case .allSameDigit:
                return "PINs with all the same digit (e.g. 0000, 1111) are not allowed."
            case .sequentialAscending:
                return "Sequential PINs like 1234 or 123456 are not allowed."
            case .sequentialDescending:
                return "Sequential PINs like 9876 or 654321 are not allowed."
            case .commonPattern(let p):
                return "'\(p)' is a commonly used PIN and is not allowed. Choose something less obvious."
            }
        }
    }

    // MARK: - Common pattern list

    /// Well-known PINs beyond sequential / all-same.
    /// Kept small and non-exhaustive intentionally — the rules above catch the
    /// statistical majority; this list catches cultural references.
    private static let knownCommon: Set<String> = [
        // Year-looking patterns
        "2000", "2001", "2002", "2003", "2004", "2005", "2006", "2007",
        "2008", "2009", "2010", "2011", "2012", "2013", "2014", "2015",
        "2016", "2017", "2018", "2019", "2020", "2021", "2022", "2023",
        "2024", "2025", "2026",
        "1990", "1991", "1992", "1993", "1994", "1995", "1996", "1997",
        "1998", "1999", "1980", "1970",
        // Well-known combos
        "1212", "1111", "2222", "3333", "4444", "5555", "6666", "7777",
        "8888", "9999", "0000", "1234", "4321", "1357", "2468",
        "1122", "2233", "3344", "4455", "5566", "6677", "7788", "8899",
        "9900", "1001", "2112", "3223", "4334", "5445", "6556", "7667",
        "8778", "9889",
        // Common 6-digit additions
        "123456", "654321", "111111", "000000", "112233", "123123",
        "121212", "696969", "159753", "357159",
    ]

    // MARK: - Public API

    /// Returns the first `BlocklistViolation` if `pin` is on the blocklist, else `nil`.
    ///
    /// - Parameter pin: The raw digit string entered by the user (4–6 chars, digits only).
    public static func check(pin: String) -> BlocklistViolation? {
        guard !pin.isEmpty, pin.allSatisfy(\.isNumber) else { return nil }

        // 1. All same digit: "0000", "1111" …
        if Set(pin).count == 1 {
            return .allSameDigit
        }

        // 2. Ascending sequential: 1234, 2345, 123456 …
        if isSequential(pin, ascending: true) {
            return .sequentialAscending
        }

        // 3. Descending sequential: 9876, 8765, 987654 …
        if isSequential(pin, ascending: false) {
            return .sequentialDescending
        }

        // 4. Known-common list
        if knownCommon.contains(pin) {
            return .commonPattern(pattern: pin)
        }

        return nil
    }

    /// Returns `true` when `pin` is blocked.
    public static func isBlocked(_ pin: String) -> Bool {
        check(pin: pin) != nil
    }

    // MARK: - Helpers

    private static func isSequential(_ pin: String, ascending: Bool) -> Bool {
        let digits = pin.compactMap { $0.wholeNumberValue }
        guard digits.count >= 2 else { return false }
        let step: Int = ascending ? 1 : -1
        return zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == step }
    }
}
