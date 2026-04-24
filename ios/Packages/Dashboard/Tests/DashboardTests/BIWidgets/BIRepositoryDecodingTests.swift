import XCTest
@testable import Dashboard

// MARK: - BIRepositoryDecodingTests
//
// Verifies every model in DashboardBIRepository decodes from server-shaped JSON.

final class BIRepositoryDecodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - RevenueTrendPoint

    func test_revenueTrendPoint_decodesCorrectly() throws {
        let json = #"{"month":"2025-01","revenue":1234.56}"#.data(using: .utf8)!
        let point = try decoder.decode(RevenueTrendPoint.self, from: json)
        XCTAssertEqual(point.month, "2025-01")
        XCTAssertEqual(point.revenue, 1234.56, accuracy: 0.001)
        XCTAssertEqual(point.id, "2025-01")
    }

    func test_revenueTrendPoint_missingFieldsDefaultsToZero() throws {
        let json = #"{}"#.data(using: .utf8)!
        let point = try decoder.decode(RevenueTrendPoint.self, from: json)
        XCTAssertEqual(point.month, "")
        XCTAssertEqual(point.revenue, 0)
    }

    // MARK: - TicketStatusCount

    func test_ticketStatusCount_decodesCorrectly() throws {
        let jsonStr = "{\"id\":3,\"name\":\"In Progress\",\"color\":\"#FF6B35\",\"count\":17,\"is_closed\":false,\"is_cancelled\":false}"
        let json = jsonStr.data(using: .utf8)!
        let status = try decoder.decode(TicketStatusCount.self, from: json)
        XCTAssertEqual(status.id, 3)
        XCTAssertEqual(status.name, "In Progress")
        XCTAssertEqual(status.color, "#FF6B35")
        XCTAssertEqual(status.count, 17)
        XCTAssertFalse(status.isClosed)
    }

    func test_ticketStatusCount_missingOptionalColor() throws {
        let json = #"{"id":1,"name":"Open","count":5}"#.data(using: .utf8)!
        let status = try decoder.decode(TicketStatusCount.self, from: json)
        XCTAssertNil(status.color)
        XCTAssertEqual(status.count, 5)
    }

    // MARK: - DashboardSummaryPayload

    func test_dashboardSummaryPayload_decodesRevenueTrendAndStatusCounts() throws {
        let json = #"""
        {"revenue_trend":[{"month":"2024-12","revenue":8000},{"month":"2025-01","revenue":9500}],
         "status_counts":[{"id":1,"name":"Open","count":12},{"id":2,"name":"Closed","count":5,"is_closed":true}]}
        """#.data(using: .utf8)!
        let payload = try decoder.decode(DashboardSummaryPayload.self, from: json)
        XCTAssertEqual(payload.revenueTrend.count, 2)
        XCTAssertEqual(payload.revenueTrend[1].revenue, 9500)
        XCTAssertEqual(payload.statusCounts.count, 2)
        XCTAssertTrue(payload.statusCounts[1].isClosed)
    }

    func test_dashboardSummaryPayload_emptyArraysWhenKeysMissing() throws {
        let payload = try decoder.decode(DashboardSummaryPayload.self, from: #"{}"#.data(using: .utf8)!)
        XCTAssertTrue(payload.revenueTrend.isEmpty)
        XCTAssertTrue(payload.statusCounts.isEmpty)
    }

    // MARK: - TechLeaderboardPayload

    func test_techLeaderboardPayload_decodesLeaderboard() throws {
        let json = #"""
        {"period":"month","leaderboard":[
          {"user_id":1,"name":"Alice Smith","tickets_closed":42,"revenue":18000,"csat_avg":9.2},
          {"user_id":2,"name":"Bob Jones","tickets_closed":31,"revenue":12500}
        ]}
        """#.data(using: .utf8)!
        let payload = try decoder.decode(TechLeaderboardPayload.self, from: json)
        XCTAssertEqual(payload.period, "month")
        XCTAssertEqual(payload.leaderboard.count, 2)
        XCTAssertEqual(payload.leaderboard[0].csatAvg, 9.2, accuracy: 0.01)
        XCTAssertNil(payload.leaderboard[1].csatAvg)
    }

    func test_techLeaderboardPayload_emptyLeaderboard() throws {
        let payload = try decoder.decode(TechLeaderboardPayload.self, from: #"{"period":"week","leaderboard":[]}"#.data(using: .utf8)!)
        XCTAssertTrue(payload.leaderboard.isEmpty)
    }

    // MARK: - RepeatCustomersPayload

    func test_repeatCustomersPayload_decodesTop() throws {
        let json = #"""
        {"top":[{"customer_id":10,"name":"Jane Doe","ticket_count":8,"total_spent":3200,"share_pct":5.1}],
         "combined_share_pct":5.1,"total_revenue":62745.00}
        """#.data(using: .utf8)!
        let payload = try decoder.decode(RepeatCustomersPayload.self, from: json)
        XCTAssertEqual(payload.top.count, 1)
        XCTAssertEqual(payload.top[0].totalSpent, 3200, accuracy: 0.01)
        XCTAssertEqual(payload.combinedSharePct, 5.1, accuracy: 0.01)
    }

    func test_repeatCustomersPayload_emptyTop() throws {
        let payload = try decoder.decode(RepeatCustomersPayload.self, from: #"{"top":[],"combined_share_pct":0,"total_revenue":0}"#.data(using: .utf8)!)
        XCTAssertTrue(payload.top.isEmpty)
    }

    // MARK: - CashTrappedPayload

    func test_cashTrappedPayload_decodes() throws {
        let json = #"""
        {"total_cash_trapped":4800.00,"item_count":12,
         "top_offenders":[{"id":5,"name":"Battery 3000mAh","category":"Batteries","in_stock":20,"value":400.00}]}
        """#.data(using: .utf8)!
        let payload = try decoder.decode(CashTrappedPayload.self, from: json)
        XCTAssertEqual(payload.totalCashTrapped, 4800, accuracy: 0.01)
        XCTAssertEqual(payload.itemCount, 12)
        XCTAssertEqual(payload.topOffenders[0].name, "Battery 3000mAh")
    }

    func test_cashTrappedPayload_emptyOffenders() throws {
        let payload = try decoder.decode(CashTrappedPayload.self, from: #"{"total_cash_trapped":0,"item_count":0,"top_offenders":[]}"#.data(using: .utf8)!)
        XCTAssertTrue(payload.topOffenders.isEmpty)
    }

    // MARK: - ChurnPayload

    func test_churnPayload_decodes() throws {
        let json = #"""
        {"threshold_days":90,"at_risk_count":34,
         "customers":[{"customer_id":7,"name":"Mark T","days_inactive":120,"lifetime_spent":1500}]}
        """#.data(using: .utf8)!
        let payload = try decoder.decode(ChurnPayload.self, from: json)
        XCTAssertEqual(payload.atRiskCount, 34)
        XCTAssertEqual(payload.customers[0].daysInactive, 120)
    }

    func test_churnPayload_emptyCustomers() throws {
        let payload = try decoder.decode(ChurnPayload.self, from: #"{"threshold_days":90,"at_risk_count":0,"customers":[]}"#.data(using: .utf8)!)
        XCTAssertEqual(payload.atRiskCount, 0)
        XCTAssertTrue(payload.customers.isEmpty)
    }

    // MARK: - TopServiceEntry

    func test_topServiceEntry_decodes() throws {
        let json = #"{"name":"Screen Replacement","count":120,"revenue":6000.0}"#.data(using: .utf8)!
        let entry = try decoder.decode(TopServiceEntry.self, from: json)
        XCTAssertEqual(entry.name, "Screen Replacement")
        XCTAssertEqual(entry.count, 120)
        XCTAssertEqual(entry.revenue, 6000, accuracy: 0.01)
        XCTAssertEqual(entry.id, "Screen Replacement")
    }

    func test_topServiceEntry_missingFieldsDefault() throws {
        let entry = try decoder.decode(TopServiceEntry.self, from: #"{}"#.data(using: .utf8)!)
        XCTAssertEqual(entry.name, "")
        XCTAssertEqual(entry.count, 0)
        XCTAssertEqual(entry.revenue, 0)
    }
}
