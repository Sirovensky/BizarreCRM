import XCTest
@testable import Communications

// MARK: - SnippetVariableParserTests

final class SnippetVariableParserTests: XCTestCase {

    // MARK: - Extract

    func test_extract_findsAllDoublebraceTokens() {
        let text = "Hi {{first_name}}, your balance is {{amount}}."
        let tokens = SnippetVariableParser.extract(from: text)
        XCTAssertEqual(tokens, ["{{first_name}}", "{{amount}}"])
    }

    func test_extract_deduplicates() {
        let text = "{{first_name}} {{first_name}} {{last_name}}"
        let tokens = SnippetVariableParser.extract(from: text)
        XCTAssertEqual(tokens.filter { $0 == "{{first_name}}" }.count, 1)
        XCTAssertEqual(tokens.count, 2)
    }

    func test_extract_returnsEmpty_forPlainText() {
        let text = "No placeholders here."
        XCTAssertTrue(SnippetVariableParser.extract(from: text).isEmpty)
    }

    func test_extract_doesNotMatchSingleBraces() {
        let text = "Hello {first_name} — single brace should not match."
        XCTAssertTrue(SnippetVariableParser.extract(from: text).isEmpty)
    }

    func test_extract_preservesOrder() {
        let text = "{{date}} then {{company}} then {{ticket_no}}"
        let tokens = SnippetVariableParser.extract(from: text)
        XCTAssertEqual(tokens, ["{{date}}", "{{company}}", "{{ticket_no}}"])
    }

    // MARK: - Render with explicit map

    func test_render_substitutesProvidedVariables() {
        let text = "Hello {{first_name}}!"
        let result = SnippetVariableParser.render(text, variables: ["{{first_name}}": "Alice"])
        XCTAssertEqual(result, "Hello Alice!")
    }

    func test_render_acceptsBareName_withoutBraces() {
        let text = "Hello {{first_name}}!"
        let result = SnippetVariableParser.render(text, variables: ["first_name": "Bob"])
        XCTAssertEqual(result, "Hello Bob!")
    }

    func test_render_leavesUnknownTokensUnchanged() {
        let text = "Hello {{unknown}}!"
        let result = SnippetVariableParser.render(text, variables: ["{{first_name}}": "Carol"])
        XCTAssertTrue(result.contains("{{unknown}}"))
    }

    func test_render_multipleSubstitutions() {
        let text = "Hi {{first_name}} {{last_name}}, ticket: {{ticket_no}}"
        let result = SnippetVariableParser.render(text, variables: [
            "{{first_name}}": "Jane",
            "{{last_name}}": "Smith",
            "{{ticket_no}}": "TKT-001"
        ])
        XCTAssertEqual(result, "Hi Jane Smith, ticket: TKT-001")
    }

    // MARK: - renderSample

    func test_renderSample_substitutesFirstName() {
        let text = "Hello {{first_name}}!"
        let result = SnippetVariableParser.renderSample(text)
        XCTAssertEqual(result, "Hello Jane!")
    }

    func test_renderSample_substitutesCompany() {
        let text = "From {{company}}"
        let result = SnippetVariableParser.renderSample(text)
        XCTAssertEqual(result, "From Acme Corp")
    }

    func test_renderSample_substitutesTicketNo() {
        let text = "Ticket: {{ticket_no}}"
        let result = SnippetVariableParser.renderSample(text)
        XCTAssertEqual(result, "Ticket: TKT-0042")
    }

    func test_renderSample_substitutesAmount() {
        let text = "Due: {{amount}}"
        let result = SnippetVariableParser.renderSample(text)
        XCTAssertEqual(result, "Due: $149.99")
    }

    func test_renderSample_substitutesPhone() {
        let text = "Call {{phone}}"
        let result = SnippetVariableParser.renderSample(text)
        XCTAssertFalse(result.contains("{{phone}}"))
    }

    func test_renderSample_noOp_forPlainText() {
        let text = "Just a plain message."
        XCTAssertEqual(SnippetVariableParser.renderSample(text), text)
    }
}
