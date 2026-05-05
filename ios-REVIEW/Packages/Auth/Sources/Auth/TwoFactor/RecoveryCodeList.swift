import Foundation

// MARK: - RecoveryCodeList
// Pure value type: holds backup codes + grid formatting helpers.
// NO storage in UserDefaults — caller holds in-memory only.

public struct RecoveryCodeList: Equatable, Sendable {

    public let codes: [String]

    public init(codes: [String]) {
        self.codes = codes
    }

    // MARK: - Formatting

    /// Formats a single code for display: uppercase, dash at position 8 (or midpoint for shorter codes).
    /// e.g. "ABCD1234EFGH" → "ABCD1234-EFGH"; "ABCD1234" → "ABCD-1234".
    /// Real server codes are 16-char Crockford base32 → "ABCDEFGH-IJKLMNOP".
    public func formatted(_ code: String) -> String {
        let upper = code.uppercased()
        guard upper.count > 4 else { return upper }
        // Use position 8 when code is long enough (≥9 chars), else midpoint.
        let splitPos = upper.count >= 9 ? 8 : upper.count / 2
        let splitIndex = upper.index(upper.startIndex, offsetBy: splitPos)
        return String(upper[..<splitIndex]) + "-" + String(upper[splitIndex...])
    }

    /// All codes formatted for display.
    public var formattedCodes: [String] {
        codes.map { formatted($0) }
    }

    /// Plain-text block suitable for clipboard / file export.
    /// Emits formatted codes one per line, preceded by a header.
    public var exportText: String {
        let header = "BizarreCRM Recovery Codes\nGenerated: \(isoDate)\nStore these codes in a safe place.\n\n"
        let body = formattedCodes.joined(separator: "\n")
        return header + body
    }

    /// 2-column grid arrangement: array of (left, right?) pairs.
    public var grid: [(String, String?)] {
        var result: [(String, String?)] = []
        let formatted = formattedCodes
        var idx = 0
        while idx < formatted.count {
            let left = formatted[idx]
            let right = idx + 1 < formatted.count ? formatted[idx + 1] : nil
            result.append((left, right))
            idx += 2
        }
        return result
    }

    // MARK: - Private helpers

    private var isoDate: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: Date())
    }
}
