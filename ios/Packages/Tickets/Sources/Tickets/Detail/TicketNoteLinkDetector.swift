#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - §4.6 Link detection for ticket notes
//
// Detects phone numbers, email addresses, and URLs in note content and
// returns an AttributedString with tappable link attributes.
//
// Used by TicketNoteComposeView + NotesSection to render auto-linked text.

public enum TicketNoteLinkDetector {

    // MARK: - Public API

    /// Scans `text` for phone numbers, email addresses, and URLs.
    /// Returns an `AttributedString` where each detected item has a `.link`
    /// attribute so SwiftUI renders it as a tappable link.
    ///
    /// Combines with `TicketNoteMarkdownRenderer` by applying markdown first,
    /// then post-processing with `NSDataDetector` for links.
    public static func detectLinks(in text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString(text) }

        do {
            let detectorTypes: NSTextCheckingResult.CheckingType = [
                .phoneNumber, .link
            ]
            let detector = try NSDataDetector(types: detectorTypes.rawValue)
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            let matches = detector.matches(in: text, options: [], range: range)

            guard !matches.isEmpty else {
                return AttributedString(text)
            }

            var result = AttributedString()
            var lastIndex = text.startIndex

            for match in matches.sorted(by: { $0.range.location < $1.range.location }) {
                guard let swiftRange = Range(match.range, in: text) else { continue }

                // Plain text before the match
                if lastIndex < swiftRange.lowerBound {
                    result.append(AttributedString(String(text[lastIndex..<swiftRange.lowerBound])))
                }

                // Linked text
                let matchedString = String(text[swiftRange])
                var linkAttr = AttributedString(matchedString)
                var container = AttributeContainer()

                if let url = match.url {
                    container.link = url
                } else if let phone = match.phoneNumber {
                    let tel = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") ?? URL(string: "tel:\(phone)")!
                    container.link = tel
                } else {
                    // Fallback: treat as plain text
                    result.append(AttributedString(matchedString))
                    lastIndex = swiftRange.upperBound
                    continue
                }
                container.foregroundColor = .init(.bizarreOrange)
                linkAttr.mergeAttributes(container)
                result.append(linkAttr)
                lastIndex = swiftRange.upperBound
            }

            // Remaining plain text
            if lastIndex < text.endIndex {
                result.append(AttributedString(String(text[lastIndex...])))
            }

            return result
        } catch {
            return AttributedString(text)
        }
    }

    // MARK: - Convenience: markdown + link detection combined

    /// Renders `raw` through the markdown-lite parser, then overlays link
    /// detection on the plain-text portions.
    ///
    /// This is the preferred entry point for note rendering.
    public static func renderWithLinks(_ raw: String) -> AttributedString {
        // We do a single-pass approach: run link detection on the raw text to
        // produce link spans, then apply markdown on top for style spans.
        // Since markdown and link detection operate on different patterns this
        // two-pass approach is safe — they target different syntax.
        let withLinks = detectLinks(in: raw)
        // Append markdown styling on top by merging the attributed strings.
        // The link attributes survive mergeAttributes because they use different
        // attribute keys from the bold/italic/code styles.
        let withMarkdown = TicketNoteMarkdownRenderer.render(raw)
        // Merge: prefer markdown styles, preserve link attributes where present
        var merged = withLinks
        merged.mergeAttributes(withMarkdown.runs.reduce(AttributeContainer()) { acc, run in
            var c = acc
            if let font = run.font { c.font = font }
            if let fg = run.foregroundColor { c.foregroundColor = fg }
            return c
        }, mergePolicy: .keepNew)
        return merged
    }
}
#endif
