#if canImport(UIKit)
import Foundation
import UIKit

// §4.6 — Markdown-lite renderer for ticket notes.
//
// Supported patterns (subset of CommonMark):
//   **bold**          → bold weight
//   *italic*          → italic
//   `code`            → monospaced, code block background
//   - bullet          → bullet list item
//   @mention          → tinted mention token
//
// Returns an `AttributedString` for rendering in SwiftUI `Text`.
// Pure function — no side effects.

public enum TicketNoteMarkdownRenderer {

    // MARK: - Public API

    /// Converts a markdown-lite note string to `AttributedString`.
    /// Falls back to plain `AttributedString` on parse failure.
    public static func render(_ raw: String) -> AttributedString {
        do {
            return try parse(raw)
        } catch {
            return AttributedString(raw)
        }
    }

    // MARK: - Parser

    private static func parse(_ raw: String) throws -> AttributedString {
        var result = AttributedString()

        // Process line by line for bullet support; each line re-enters the
        // inline parser.
        let lines = raw.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 { result.append(AttributedString("\n")) }

            if line.hasPrefix("- ") || line.hasPrefix("• ") {
                // Bullet list item
                let rest = String(line.dropFirst(2))
                var bullet = AttributedString("• ")
                var bulletContainer = AttributeContainer()
                bulletContainer.foregroundColor = .init(.bizarreOnSurface)
                bullet.mergeAttributes(bulletContainer)
                result.append(bullet)
                result.append(try parseInline(rest))
            } else {
                result.append(try parseInline(line))
            }
        }
        return result
    }

    private static func parseInline(_ raw: String) throws -> AttributedString {
        var result = AttributedString()
        var remaining = Substring(raw)

        while !remaining.isEmpty {
            // **bold**
            if remaining.hasPrefix("**") {
                let afterOpen = remaining.dropFirst(2)
                if let closeRange = afterOpen.range(of: "**") {
                    let inner = String(afterOpen[..<closeRange.lowerBound])
                    var attr = AttributedString(inner)
                    var container = AttributeContainer()
                    container.font = .init(UIFont.boldSystemFont(ofSize: UIFont.systemFontSize))
                    attr.mergeAttributes(container)
                    result.append(attr)
                    remaining = afterOpen[closeRange.upperBound...]
                    continue
                }
            }

            // *italic* (but not **)
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**") {
                let afterOpen = remaining.dropFirst(1)
                if let closeRange = afterOpen.range(of: "*") {
                    let inner = String(afterOpen[..<closeRange.lowerBound])
                    var attr = AttributedString(inner)
                    var container = AttributeContainer()
                    container.font = .init(UIFont.italicSystemFont(ofSize: UIFont.systemFontSize))
                    attr.mergeAttributes(container)
                    result.append(attr)
                    remaining = afterOpen[closeRange.upperBound...]
                    continue
                }
            }

            // `code`
            if remaining.hasPrefix("`") {
                let afterOpen = remaining.dropFirst(1)
                if let closeRange = afterOpen.range(of: "`") {
                    let inner = String(afterOpen[..<closeRange.lowerBound])
                    var attr = AttributedString(inner)
                    var container = AttributeContainer()
                    container.font = .init(.monospacedSystemFont(ofSize: UIFont.systemFontSize - 1, weight: .regular))
                    attr.mergeAttributes(container)
                    result.append(attr)
                    remaining = afterOpen[closeRange.upperBound...]
                    continue
                }
            }

            // @mention — word after @ until whitespace/punctuation
            if remaining.hasPrefix("@") {
                let afterAt = remaining.dropFirst(1)
                let endIdx = afterAt.firstIndex(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) ?? afterAt.endIndex
                let name = String(afterAt[..<endIdx])
                if !name.isEmpty {
                    var attr = AttributedString("@\(name)")
                    var container = AttributeContainer()
                    container.foregroundColor = .init(.bizarreOrange)
                    attr.mergeAttributes(container)
                    result.append(attr)
                    remaining = afterAt[endIdx...]
                    continue
                }
            }

            // Plain character — consume one character at a time to avoid
            // infinite loops.
            let ch = remaining.removeFirst()
            result.append(AttributedString(String(ch)))
        }

        return result
    }
}
#endif
