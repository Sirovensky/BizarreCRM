import Foundation

/// §18.1 — Query normalisation for special identifier formats.
///
/// Detects when a search query is most likely a phone number or an IMEI and
/// returns a digits-only canonical form so that both the local FTS index and
/// the server's `GET /search?q=` endpoint match formatted variants of the same
/// value (e.g. `(415) 555-1212` ↔ `4155551212`, `35-209900-176148-1` ↔
/// `352099001761481`).
///
/// Heuristic rules (kept intentionally conservative — no machine learning):
/// 1. Strip all non-digit characters from the input.
/// 2. If the digit run is **exactly 15 digits** → IMEI.
/// 3. If the digit run is **10–14 digits** with no embedded letters → phone.
///    For 11+ digit phones we keep the last 10 (`+1 415 555 1212` → `4155551212`).
/// 4. Otherwise the original (trimmed) query passes through unchanged so
///    name/text searches behave as before.
public enum QueryNormalizer {

    public enum Kind: Equatable {
        case passthrough
        case phone
        case imei
    }

    public struct Normalised: Equatable {
        public let value: String
        public let kind: Kind

        public init(value: String, kind: Kind) {
            self.value = value
            self.kind = kind
        }
    }

    /// Normalise `raw`. Safe for empty strings (returns `.passthrough` of "").
    public static func normalise(_ raw: String) -> Normalised {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Normalised(value: "", kind: .passthrough)
        }

        // Reject anything that contains letters (names, SKUs that mix letters).
        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        if hasLetters { return Normalised(value: trimmed, kind: .passthrough) }

        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return Normalised(value: trimmed, kind: .passthrough) }

        // §18.1 IMEI — exactly 15 digits.
        if digits.count == 15 {
            return Normalised(value: digits, kind: .imei)
        }

        // §18.1 Phone — 10–14 digits, last 10 wins (handles country codes).
        if (10...14).contains(digits.count) {
            let last10 = String(digits.suffix(10))
            return Normalised(value: last10, kind: .phone)
        }

        return Normalised(value: trimmed, kind: .passthrough)
    }
}
