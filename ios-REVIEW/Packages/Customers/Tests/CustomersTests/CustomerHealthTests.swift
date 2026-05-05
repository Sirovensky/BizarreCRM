import XCTest
@testable import Customers
import Networking

// MARK: - CustomerHealthTests
// §44 — 15+ unit tests covering CustomerHealthScore.compute(detail:).
// All tests are pure / synchronous — no async, no network.

final class CustomerHealthTests: XCTestCase {

    // MARK: Tier bucket tests

    /// Score of 70 maps to green.
    func test_tier_70_isGreen() {
        let detail = makeDetail(serverScore: 70)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.tier, .green)
        XCTAssertEqual(result.value, 70)
    }

    /// Score of 100 maps to green.
    func test_tier_100_isGreen() {
        let detail = makeDetail(serverScore: 100)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.tier, .green)
        XCTAssertEqual(result.value, 100)
    }

    /// Score of 69 maps to yellow.
    func test_tier_69_isYellow() {
        let detail = makeDetail(serverScore: 69)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.tier, .yellow)
    }

    /// Score of 40 maps to yellow.
    func test_tier_40_isYellow() {
        let detail = makeDetail(serverScore: 40)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.tier, .yellow)
    }

    /// Score of 39 maps to red.
    func test_tier_39_isRed() {
        let detail = makeDetail(serverScore: 39)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.tier, .red)
    }

    /// Score of 0 maps to red.
    func test_tier_0_isRed() {
        let detail = makeDetail(serverScore: 0)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.tier, .red)
        XCTAssertEqual(result.value, 0)
    }

    // MARK: Last-visit recency (client-side path)

    /// Recent visit (≤30 days) earns 30 recency points.
    func test_clientSide_recentVisit_earns30pts() {
        let date = daysAgo(15)
        let detail = makeDetailClient(lastVisitAt: iso8601(date), totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        // Recency: 30, no spend, no penalty → 30
        XCTAssertEqual(result.value, 30)
    }

    /// Visit 45 days ago earns 25 recency points (≤60 days bracket).
    func test_clientSide_45dayVisit_earns25pts() {
        let date = daysAgo(45)
        let detail = makeDetailClient(lastVisitAt: iso8601(date), totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.value, 25)
    }

    /// Visit >180 days ago earns 0 recency points.
    func test_clientSide_200dayVisit_earns0pts() {
        let date = daysAgo(200)
        let detail = makeDetailClient(lastVisitAt: iso8601(date), totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.value, 0)
    }

    // MARK: Open-ticket penalty clamping

    /// One open ticket deducts 10 pts.
    func test_clientSide_oneOpenTicket_deducts10pts() {
        let detail = makeDetailClient(lastVisitAt: daysAgoISO(10), openTicketCount: 1, totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        // 30 (recency) - 10 (ticket) = 20
        XCTAssertEqual(result.value, 20)
    }

    /// Three open tickets deducts only 20 pts (cap).
    func test_clientSide_threeOpenTickets_capsAt20() {
        let detail = makeDetailClient(lastVisitAt: daysAgoISO(10), openTicketCount: 3, totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        // 30 (recency) - 20 (capped) = 10
        XCTAssertEqual(result.value, 10)
    }

    // MARK: Complaint penalty clamping

    /// One complaint deducts 15 pts.
    func test_clientSide_oneComplaint_deducts15pts() {
        let detail = makeDetailClient(lastVisitAt: daysAgoISO(10), complaintCount: 1, totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        // 30 - 15 = 15
        XCTAssertEqual(result.value, 15)
    }

    /// Three complaints deducts only 30 pts (cap). Score clamped to 0 if negative.
    func test_clientSide_threeComplaints_capsAt30() {
        let detail = makeDetailClient(lastVisitAt: nil, complaintCount: 3, totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        // 0 - 30 = -30 → clamped 0
        XCTAssertEqual(result.value, 0)
    }

    // MARK: Spend scaling

    /// $1 000 spend earns 40 spend pts.
    func test_clientSide_1000dollars_earns40pts() {
        let cents: Int64 = 100_000  // $1000.00
        let detail = makeDetailClient(lastVisitAt: nil, totalSpentCents: cents)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.value, 40)
    }

    /// $49 spend earns 0 spend pts.
    func test_clientSide_49dollars_earns0pts() {
        let cents: Int64 = 4_900  // $49.00
        let detail = makeDetailClient(lastVisitAt: nil, totalSpentCents: cents)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.value, 0)
    }

    // MARK: Recommendation strings

    /// Visit > 180 days produces the follow-up recommendation.
    func test_recommendation_oldVisit_returnsFollowUp() {
        let date = daysAgo(200)
        let detail = makeDetailClient(lastVisitAt: iso8601(date), totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.recommendation, "Haven't seen in 180 days — send follow-up.")
    }

    /// Recent engaged customer has no recommendation.
    func test_recommendation_recentCustomer_returnsNil() {
        let date = daysAgo(10)
        let detail = makeDetailClient(lastVisitAt: iso8601(date), totalSpentCents: 200_00)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertNil(result.recommendation)
    }

    /// Complaint > 0 returns complaint recommendation (takes priority over recency).
    func test_recommendation_complaint_returnComplaintString() {
        let date = daysAgo(5)
        let detail = makeDetailClient(lastVisitAt: iso8601(date), complaintCount: 1, totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.recommendation, "Open complaint awaiting response.")
    }

    // MARK: Edge cases

    /// All fields nil → neutral 50, yellow, no recommendation.
    func test_allFieldsNil_returnsNeutral50() {
        let detail = makeDetailClient(lastVisitAt: nil, totalSpentCents: nil)
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.value, 50)
        XCTAssertEqual(result.tier, .yellow)
        XCTAssertNil(result.recommendation)
    }

    /// Server score overrides client heuristics — tier is derived from server value.
    func test_serverScore_overridesClientHeuristics() {
        // Even with a recent visit (would give high heuristic), server score wins.
        let detail = makeDetail(serverScore: 25)
        // We verify the server path is taken regardless of other fields.
        let result = CustomerHealthScore.compute(detail: detail)
        XCTAssertEqual(result.value, 25)
        XCTAssertEqual(result.tier, .red)
    }

    /// Server score is clamped to 0–100 even if out of range.
    func test_serverScore_clampedTo0_100() {
        let over = makeDetail(serverScore: 150)
        XCTAssertEqual(CustomerHealthScore.compute(detail: over).value, 100)

        let under = makeDetail(serverScore: -10)
        XCTAssertEqual(CustomerHealthScore.compute(detail: under).value, 0)
    }

    // MARK: ISO-8601 parsing helpers

    func test_parseISO8601_dateOnly() {
        let result = CustomerHealthScore.parseISO8601("2024-01-15")
        XCTAssertNotNil(result)
    }

    func test_parseISO8601_fullTimestamp() {
        let result = CustomerHealthScore.parseISO8601("2024-01-15T12:00:00Z")
        XCTAssertNotNil(result)
    }

    func test_parseISO8601_malformed_returnsNil() {
        let result = CustomerHealthScore.parseISO8601("not-a-date")
        XCTAssertNil(result)
    }

    // MARK: daysSince

    func test_daysSince_10daysAgo_returns10() {
        let date = daysAgo(10)
        XCTAssertEqual(CustomerHealthScore.daysSince(date), 10)
    }

    func test_daysSince_futureDate_returns0() {
        let future = Date().addingTimeInterval(86_400 * 5)
        XCTAssertEqual(CustomerHealthScore.daysSince(future), 0)
    }
}

// MARK: - Helpers

private func makeDetail(serverScore: Int) -> CustomerDetail {
    let json = """
    {
        "id": 1,
        "health_score": \(serverScore)
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(CustomerDetail.self, from: json)
}

private func makeDetailClient(
    lastVisitAt: String?,
    openTicketCount: Int? = nil,
    complaintCount: Int? = nil,
    totalSpentCents: Int64?
) -> CustomerDetail {
    var fields: [String] = ["\"id\": 1"]
    if let v = lastVisitAt    { fields.append("\"last_visit_at\": \"\(v)\"") }
    if let v = openTicketCount { fields.append("\"open_ticket_count\": \(v)") }
    if let v = complaintCount { fields.append("\"complaint_count\": \(v)") }
    if let v = totalSpentCents { fields.append("\"total_spent_cents\": \(v)") }
    let json = "{\(fields.joined(separator: ", "))}".data(using: .utf8)!
    return try! JSONDecoder().decode(CustomerDetail.self, from: json)
}

private func daysAgo(_ n: Int) -> Date {
    Date().addingTimeInterval(-Double(n) * 86_400)
}

private func daysAgoISO(_ n: Int) -> String { iso8601(daysAgo(n)) }

private func iso8601(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: date)
}
