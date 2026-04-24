import XCTest
@testable import Dashboard
@testable import Networking

// MARK: - DashboardLayoutTests
//
// Tests for pure layout-logic helpers that do not require a running UIKit
// environment. These functions are `internal` in DashboardView.swift so
// they are reachable via `@testable import Dashboard`.

final class DashboardLayoutTests: XCTestCase {

    // MARK: - kpiGridColumnCount

    func test_kpiGridColumnCount_compact_returns1() {
        XCTAssertEqual(kpiGridColumnCount(isCompact: true), 1,
            "iPhone (compact) should use adaptive (represented as 1) column mode")
    }

    func test_kpiGridColumnCount_regular_returns3() {
        XCTAssertEqual(kpiGridColumnCount(isCompact: false), 3,
            "iPad (regular-width) must always show 3 KPI columns per §3 spec")
    }

    // MARK: - attentionItems(from:)

    func test_attentionItems_allZero_returnsAllItems() {
        let attention = NeedsAttention(
            staleTickets: [],
            overdueInvoices: [],
            missingPartsCount: 0,
            lowStockCount: 0
        )
        let items = attentionItems(from: attention)
        // All four categories are always returned (caller decides whether to show card).
        XCTAssertEqual(items.count, 4)
    }

    func test_attentionItems_counts_matchAttentionModel() {
        let ticket = NeedsAttention.StaleTicket(
            id: 1, orderId: "T-001", customerName: "Alice", daysStale: 4, status: "Open"
        )
        let invoice = NeedsAttention.OverdueInvoice(
            id: 2, orderId: "I-001", customerName: "Bob", amountDue: 150.0, daysOverdue: 7
        )
        let attention = NeedsAttention(
            staleTickets: [ticket],
            overdueInvoices: [invoice],
            missingPartsCount: 3,
            lowStockCount: 5
        )
        let items = attentionItems(from: attention)

        let stale    = items.first { $0.label == "Stale tickets" }
        let overdue  = items.first { $0.label == "Overdue invoices" }
        let missing  = items.first { $0.label == "Missing parts" }
        let lowStock = items.first { $0.label == "Low stock" }

        XCTAssertEqual(stale?.count,    1)
        XCTAssertEqual(overdue?.count,  1)
        XCTAssertEqual(missing?.count,  3)
        XCTAssertEqual(lowStock?.count, 5)
    }

    func test_attentionItems_totalZero_cardShouldBeHidden() {
        // The attention card is suppressed when total == 0.
        // This test verifies the sum logic used by the view.
        let attention = NeedsAttention(
            staleTickets: [],
            overdueInvoices: [],
            missingPartsCount: 0,
            lowStockCount: 0
        )
        let items = attentionItems(from: attention)
        let total = items.reduce(0) { $0 + $1.count }
        XCTAssertEqual(total, 0, "No issues → card should be hidden")
    }

    func test_attentionItems_totalNonZero_cardShouldBeVisible() {
        let attention = NeedsAttention(
            staleTickets: [],
            overdueInvoices: [],
            missingPartsCount: 0,
            lowStockCount: 2
        )
        let items = attentionItems(from: attention)
        let total = items.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(total, 0, "Low stock alert → card must be shown")
    }

    func test_attentionItems_labelOrder_isStable() {
        // Labels must always appear in the same order so screen readers and
        // tests get a deterministic sequence.
        let attention = NeedsAttention()
        let items = attentionItems(from: attention)
        let labels = items.map(\.label)
        XCTAssertEqual(labels, ["Stale tickets", "Overdue invoices", "Missing parts", "Low stock"])
    }

    // MARK: - dashboardGreeting(for:)

    func test_greeting_morning() {
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 9)), "Good morning")
    }

    func test_greeting_afternoon() {
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 13)), "Good afternoon")
    }

    func test_greeting_evening() {
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 18)), "Good evening")
    }

    func test_greeting_lateNight() {
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 23)), "Working late")
    }

    func test_greeting_earlyMorning_beforeDawn() {
        // Hour 2 is before 5 — falls through to "Working late"
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 2)), "Working late")
    }

    func test_greeting_noonBoundary() {
        // 12:00 is "Good afternoon", not "Good morning"
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 12)), "Good afternoon")
    }

    func test_greeting_dawnBoundary() {
        // 5:00 is the first minute of "Good morning"
        XCTAssertEqual(dashboardGreeting(for: Self.date(hour: 5)), "Good morning")
    }

    // MARK: - Helpers

    private static func date(hour: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}
