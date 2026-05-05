import Testing
@testable import Customers

// MARK: - §5.7 Suggested tags behavior tests

@Suite("CustomerSuggestedTagsService")
struct CustomerSuggestedTagsServiceTests {
    let service = CustomerSuggestedTagsService()

    @Test("suggests late-payer after 3 overdue invoices")
    func suggestsLatePayer() {
        let tags = service.suggestions(overdueInvoiceCount: 3)
        #expect(tags.map(\.tag).contains("late-payer"))
    }

    @Test("does not suggest late-payer below threshold")
    func noLatePayerBelowThreshold() {
        let tags = service.suggestions(overdueInvoiceCount: 2)
        #expect(!tags.map(\.tag).contains("late-payer"))
    }

    @Test("skips tag already present")
    func skipsExistingTag() {
        let tags = service.suggestions(
            overdueInvoiceCount: 5,
            existingTags: ["late-payer"]
        )
        #expect(!tags.map(\.tag).contains("late-payer"))
    }

    @Test("suggests vip when LTV over threshold")
    func suggestsVIP() {
        let tags = service.suggestions(ltvCents: 50_000)
        #expect(tags.map(\.tag).contains("vip"))
    }

    @Test("does not suggest vip below threshold")
    func noVIPBelowThreshold() {
        let tags = service.suggestions(ltvCents: 49_999)
        #expect(!tags.map(\.tag).contains("vip"))
    }

    @Test("suggests at-risk after 180 days since last visit")
    func suggestsAtRisk() {
        let tags = service.suggestions(daysSinceLastVisit: 181)
        #expect(tags.map(\.tag).contains("at-risk"))
    }

    @Test("does not suggest at-risk when visit recent")
    func noAtRiskRecent() {
        let tags = service.suggestions(daysSinceLastVisit: 90)
        #expect(!tags.map(\.tag).contains("at-risk"))
    }

    @Test("suggests frequent after 10 tickets")
    func suggestsFrequent() {
        let tags = service.suggestions(ticketCount: 10)
        #expect(tags.map(\.tag).contains("frequent"))
    }

    @Test("suggests returning with 5-9 tickets (not frequent)")
    func suggestsReturning() {
        let tags = service.suggestions(ticketCount: 5)
        #expect(tags.map(\.tag).contains("returning"))
        #expect(!tags.map(\.tag).contains("frequent"))
    }

    @Test("suggests new on first ticket")
    func suggestsNew() {
        let tags = service.suggestions(ticketCount: 1)
        #expect(tags.map(\.tag).contains("new"))
    }

    @Test("suggests high-value on large average ticket")
    func suggestsHighValue() {
        let tags = service.suggestions(averageTicketCents: 20_000)
        #expect(tags.map(\.tag).contains("high-value"))
    }

    @Test("no suggestions for empty customer")
    func noSuggestionsForEmpty() {
        let tags = service.suggestions()
        #expect(tags.isEmpty)
    }

    @Test("multiple suggestions can be returned")
    func multipleSuggestions() {
        let tags = service.suggestions(
            overdueInvoiceCount: 4,
            ltvCents: 100_000,
            daysSinceLastVisit: 200,
            ticketCount: 15
        )
        #expect(tags.count >= 4)
    }

    @Test("reason string is non-empty")
    func reasonNonEmpty() {
        let tags = service.suggestions(overdueInvoiceCount: 3)
        for tag in tags {
            #expect(!tag.reason.isEmpty)
        }
    }
}
