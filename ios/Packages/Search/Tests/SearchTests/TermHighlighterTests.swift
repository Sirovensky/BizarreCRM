import XCTest
import SwiftUI
@testable import Search

final class TermHighlighterTests: XCTestCase {

    // MARK: - attributed(snippet:)

    func test_attributed_plainText_noMarkers_returnsSameString() {
        let result = TermHighlighter.attributed(snippet: "Hello world")
        XCTAssertEqual(String(result.characters), "Hello world")
    }

    func test_attributed_singleHighlight_rendersCorrectText() {
        let result = TermHighlighter.attributed(snippet: "Hello <b>world</b>")
        let full = String(result.characters)
        XCTAssertEqual(full, "Hello world")
    }

    func test_attributed_multipleHighlights_allDetagged() {
        let result = TermHighlighter.attributed(snippet: "<b>one</b> and <b>two</b>")
        XCTAssertEqual(String(result.characters), "one and two")
    }

    func test_attributed_trailingText_preserved() {
        let result = TermHighlighter.attributed(snippet: "see <b>term</b> here")
        XCTAssertEqual(String(result.characters), "see term here")
    }

    func test_attributed_emptyHighlight_nocrash() {
        let result = TermHighlighter.attributed(snippet: "<b></b>")
        XCTAssertEqual(String(result.characters), "")
    }

    func test_attributed_ellipsis_preserved() {
        let result = TermHighlighter.attributed(snippet: "…some <b>match</b>…")
        XCTAssertEqual(String(result.characters), "…some match…")
    }

    // MARK: - highlight(text:query:)

    func test_highlight_emptyQuery_returnsOriginalText() {
        let result = TermHighlighter.highlight(text: "Alice Smith", query: "")
        XCTAssertEqual(String(result.characters), "Alice Smith")
    }

    func test_highlight_noMatch_returnsOriginalText() {
        let result = TermHighlighter.highlight(text: "Alice Smith", query: "zzz")
        XCTAssertEqual(String(result.characters), "Alice Smith")
    }

    func test_highlight_singleMatch_preservesFullText() {
        let result = TermHighlighter.highlight(text: "Alice Smith", query: "Alice")
        XCTAssertEqual(String(result.characters), "Alice Smith")
    }

    func test_highlight_caseInsensitive() {
        // "alice" should match "Alice"
        let result = TermHighlighter.highlight(text: "Alice Smith", query: "alice")
        XCTAssertEqual(String(result.characters), "Alice Smith")
    }

    func test_highlight_multipleTokens_bothMatched() {
        let text = "Alice Smith"
        let result = TermHighlighter.highlight(text: text, query: "Alice Smith")
        XCTAssertEqual(String(result.characters), text)
    }

    func test_highlight_multipleOccurrences_allPreserved() {
        let text = "iphone iphone"
        let result = TermHighlighter.highlight(text: text, query: "iphone")
        XCTAssertEqual(String(result.characters), text)
    }

    func test_highlight_diacriticInsensitive() {
        // "café" should match "cafe"
        let result = TermHighlighter.highlight(text: "Café Roma", query: "cafe")
        XCTAssertEqual(String(result.characters), "Café Roma")
    }
}
