import Testing
import Foundation
@testable import Marketing

// MARK: - §37 Campaign message preview tests

@Suite("CampaignMessagePreview")
struct CampaignMessagePreviewTests {

    // MARK: TemplateVariableRenderer

    @Test("renders single variable substitution")
    func singleVar() {
        let result = TemplateVariableRenderer.render(
            template: "Hello {first_name}!",
            context: ["first_name": "Alex"]
        )
        #expect(result == "Hello Alex!")
    }

    @Test("renders multiple variables")
    func multiVar() {
        let result = TemplateVariableRenderer.render(
            template: "Hi {first_name}, your ticket {ticket_no} is ready.",
            context: ["first_name": "Sam", "ticket_no": "TKT-007"]
        )
        #expect(result == "Hi Sam, your ticket TKT-007 is ready.")
    }

    @Test("leaves unknown variable as-is")
    func unknownVar() {
        let result = TemplateVariableRenderer.render(
            template: "Hi {unknown_var}",
            context: ["first_name": "Alex"]
        )
        #expect(result == "Hi {unknown_var}")
    }

    @Test("renders double-brace variables")
    func doubleBrace() {
        let result = TemplateVariableRenderer.render(
            template: "Hello {{first_name}}!",
            context: ["first_name": "Jordan"]
        )
        #expect(result == "Hello Jordan!")
    }

    @Test("empty template returns empty string")
    func emptyTemplate() {
        let result = TemplateVariableRenderer.render(template: "", context: ["first_name": "X"])
        #expect(result.isEmpty)
    }

    // MARK: SMSSegmentCalculator

    @Test("empty string = 0 segments")
    func emptySegments() {
        #expect(SMSSegmentCalculator.segments(for: "") == 0)
    }

    @Test("short GSM-7 message = 1 segment")
    func shortGSM7() {
        let body = "Hello! Your repair is ready."
        #expect(SMSSegmentCalculator.segments(for: body) == 1)
    }

    @Test("160-char GSM-7 message = 1 segment")
    func exactly160() {
        let body = String(repeating: "A", count: 160)
        #expect(SMSSegmentCalculator.segments(for: body) == 1)
    }

    @Test("161-char GSM-7 message = 2 segments")
    func over160() {
        let body = String(repeating: "A", count: 161)
        #expect(SMSSegmentCalculator.segments(for: body) == 2)
    }

    @Test("306-char GSM-7 message = 2 segments (fits in 2 × 153)")
    func twoSegmentsGSM7() {
        let body = String(repeating: "A", count: 306)
        #expect(SMSSegmentCalculator.segments(for: body) == 2)
    }

    @Test("unicode message under 70 chars = 1 segment")
    func unicodeShort() {
        let body = "Hi! 🎉 Your order is ready."
        #expect(SMSSegmentCalculator.segments(for: body) == 1)
    }

    @Test("unicode message over 70 chars = 2 segments")
    func unicodeLong() {
        // Build a 71-char string with a non-GSM7 character
        let body = String(repeating: "A", count: 70) + "é"
        #expect(SMSSegmentCalculator.segments(for: body) == 2)
    }
}
