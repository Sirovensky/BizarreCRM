import XCTest
@testable import Customers
import Networking

// MARK: - CustomerHealthScoreTests (§44)
//
// Tests for CustomerHealthScoreResult.compute(detail:) covering:
//   - server-score path (pass-through + clamping + label mapping)
//   - client-side RFM recency / frequency / monetary pillars
//   - combined scoring and boundary values
//   - recommendation strings
//   - all-nil neutral path

final class CustomerHealthScoreTests: XCTestCase {

    // MARK: - Server-score path

    func test_serverScore_70_isGreen() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 70))
        XCTAssertEqual(result.value, 70)
        XCTAssertEqual(result.tier, .green)
    }

    func test_serverScore_100_isGreen() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 100))
        XCTAssertEqual(result.value, 100)
        XCTAssertEqual(result.tier, .green)
    }

    func test_serverScore_69_isYellow() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 69))
        XCTAssertEqual(result.tier, .yellow)
    }

    func test_serverScore_40_isYellow() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 40))
        XCTAssertEqual(result.tier, .yellow)
    }

    func test_serverScore_39_isRed() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 39))
        XCTAssertEqual(result.tier, .red)
    }

    func test_serverScore_0_isRed() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 0))
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.tier, .red)
    }

    func test_serverScore_clampedAbove100() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 150))
        XCTAssertEqual(result.value, 100)
        XCTAssertEqual(result.tier, .green)
    }

    func test_serverScore_clampedBelowZero() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: -20))
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.tier, .red)
    }

    func test_serverScore_healthLabel_champion() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 90, healthLabel: "champion"))
        XCTAssertEqual(result.label, .champion)
    }

    func test_serverScore_healthLabel_atRisk() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 30, healthLabel: "at_risk"))
        XCTAssertEqual(result.label, .atRisk)
    }

    func test_serverScore_unknownLabel_isNil() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 50, healthLabel: "unknown_label"))
        XCTAssertNil(result.label)
    }

    // MARK: - All-nil → neutral 50

    func test_allFieldsNil_returnsNeutral50() {
        let result = CustomerHealthScoreResult.compute(detail: makeClientDetail())
        XCTAssertEqual(result.value, 50)
        XCTAssertEqual(result.tier, .yellow)
        XCTAssertNil(result.recommendation)
    }

    // MARK: - Recency pillar

    func test_recency_within30days_earns40pts() {
        let result = CustomerHealthScoreResult.recencyPoints(for: makeClientDetail(lastVisitAt: daysAgoISO(15)))
        XCTAssertEqual(result, 40)
    }

    func test_recency_within60days_earns30pts() {
        let result = CustomerHealthScoreResult.recencyPoints(for: makeClientDetail(lastVisitAt: daysAgoISO(45)))
        XCTAssertEqual(result, 30)
    }

    func test_recency_within90days_earns20pts() {
        let result = CustomerHealthScoreResult.recencyPoints(for: makeClientDetail(lastVisitAt: daysAgoISO(75)))
        XCTAssertEqual(result, 20)
    }

    func test_recency_within180days_earns10pts() {
        let result = CustomerHealthScoreResult.recencyPoints(for: makeClientDetail(lastVisitAt: daysAgoISO(120)))
        XCTAssertEqual(result, 10)
    }

    func test_recency_beyond180days_earns0pts() {
        let result = CustomerHealthScoreResult.recencyPoints(for: makeClientDetail(lastVisitAt: daysAgoISO(200)))
        XCTAssertEqual(result, 0)
    }

    func test_recency_nilDate_earns0pts() {
        let result = CustomerHealthScoreResult.recencyPoints(for: makeClientDetail())
        XCTAssertEqual(result, 0)
    }

    // MARK: - Frequency pillar (via openTicketCount proxy)

    func test_frequency_10tickets_earns30pts() {
        let result = CustomerHealthScoreResult.frequencyPoints(for: makeClientDetail(openTicketCount: 10))
        XCTAssertEqual(result, 30)
    }

    func test_frequency_5tickets_earns25pts() {
        let result = CustomerHealthScoreResult.frequencyPoints(for: makeClientDetail(openTicketCount: 5))
        XCTAssertEqual(result, 25)
    }

    func test_frequency_3tickets_earns15pts() {
        let result = CustomerHealthScoreResult.frequencyPoints(for: makeClientDetail(openTicketCount: 3))
        XCTAssertEqual(result, 15)
    }

    func test_frequency_1ticket_earns5pts() {
        let result = CustomerHealthScoreResult.frequencyPoints(for: makeClientDetail(openTicketCount: 1))
        XCTAssertEqual(result, 5)
    }

    func test_frequency_0tickets_earns0pts() {
        let result = CustomerHealthScoreResult.frequencyPoints(for: makeClientDetail(openTicketCount: 0))
        XCTAssertEqual(result, 0)
    }

    // MARK: - Monetary pillar

    func test_monetary_1000dollars_earns30pts() {
        let result = CustomerHealthScoreResult.monetaryPoints(for: makeClientDetail(totalSpentCents: 100_000))
        XCTAssertEqual(result, 30)
    }

    func test_monetary_500dollars_earns25pts() {
        let result = CustomerHealthScoreResult.monetaryPoints(for: makeClientDetail(totalSpentCents: 50_000))
        XCTAssertEqual(result, 25)
    }

    func test_monetary_200dollars_earns15pts() {
        let result = CustomerHealthScoreResult.monetaryPoints(for: makeClientDetail(totalSpentCents: 20_000))
        XCTAssertEqual(result, 15)
    }

    func test_monetary_50dollars_earns5pts() {
        let result = CustomerHealthScoreResult.monetaryPoints(for: makeClientDetail(totalSpentCents: 5_000))
        XCTAssertEqual(result, 5)
    }

    func test_monetary_49dollars_earns0pts() {
        let result = CustomerHealthScoreResult.monetaryPoints(for: makeClientDetail(totalSpentCents: 4_900))
        XCTAssertEqual(result, 0)
    }

    func test_monetary_nil_earns0pts() {
        let result = CustomerHealthScoreResult.monetaryPoints(for: makeClientDetail())
        XCTAssertEqual(result, 0)
    }

    // MARK: - Combined score clamping

    func test_combinedScore_isClampedAbove100() {
        // Max recency (40) + max frequency (30) + max monetary (30) = 100
        let d = makeClientDetail(
            lastVisitAt: daysAgoISO(5),
            openTicketCount: 20,
            totalSpentCents: 500_000
        )
        let result = CustomerHealthScoreResult.compute(detail: d)
        XCTAssertEqual(result.value, 100)
    }

    func test_combinedScore_isClampedAtZero() {
        // All zeroes → 0
        let d = makeClientDetail(
            lastVisitAt: daysAgoISO(300),
            openTicketCount: 0,
            totalSpentCents: 0
        )
        let result = CustomerHealthScoreResult.compute(detail: d)
        XCTAssertGreaterThanOrEqual(result.value, 0)
    }

    // MARK: - Recommendations

    func test_recommendation_complaint_takesPriority() {
        let d = makeClientDetail(lastVisitAt: daysAgoISO(5), complaintCount: 1)
        let result = CustomerHealthScoreResult.compute(detail: d)
        XCTAssertEqual(result.recommendation, "Open complaint awaiting response.")
    }

    func test_recommendation_oldVisit_givesFollowUp() {
        let d = makeClientDetail(lastVisitAt: daysAgoISO(200), totalSpentCents: 100_000)
        let result = CustomerHealthScoreResult.compute(detail: d)
        XCTAssertEqual(result.recommendation, "Haven't seen in 180 days — send follow-up.")
    }

    func test_recommendation_recentCustomer_returnsNil() {
        let d = makeClientDetail(lastVisitAt: daysAgoISO(10), totalSpentCents: 20_000)
        let result = CustomerHealthScoreResult.compute(detail: d)
        XCTAssertNil(result.recommendation)
    }

    // MARK: - Components populated on client-side path

    func test_clientPath_populatesComponents() {
        let d = makeClientDetail(
            lastVisitAt: daysAgoISO(10),
            openTicketCount: 5,
            totalSpentCents: 100_000
        )
        let result = CustomerHealthScoreResult.compute(detail: d)
        XCTAssertNotNil(result.components)
        XCTAssertEqual(result.components?.recencyPoints, 40)
        XCTAssertEqual(result.components?.frequencyPoints, 25)
        XCTAssertEqual(result.components?.monetaryPoints, 30)
    }

    func test_serverPath_doesNotPopulateComponents() {
        let result = CustomerHealthScoreResult.compute(detail: makeDetail(serverScore: 80))
        XCTAssertNil(result.components)
    }
}

// MARK: - Helpers

private func makeDetail(serverScore: Int, healthLabel: String? = nil) -> CustomerDetail {
    var fields = ["\"id\": 1", "\"health_score\": \(serverScore)"]
    if let label = healthLabel { fields.append("\"health_label\": \"\(label)\"") }
    return decode(fields)
}

private func makeClientDetail(
    lastVisitAt: String? = nil,
    openTicketCount: Int? = nil,
    complaintCount: Int? = nil,
    totalSpentCents: Int64? = nil
) -> CustomerDetail {
    var fields = ["\"id\": 1"]
    if let v = lastVisitAt     { fields.append("\"last_visit_at\": \"\(v)\"") }
    if let v = openTicketCount  { fields.append("\"open_ticket_count\": \(v)") }
    if let v = complaintCount  { fields.append("\"complaint_count\": \(v)") }
    if let v = totalSpentCents { fields.append("\"total_spent_cents\": \(v)") }
    return decode(fields)
}

private func decode(_ fields: [String]) -> CustomerDetail {
    let json = "{\(fields.joined(separator: ", "))}".data(using: .utf8)!
    return try! JSONDecoder().decode(CustomerDetail.self, from: json)
}

private func daysAgo(_ n: Int) -> Date {
    Date().addingTimeInterval(-Double(n) * 86_400)
}

private func daysAgoISO(_ n: Int) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: daysAgo(n))
}
