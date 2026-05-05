import XCTest
@testable import Communications

// MARK: - TemplateRendererTests
// TDD: written before TemplateRenderer was implemented.

final class TemplateRendererTests: XCTestCase {

    // MARK: - render: no variables

    func test_render_noVariables_returnsOriginal() {
        let body = "Hello, we'll be in touch soon."
        let result = TemplateRenderer.render(body, variables: .init())
        XCTAssertEqual(result, body)
    }

    // MARK: - render: single substitution

    func test_render_firstName_substituted() {
        let body = "Hi {first_name}, your ticket is ready."
        let result = TemplateRenderer.render(body, variables: .init(firstName: "Alice"))
        XCTAssertEqual(result, "Hi Alice, your ticket is ready.")
    }

    func test_render_lastName_substituted() {
        let body = "Dear {last_name},"
        let result = TemplateRenderer.render(body, variables: .init(lastName: "Smith"))
        XCTAssertEqual(result, "Dear Smith,")
    }

    func test_render_ticketNo_substituted() {
        let body = "Your ticket {ticket_no} is complete."
        let result = TemplateRenderer.render(body, variables: .init(ticketNo: "TKT-007"))
        XCTAssertEqual(result, "Your ticket TKT-007 is complete.")
    }

    func test_render_amount_substituted() {
        let body = "Total due: {amount}"
        let result = TemplateRenderer.render(body, variables: .init(amount: "$99.99"))
        XCTAssertEqual(result, "Total due: $99.99")
    }

    func test_render_date_substituted() {
        let body = "Scheduled for {date}."
        let result = TemplateRenderer.render(body, variables: .init(date: "Jan 15"))
        XCTAssertEqual(result, "Scheduled for Jan 15.")
    }

    func test_render_company_substituted() {
        let body = "Hi {company} team!"
        let result = TemplateRenderer.render(body, variables: .init(company: "Acme"))
        XCTAssertEqual(result, "Hi Acme team!")
    }

    // MARK: - render: multiple substitutions

    func test_render_multipleVariables() {
        let body = "Hi {first_name} {last_name}, ticket #{ticket_no} — total {amount}."
        let result = TemplateRenderer.render(body, variables: .init(
            firstName: "Jane",
            lastName: "Doe",
            ticketNo: "TKT-42",
            amount: "$149"
        ))
        XCTAssertEqual(result, "Hi Jane Doe, ticket #TKT-42 — total $149.")
    }

    // MARK: - render: nil variable leaves placeholder

    func test_render_nilVariable_keepPlaceholder() {
        let body = "Hi {first_name}!"
        let result = TemplateRenderer.render(body, variables: .init(firstName: nil))
        XCTAssertEqual(result, "Hi {first_name}!")
    }

    // MARK: - render: unknown variable untouched

    func test_render_unknownVariable_unchanged() {
        let body = "Track at {custom_url}"
        let result = TemplateRenderer.render(body, variables: .sample)
        XCTAssertEqual(result, "Track at {custom_url}")
    }

    // MARK: - render: empty body

    func test_render_emptyBody_returnsEmpty() {
        let result = TemplateRenderer.render("", variables: .sample)
        XCTAssertEqual(result, "")
    }

    // MARK: - render: sample data

    func test_render_sampleData_noPlaceholdersRemain() {
        let body = "{first_name} {last_name} — {ticket_no} — {company} — {amount} — {date}"
        let result = TemplateRenderer.render(body, variables: .sample)
        XCTAssertFalse(result.contains("{first_name}"))
        XCTAssertFalse(result.contains("{last_name}"))
        XCTAssertFalse(result.contains("{ticket_no}"))
        XCTAssertFalse(result.contains("{company}"))
        XCTAssertFalse(result.contains("{amount}"))
        XCTAssertFalse(result.contains("{date}"))
    }

    // MARK: - extractVariables

    func test_extractVariables_findsAllTokens() {
        let body = "Hi {first_name}, your ticket {ticket_no} is ready. Total: {amount}."
        let vars = TemplateRenderer.extractVariables(from: body)
        XCTAssertTrue(vars.contains("{first_name}"))
        XCTAssertTrue(vars.contains("{ticket_no}"))
        XCTAssertTrue(vars.contains("{amount}"))
        XCTAssertEqual(vars.count, 3)
    }

    func test_extractVariables_emptyBody_returnsEmpty() {
        let vars = TemplateRenderer.extractVariables(from: "No placeholders here.")
        XCTAssertTrue(vars.isEmpty)
    }

    func test_extractVariables_duplicates_returnsBoth() {
        let body = "{first_name} and {first_name}"
        let vars = TemplateRenderer.extractVariables(from: body)
        XCTAssertEqual(vars.count, 2)
    }
}
