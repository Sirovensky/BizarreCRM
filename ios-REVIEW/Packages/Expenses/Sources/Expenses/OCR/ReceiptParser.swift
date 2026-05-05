import Foundation

// MARK: - ReceiptParser

/// Pure stateless parser. Takes raw OCR text and returns a structured
/// `ReceiptOCRResult`. All state mutations return new values (immutable style).
public enum ReceiptParser {

    // MARK: - Public API

    /// Parse raw text from a receipt into structured fields.
    public static func parse(rawText: String) -> ReceiptOCRResult {
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merchantName = extractMerchant(lines: lines)
        let totalCents = extractTotal(lines: lines)
        let taxCents = extractTax(lines: lines)
        let subtotalCents = extractSubtotal(lines: lines)
        let transactionDate = extractDate(lines: lines)
        let lineItems = extractLineItems(lines: lines)

        return ReceiptOCRResult(
            merchantName: merchantName,
            totalCents: totalCents,
            taxCents: taxCents,
            subtotalCents: subtotalCents,
            transactionDate: transactionDate,
            lineItems: lineItems.isEmpty ? nil : lineItems,
            rawText: rawText
        )
    }

    // MARK: - Amount regex

    /// Matches `$12.34` or `12.34` at end of line / after label.
    private static let amountPattern = #"\$?(\d{1,6}[.,]\d{2})"#
    private static let amountRegex = try! NSRegularExpression(pattern: amountPattern)

    /// Extract first dollar amount from a string. Returns cents (Int).
    static func extractAmount(from text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = amountRegex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let raw = String(text[captureRange]).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(raw) else { return nil }
        return Int((value * 100).rounded())
    }

    // MARK: - Line extraction helpers

    private static func extractMerchant(lines: [String]) -> String? {
        // First non-empty, non-numeric line is typically the merchant name.
        // Skip lines that look like addresses or dates.
        for line in lines.prefix(5) {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty,
                  stripped.count >= 3,
                  !stripped.hasPrefix("#"),
                  extractAmount(from: stripped) == nil,
                  !isDateLike(stripped) else { continue }
            // Remove phone patterns
            if stripped.range(of: #"\d{3}[-.\s]\d{3}[-.\s]\d{4}"#,
                               options: .regularExpression) != nil { continue }
            return stripped
        }
        return nil
    }

    private static func extractTotal(lines: [String]) -> Int? {
        let keywords = ["total", "grand total", "amount due", "amount charged", "balance due", "total due", "total amount"]
        // Search from bottom upward — total is usually last.
        for line in lines.reversed() {
            let lower = line.lowercased()
            let isTotal = keywords.contains { lower.contains($0) }
            // Exclude lines containing "subtotal" or "tax" when looking for total
            let isSubOrTax = lower.contains("subtotal") || lower.contains("sub total") || (lower.contains("tax") && !lower.contains("total"))
            if isTotal && !isSubOrTax, let cents = extractAmount(from: line) {
                return cents
            }
        }
        return nil
    }

    private static func extractTax(lines: [String]) -> Int? {
        let keywords = ["tax", "vat", "hst", "gst", "pst", "sales tax"]
        for line in lines {
            let lower = line.lowercased()
            if keywords.contains(where: { lower.contains($0) }),
               !lower.contains("total"),
               !lower.contains("subtotal"),
               let cents = extractAmount(from: line) {
                return cents
            }
        }
        return nil
    }

    private static func extractSubtotal(lines: [String]) -> Int? {
        for line in lines {
            let lower = line.lowercased()
            if (lower.contains("subtotal") || lower.contains("sub total")),
               let cents = extractAmount(from: line) {
                return cents
            }
        }
        return nil
    }

    // MARK: - Date extraction

    /// Date patterns: MM/DD/YYYY, DD-MM-YYYY, YYYY-MM-DD, "Jan 1 2024", etc.
    private static let datePatterns: [(pattern: String, format: String)] = [
        (#"\b(\d{1,2}[/\-]\d{1,2}[/\-]\d{4})\b"#, "MM/dd/yyyy"),
        (#"\b(\d{4}[/\-]\d{1,2}[/\-]\d{1,2})\b"#, "yyyy-MM-dd"),
        (#"\b(\d{1,2}[/\-]\d{1,2}[/\-]\d{2})\b"#,  "MM/dd/yy"),
        (#"\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4})\b"#, "MMM dd, yyyy"),
        (#"\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2}\s+\d{4})\b"#, "MMM dd yyyy"),
    ]

    static func extractDate(lines: [String]) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)

        let fullText = lines.joined(separator: "\n")

        for (pattern, format) in datePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(fullText.startIndex..., in: fullText)
            guard let match = regex.firstMatch(in: fullText, range: range),
                  let captureRange = Range(match.range(at: 1), in: fullText) else { continue }
            let dateStr = String(fullText[captureRange])
                .replacingOccurrences(of: "-", with: "/")
                .replacingOccurrences(of: ",", with: "")
            // Normalize format separators
            let normalizedFormat = format.replacingOccurrences(of: "-", with: "/")
            dateFormatter.dateFormat = normalizedFormat
            if let date = dateFormatter.date(from: dateStr) { return date }
        }
        return nil
    }

    // MARK: - Line items

    private static let lineItemPattern = #"^(.+?)\s+\$?(\d{1,6}[.,]\d{2})\s*$"#
    private static let lineItemRegex = try! NSRegularExpression(pattern: lineItemPattern)

    static func extractLineItems(lines: [String]) -> [ReceiptLineItem] {
        let skipKeywords = ["total", "subtotal", "tax", "vat", "tip", "change", "cash", "card", "balance", "amount due", "thank"]
        return lines.compactMap { line in
            let lower = line.lowercased()
            guard !skipKeywords.contains(where: { lower.contains($0) }) else { return nil }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = lineItemRegex.firstMatch(in: line, range: range) else { return nil }

            let descRange = Range(match.range(at: 1), in: line).map { String(line[$0]) }
            let amtRange = Range(match.range(at: 2), in: line).map { String(line[$0]) }

            guard let desc = descRange, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let cents = amtRange.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }.map { Int(($0 * 100).rounded()) }
            return ReceiptLineItem(description: desc.trimmingCharacters(in: .whitespacesAndNewlines), amountCents: cents)
        }
    }

    // MARK: - Helpers

    private static func isDateLike(_ text: String) -> Bool {
        let dateRegex = try? NSRegularExpression(pattern: #"\d{1,4}[/\-]\d{1,2}[/\-]\d{2,4}"#)
        let range = NSRange(text.startIndex..., in: text)
        return dateRegex?.firstMatch(in: text, range: range) != nil
    }
}
