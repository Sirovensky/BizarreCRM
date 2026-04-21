import XCTest
@testable import Reports

// MARK: - ReportModelsTests
// Tests JSON round-trips for every model and derived computed properties.

final class ReportModelsTests: XCTestCase {

    // Models use explicit CodingKeys with snake_case strings — no strategy needed.
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - RevenuePoint

    func test_revenuePoint_roundTrip() throws {
        let original = RevenuePoint(id: 1, date: "2024-01-01", amountCents: 12345, saleCount: 7)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RevenuePoint.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.date, original.date)
        XCTAssertEqual(decoded.amountCents, original.amountCents)
        XCTAssertEqual(decoded.saleCount, original.saleCount)
    }

    func test_revenuePoint_amountDollars() {
        let pt = RevenuePoint(id: 1, date: "2024-01-01", amountCents: 10050, saleCount: 3)
        XCTAssertEqual(pt.amountDollars, 100.50, accuracy: 0.001)
    }

    // MARK: - TicketStatusPoint

    func test_ticketStatusPoint_roundTrip() throws {
        let original = TicketStatusPoint(id: 2, status: "Closed", count: 42)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TicketStatusPoint.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.count, original.count)
    }

    // MARK: - AvgTicketValue

    func test_avgTicketValue_roundTrip() throws {
        let original = AvgTicketValue(currentCents: 7500, previousCents: 6800, trendPct: 10.3)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AvgTicketValue.self, from: data)
        XCTAssertEqual(decoded.currentCents, original.currentCents)
        XCTAssertEqual(decoded.previousCents, original.previousCents)
        XCTAssertEqual(decoded.trendPct, original.trendPct, accuracy: 0.001)
    }

    func test_avgTicketValue_dollars() {
        let atv = AvgTicketValue(currentCents: 9999, previousCents: 5000, trendPct: -5.0)
        XCTAssertEqual(atv.currentDollars,  99.99, accuracy: 0.001)
        XCTAssertEqual(atv.previousDollars, 50.00, accuracy: 0.001)
    }

    // MARK: - EmployeePerf

    func test_employeePerf_roundTrip() throws {
        let original = EmployeePerf(id: 3, employeeName: "Bob Smith", ticketsClosed: 15,
                                    revenueCents: 450000, avgResolutionHours: 3.5)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(EmployeePerf.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.employeeName, original.employeeName)
        XCTAssertEqual(decoded.ticketsClosed, original.ticketsClosed)
        XCTAssertEqual(decoded.revenueCents, original.revenueCents)
        XCTAssertEqual(decoded.avgResolutionHours, original.avgResolutionHours, accuracy: 0.001)
    }

    func test_employeePerf_revenueDollars() {
        let emp = EmployeePerf(id: 1, employeeName: "A", ticketsClosed: 1, revenueCents: 100_00, avgResolutionHours: 1.0)
        XCTAssertEqual(emp.revenueDollars, 100.0, accuracy: 0.001)
    }

    // MARK: - InventoryTurnoverRow

    func test_inventoryTurnoverRow_roundTrip() throws {
        let original = InventoryTurnoverRow(id: 4, sku: "ABC-123", name: "Battery",
                                             turnoverRate: 4.2, daysOnHand: 87.5)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(InventoryTurnoverRow.self, from: data)
        XCTAssertEqual(decoded.sku, original.sku)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.turnoverRate, original.turnoverRate, accuracy: 0.001)
        XCTAssertEqual(decoded.daysOnHand, original.daysOnHand, accuracy: 0.001)
    }

    // MARK: - CSATScore

    func test_csatScore_roundTrip() throws {
        let original = CSATScore(current: 4.7, previous: 4.3, responseCount: 250, trendPct: 9.3)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CSATScore.self, from: data)
        XCTAssertEqual(decoded.current, original.current, accuracy: 0.001)
        XCTAssertEqual(decoded.previous, original.previous, accuracy: 0.001)
        XCTAssertEqual(decoded.responseCount, original.responseCount)
        XCTAssertEqual(decoded.trendPct, original.trendPct, accuracy: 0.001)
    }

    // MARK: - NPSScore

    func test_npsScore_roundTrip() throws {
        let original = NPSScore(current: 65, previous: 58, promoterPct: 72.0,
                                detractorPct: 7.0, themes: ["Fast", "Friendly"])
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(NPSScore.self, from: data)
        XCTAssertEqual(decoded.current, original.current)
        XCTAssertEqual(decoded.previous, original.previous)
        XCTAssertEqual(decoded.promoterPct, original.promoterPct, accuracy: 0.001)
        XCTAssertEqual(decoded.detractorPct, original.detractorPct, accuracy: 0.001)
        XCTAssertEqual(decoded.themes, original.themes)
    }

    func test_npsScore_passivePct_derivedCorrectly() {
        let nps = NPSScore(current: 60, previous: 50, promoterPct: 65.0,
                          detractorPct: 10.0, themes: [])
        XCTAssertEqual(nps.passivePct, 25.0, accuracy: 0.001)
    }

    func test_npsScore_passivePct_clampsToZero() {
        // If promoter+detractor > 100 (bad data), passive clamps to 0.
        let nps = NPSScore(current: 10, previous: 10, promoterPct: 80.0,
                          detractorPct: 30.0, themes: [])
        XCTAssertEqual(nps.passivePct, 0.0)
    }

    // MARK: - DateRangePreset

    func test_dateRangePreset_sevenDays_spansSevenDays() {
        let ref = ISO8601DateFormatter()
        ref.formatOptions = [.withFullDate]
        let now = Date()
        let range = DateRangePreset.sevenDays.dateRange(relativeTo: now)
        let fromDate = ref.date(from: range.from)!
        let diff = now.timeIntervalSince(fromDate)
        XCTAssertEqual(diff / 86400, 7.0, accuracy: 0.5)
    }

    func test_dateRangePreset_thirtyDays() {
        let ref = ISO8601DateFormatter()
        ref.formatOptions = [.withFullDate]
        let now = Date()
        let range = DateRangePreset.thirtyDays.dateRange(relativeTo: now)
        let fromDate = ref.date(from: range.from)!
        let diff = now.timeIntervalSince(fromDate)
        XCTAssertEqual(diff / 86400, 30.0, accuracy: 0.5)
    }

    func test_dateRangePreset_ninetyDays() {
        let ref = ISO8601DateFormatter()
        ref.formatOptions = [.withFullDate]
        let now = Date()
        let range = DateRangePreset.ninetyDays.dateRange(relativeTo: now)
        let fromDate = ref.date(from: range.from)!
        let diff = now.timeIntervalSince(fromDate)
        XCTAssertEqual(diff / 86400, 90.0, accuracy: 0.5)
    }

    // MARK: - ScheduledReport

    func test_scheduledReport_roundTrip() throws {
        let original = ScheduledReport(id: 1, reportType: "revenue", frequency: .monthly,
                                        recipientEmails: ["a@b.com", "c@d.com"],
                                        isActive: true, nextRunAt: "2024-02-01")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ScheduledReport.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.reportType, original.reportType)
        XCTAssertEqual(decoded.frequency, original.frequency)
        XCTAssertEqual(decoded.recipientEmails, original.recipientEmails)
        XCTAssertEqual(decoded.isActive, original.isActive)
        XCTAssertEqual(decoded.nextRunAt, original.nextRunAt)
    }

    func test_scheduleFrequency_allCases() {
        XCTAssertEqual(ScheduleFrequency.allCases.count, 3)
        XCTAssertTrue(ScheduleFrequency.allCases.contains(.daily))
        XCTAssertTrue(ScheduleFrequency.allCases.contains(.weekly))
        XCTAssertTrue(ScheduleFrequency.allCases.contains(.monthly))
    }

    // MARK: - DrillThroughRecord

    func test_drillThroughRecord_roundTrip() throws {
        let original = DrillThroughRecord(id: 99, label: "Sale #99", detail: "iPhone repair", amountCents: 25000)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(DrillThroughRecord.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.detail, original.detail)
        XCTAssertEqual(decoded.amountCents, original.amountCents)
        XCTAssertEqual(decoded.amountDollars, 250.0)
    }

    func test_drillThroughRecord_nilAmountDollars() {
        let r = DrillThroughRecord(id: 1, label: "X", detail: nil, amountCents: nil)
        XCTAssertNil(r.amountDollars)
    }
}
