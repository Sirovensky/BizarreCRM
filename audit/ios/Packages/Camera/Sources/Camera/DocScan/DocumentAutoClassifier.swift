import Foundation

// MARK: - DocumentAutoClassifier
//
// §17 — "Auto-classification by keyword: license / invoice / receipt /
//         warranty → suggest tag"
//
// Pure-Swift, no UIKit dependency. Takes extracted OCR text and returns the
// most likely document tag. The caller (DocumentScanViewModel) runs this after
// `DocumentOCRService.extractText(from:)` and surfaces the suggestion.
//
// Privacy: classification is on-device only; no network call.

// MARK: - DocumentTag

/// Suggested document classification tag.
public enum DocumentTag: String, Sendable, CaseIterable, Identifiable {
    case license    = "License"
    case invoice    = "Invoice"
    case receipt    = "Receipt"
    case warranty   = "Warranty"
    case quotation  = "Quote"
    case contract   = "Contract"
    case other      = "Other"

    public var id: String { rawValue }

    /// SF Symbol for use in the suggestion chip.
    public var systemImageName: String {
        switch self {
        case .license:   return "person.text.rectangle"
        case .invoice:   return "doc.text"
        case .receipt:   return "scroll"
        case .warranty:  return "checkmark.shield"
        case .quotation: return "list.clipboard"
        case .contract:  return "signature"
        case .other:     return "doc"
        }
    }
}

// MARK: - DocumentAutoClassifier

/// Keyword-based document classifier.
///
/// Returns the best-matching ``DocumentTag`` and a confidence score (0–1).
/// A score below `minimumConfidence` yields `.other`.
///
/// Usage:
/// ```swift
/// let classifier = DocumentAutoClassifier()
/// let (tag, confidence) = classifier.classify(text: ocrText)
/// ```
public struct DocumentAutoClassifier: Sendable {

    // MARK: - Configuration

    /// Tags below this hit-rate are reported as `.other`.
    public let minimumConfidence: Double

    public init(minimumConfidence: Double = 0.25) {
        self.minimumConfidence = minimumConfidence
    }

    // MARK: - Keyword table

    private typealias KeywordList = [String]

    private static let keywords: [(DocumentTag, KeywordList)] = [
        (.license, [
            "driver", "license", "licence", "dl#", "dl num", "id card",
            "date of birth", "dob", "class", "expiration", "motor vehicle",
            "dmv", "department of motor", "issued by state",
        ]),
        (.invoice, [
            "invoice", "bill to", "ship to", "payment terms", "due date",
            "po number", "purchase order", "qty", "unit price", "subtotal",
            "invoice #", "invoice no", "net 30", "net 60", "remit to",
        ]),
        (.receipt, [
            "receipt", "thank you for your purchase", "total paid",
            "change due", "visa", "mastercard", "amex", "cash tendered",
            "transaction id", "auth code", "order #", "sale #",
            "subtotal", "tax", "tip", "cashier",
        ]),
        (.warranty, [
            "warranty", "limited warranty", "defect", "return policy",
            "service plan", "coverage", "repair", "replacement",
            "serial number", "model number", "proof of purchase",
            "this warranty", "excluded from warranty",
        ]),
        (.quotation, [
            "quote", "quotation", "estimate", "proposed", "valid for",
            "validity", "terms of quotation", "quote #", "quote no",
            "price estimate", "service estimate",
        ]),
        (.contract, [
            "agreement", "contract", "terms and conditions", "hereby agrees",
            "party", "parties", "signed by", "signature", "notary",
            "legal", "binding", "whereas", "consideration",
        ]),
    ]

    // MARK: - Classify

    /// Classify `text` and return the best-matching tag.
    ///
    /// - Parameter text: OCR-extracted text from the scanned document.
    /// - Returns: Tuple of `(DocumentTag, confidence: Double)`.
    ///   `confidence` is the fraction of matched keywords for the winning tag (0–1).
    public func classify(text: String) -> (tag: DocumentTag, confidence: Double) {
        let normalized = text.lowercased()

        var scores: [(DocumentTag, Int)] = []

        for (tag, kws) in Self.keywords {
            let hits = kws.filter { normalized.contains($0) }.count
            scores.append((tag, hits))
        }

        scores.sort { $0.1 > $1.1 }

        guard let best = scores.first, best.1 > 0 else {
            return (.other, 0)
        }

        let totalKeywords = Self.keywords.first(where: { $0.0 == best.0 })?.1.count ?? 1
        let confidence = Double(best.1) / Double(totalKeywords)

        if confidence < minimumConfidence {
            return (.other, confidence)
        }
        return (best.0, confidence)
    }
}
