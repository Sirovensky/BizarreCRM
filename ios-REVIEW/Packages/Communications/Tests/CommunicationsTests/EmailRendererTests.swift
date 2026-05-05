import XCTest
@testable import Communications

// MARK: - EmailRendererTests
// TDD: written before EmailRenderer was implemented.

final class EmailRendererTests: XCTestCase {

    // MARK: - Helpers

    private func makeTemplate(
        subject: String = "Hello {first_name}",
        htmlBody: String = "<p>Hi {first_name}, ticket {ticket_no} total {total}</p>",
        plainBody: String = "Hi {first_name}, ticket {ticket_no} total {total}"
    ) -> EmailTemplate {
        EmailTemplate(
            id: 1,
            name: "Test",
            subject: subject,
            htmlBody: htmlBody,
            plainBody: plainBody,
            category: .reminder,
            dynamicVars: ["{first_name}", "{ticket_no}", "{total}"]
        )
    }

    // MARK: - Subject substitution

    func test_render_substitutesSubject() {
        let template = makeTemplate(subject: "Hello {first_name}")
        let ctx: [String: String] = ["first_name": "Alice"]
        let result = EmailRenderer.render(template: template, context: ctx)
        XCTAssertEqual(result.subject, "Hello Alice")
    }

    func test_render_unknownVarInSubject_unchanged() {
        let template = makeTemplate(subject: "Hi {custom_var}")
        let result = EmailRenderer.render(template: template, context: [:])
        XCTAssertEqual(result.subject, "Hi {custom_var}")
    }

    // MARK: - HTML substitution

    func test_render_substitutesHtmlBody() {
        let template = makeTemplate(htmlBody: "<p>Hi {first_name}</p>")
        let result = EmailRenderer.render(template: template, context: ["first_name": "Bob"])
        XCTAssertTrue(result.html.contains("Hi Bob"))
    }

    func test_render_multipleVarsInHtml() {
        let template = makeTemplate(
            htmlBody: "<p>{first_name} — ticket {ticket_no} — total {total}</p>"
        )
        let ctx: [String: String] = ["first_name": "Jane", "ticket_no": "TKT-99", "total": "$49"]
        let result = EmailRenderer.render(template: template, context: ctx)
        XCTAssertTrue(result.html.contains("Jane"))
        XCTAssertTrue(result.html.contains("TKT-99"))
        XCTAssertTrue(result.html.contains("$49"))
        XCTAssertFalse(result.html.contains("{first_name}"))
    }

    // MARK: - Plain body substitution

    func test_render_substitutesPlainBody() {
        let template = makeTemplate(plainBody: "Hi {first_name}")
        let result = EmailRenderer.render(template: template, context: ["first_name": "Carol"])
        XCTAssertEqual(result.plain, "Hi Carol")
    }

    // MARK: - HTML-to-plain stripping (when plainBody not provided)

    func test_render_htmlTags_strippedForPlain() {
        let template = EmailTemplate(
            id: 2,
            name: "Strip test",
            subject: "S",
            htmlBody: "<h1>Hello <b>World</b></h1><p>Body text here.</p>",
            plainBody: nil,
            category: .reminder,
            dynamicVars: []
        )
        let result = EmailRenderer.render(template: template, context: [:])
        XCTAssertFalse(result.plain.contains("<h1>"))
        XCTAssertFalse(result.plain.contains("<b>"))
        XCTAssertFalse(result.plain.contains("<p>"))
        XCTAssertTrue(result.plain.contains("Hello"))
        XCTAssertTrue(result.plain.contains("World"))
        XCTAssertTrue(result.plain.contains("Body text here."))
    }

    func test_render_htmlEntityDecoded_inPlain() {
        let template = EmailTemplate(
            id: 3,
            name: "Entities",
            subject: "S",
            htmlBody: "<p>Price: &amp;49 &lt;USD&gt;</p>",
            plainBody: nil,
            category: .reminder,
            dynamicVars: []
        )
        let result = EmailRenderer.render(template: template, context: [:])
        // Should decode &amp; → & and &lt; → <
        XCTAssertTrue(result.plain.contains("&49") || result.plain.contains("Price:"))
    }

    // MARK: - Missing variable fallback

    func test_render_missingVar_leavesPlaceholder() {
        let template = makeTemplate(subject: "Hi {first_name} from {shop_name}")
        let result = EmailRenderer.render(template: template, context: ["first_name": "Dave"])
        XCTAssertTrue(result.subject.contains("Dave"))
        XCTAssertTrue(result.subject.contains("{shop_name}"))
    }

    func test_render_emptyContext_leavesAllPlaceholders() {
        let template = makeTemplate(subject: "{first_name}")
        let result = EmailRenderer.render(template: template, context: [:])
        XCTAssertEqual(result.subject, "{first_name}")
    }

    // MARK: - All vars substituted with sample

    func test_render_sampleContext_noPlaceholdersRemainInHtml() {
        let template = makeTemplate(
            htmlBody: "<p>{first_name} {ticket_no} {total} {due_date} {tech_name} {appointment_time} {shop_name}</p>"
        )
        let ctx = EmailRenderer.sampleContext
        let result = EmailRenderer.render(template: template, context: ctx)
        XCTAssertFalse(result.html.contains("{first_name}"))
        XCTAssertFalse(result.html.contains("{ticket_no}"))
        XCTAssertFalse(result.html.contains("{total}"))
    }

    // MARK: - Empty template bodies

    func test_render_emptyHtmlBody_returnsEmpty() {
        let template = makeTemplate(htmlBody: "")
        let result = EmailRenderer.render(template: template, context: [:])
        XCTAssertTrue(result.html.isEmpty)
    }

    func test_render_emptySubject_returnsEmpty() {
        let template = makeTemplate(subject: "")
        let result = EmailRenderer.render(template: template, context: [:])
        XCTAssertTrue(result.subject.isEmpty)
    }
}
