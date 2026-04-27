import Foundation
import SwiftUI
import Observation
import Networking

// MARK: - ReportsViewModel

@Observable
@MainActor
public final class ReportsViewModel {

    // MARK: - Sub-tab (§15.1)

    public var selectedSubTab: ReportSubTab = .sales

    // MARK: - Date range

    public var selectedPreset: DateRangePreset = .thirtyDays {
        didSet { if selectedPreset != .custom { applyPreset(selectedPreset) } }
    }
    public var customFrom: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    public var customTo: Date = Date()

    // MARK: - Granularity (day / week / month)
    // Controls the group_by parameter sent to GET /api/v1/reports/sales.
    public var granularity: ReportGranularity = .day

    // MARK: - Data state

    public var revenue: [RevenuePoint] = []
    /// Period-over-period totals from the sales report.
    public var salesTotals: SalesTotals = SalesTotals()
    /// Revenue by payment method.
    public var revenueByMethod: [PaymentMethodPoint] = []
    public var ticketsByStatus: [TicketStatusPoint] = []
    public var avgTicketValue: AvgTicketValue?
    public var employeePerf: [EmployeePerf] = []
    public var inventoryTurnover: [InventoryTurnoverRow] = []
    /// Full inventory report (low stock, value, top moving).
    public var inventoryReport: InventoryReport?
    /// Expenses + daily breakdown.
    public var expensesReport: ExpensesReport?
    public var csatScore: CSATScore?
    public var npsScore: NPSScore?
    public var lastSyncedAt: Date?
    /// §15.4 Technician performance (GET /reports/technician-performance)
    public var technicianPerf: [TechnicianPerfRow] = []
    /// §15.6 Tax report (GET /reports/tax)
    public var taxReport: TaxReportResponse?
    public var taxReportLoading: Bool = false

    // MARK: - §15.2 YoY growth + top customers
    public var yoyPoints: [YoYDataPoint] = []
    public var topCustomers: [TopCustomerRow] = []

    // MARK: - §15.3 Tickets trend (opened/closed per day)
    public var ticketsTrend: [TicketDayPoint] = []
    /// §15.3 Tickets by tech (derived from employeePerf)
    public var ticketsByTech: [TicketsByTechPoint] {
        employeePerf.map { TicketsByTechPoint(from: $0) }
    }
    /// §15.3 Busy-hours heatmap
    public var busyHours: [BusyHourCell] = []
    /// §15.3 SLA breach summary
    public var slaSummary: SLABreachSummary?

    // MARK: - §15.4 Selected tech for drill-through sheet
    public var selectedTech: TechnicianPerfRow?

    // MARK: - §15.7 Insights data
    public var warrantyClaims: [WarrantyClaimsPoint] = []
    public var deviceModelsRepaired: [DeviceModelRepaired] = []
    public var partsUsage: [PartUsageRow] = []
    public var techHours: [TechHoursRow] = []
    public var stalledTickets: StalledTicketsSummary?
    public var customerAcquisitionChurn: CustomerAcquisitionChurn?

    // MARK: - §15.9 BI built-in data
    public var revenueByCategory: [RevenueByCategoryRow] = []
    public var repeatCustomerStats: RepeatCustomerStats?
    public var avgTicketValueTrend: [AvgTicketValueTrendPoint] = []
    public var conversionFunnel: ConversionFunnelStats?
    public var laborUtilization: [LaborUtilizationRow] = []

    // MARK: - Loading / error

    public var isLoading = false
    public var errorMessage: String?

    // MARK: - Hero tile computed

    public var revenueTotalCents: Int64 { revenue.reduce(0) { $0 + $1.amountCents } }
    public var revenueTotalDollars: Double {
        // Prefer the precise server total when available
        salesTotals.totalRevenue > 0
            ? salesTotals.totalRevenue
            : Double(revenueTotalCents) / 100.0
    }

    // MARK: - Private

    public let repository: ReportsRepository

    // Cached derived dates
    private(set) var fromDateString: String = ""
    private(set) var toDateString: String = ""

    // MARK: - Init

    public init(repository: ReportsRepository) {
        self.repository = repository
        applyPreset(.thirtyDays)
    }

    // MARK: - Public API

    public func loadAll() async {
        isLoading = true
        errorMessage = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadRevenue() }
            group.addTask { await self.loadTicketsByStatus() }
            group.addTask { await self.loadAvgTicketValue() }
            group.addTask { await self.loadEmployeePerf() }
            group.addTask { await self.loadInventoryTurnover() }
            group.addTask { await self.loadInventoryReport() }
            group.addTask { await self.loadExpensesReport() }
            group.addTask { await self.loadCSAT() }
            group.addTask { await self.loadNPS() }
            group.addTask { await self.loadTechnicianPerf() }
            group.addTask { await self.loadTaxReport() }
            // §15.2
            group.addTask { await self.loadTopCustomers() }
            group.addTask { await self.loadYoYGrowth() }
            // §15.3
            group.addTask { await self.loadTicketsTrend() }
            group.addTask { await self.loadBusyHours() }
            group.addTask { await self.loadSLASummary() }
            // §15.7 Insights
            group.addTask { await self.loadWarrantyClaims() }
            group.addTask { await self.loadDeviceModelsRepaired() }
            group.addTask { await self.loadPartsUsage() }
            group.addTask { await self.loadTechHours() }
            group.addTask { await self.loadStalledTickets() }
            group.addTask { await self.loadCustomerAcquisitionChurn() }
            // §15.9 BI built-in
            group.addTask { await self.loadRevenueByCategory() }
            group.addTask { await self.loadRepeatCustomerStats() }
            group.addTask { await self.loadAvgTicketValueTrend() }
            group.addTask { await self.loadConversionFunnel() }
            group.addTask { await self.loadLaborUtilization() }
        }
        lastSyncedAt = Date()
        isLoading = false
    }

    public func applyCustomRange(from: Date, to: Date) {
        customFrom = from
        customTo = to
        selectedPreset = .custom
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fromDateString = fmt.string(from: from)
        toDateString   = fmt.string(from: to)
    }

    // MARK: - Private loaders

    private func applyPreset(_ preset: DateRangePreset) {
        let range = preset.dateRange()
        fromDateString = range.from
        toDateString   = range.to
    }

    private func loadRevenue() async {
        do {
            let report = try await repository.getSalesReport(
                from: fromDateString, to: toDateString, groupBy: granularity.rawValue
            )
            revenue = report.rows
            salesTotals = report.totals
            revenueByMethod = report.byMethod
        } catch {
            errorMessage = "Revenue: \(error.localizedDescription)"
        }
    }

    private func loadTicketsByStatus() async {
        do {
            ticketsByStatus = try await repository.getTicketsByStatus(
                from: fromDateString, to: toDateString
            )
        } catch {
            errorMessage = "Tickets: \(error.localizedDescription)"
        }
    }

    private func loadAvgTicketValue() async {
        do {
            avgTicketValue = try await repository.getAvgTicketValue(
                from: fromDateString, to: toDateString
            )
        } catch {
            errorMessage = "Avg value: \(error.localizedDescription)"
        }
    }

    private func loadEmployeePerf() async {
        do {
            employeePerf = try await repository.getEmployeesPerformance(
                from: fromDateString, to: toDateString
            )
        } catch {
            errorMessage = "Employees: \(error.localizedDescription)"
        }
    }

    private func loadInventoryTurnover() async {
        do {
            inventoryTurnover = try await repository.getInventoryTurnover(
                from: fromDateString, to: toDateString
            )
        } catch {
            errorMessage = "Inventory turnover: \(error.localizedDescription)"
        }
    }

    private func loadInventoryReport() async {
        do {
            inventoryReport = try await repository.getInventoryReport(
                from: fromDateString, to: toDateString
            )
        } catch {
            errorMessage = "Inventory: \(error.localizedDescription)"
        }
    }

    private func loadExpensesReport() async {
        do {
            expensesReport = try await repository.getExpensesReport(
                from: fromDateString, to: toDateString
            )
        } catch {
            errorMessage = "Expenses: \(error.localizedDescription)"
        }
    }

    private func loadCSAT() async {
        do {
            csatScore = try await repository.getCSAT(from: fromDateString, to: toDateString)
        } catch let err as ReportsRepositoryError {
            // CSAT endpoint not yet on server — suppress silently
            _ = err
        } catch {
            errorMessage = "CSAT: \(error.localizedDescription)"
        }
    }

    private func loadNPS() async {
        do {
            npsScore = try await repository.getNPS(from: fromDateString, to: toDateString)
        } catch {
            errorMessage = "NPS: \(error.localizedDescription)"
        }
    }

    private func loadTechnicianPerf() async {
        do {
            technicianPerf = try await repository.getTechnicianPerformance(
                from: fromDateString, to: toDateString
            )
        } catch {
            // Endpoint may not exist yet — suppress and leave empty
            technicianPerf = []
        }
    }

    private func loadTaxReport() async {
        taxReportLoading = true
        defer { taxReportLoading = false }
        do {
            taxReport = try await repository.getTaxReport(
                from: fromDateString, to: toDateString
            )
        } catch {
            // Tax endpoint may not yet be live — leave nil
            taxReport = nil
        }
    }

    // MARK: - §15.2 Top customers → GET /api/v1/reports/top-customers

    private func loadTopCustomers() async {
        do {
            topCustomers = try await repository.getTopCustomers(
                from: fromDateString, to: toDateString
            )
        } catch {
            // Endpoint may not exist yet — suppress
            topCustomers = []
        }
    }

    // MARK: - §15.2 YoY growth (derived from two sales report fetches)
    //
    // Fetch current period + prior-year equivalent period. Build YoYDataPoint per row.

    private func loadYoYGrowth() async {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        guard let currentFrom = fmt.date(from: fromDateString),
              let currentTo = fmt.date(from: toDateString) else { return }
        // Prior year: shift both dates back by 365 days
        let priorFrom = fmt.string(from: currentFrom.addingTimeInterval(-365 * 86400))
        let priorTo   = fmt.string(from: currentTo.addingTimeInterval(-365 * 86400))
        do {
            async let current = repository.getSalesReport(from: fromDateString, to: toDateString, groupBy: granularity.rawValue)
            async let prior   = repository.getSalesReport(from: priorFrom, to: priorTo, groupBy: granularity.rawValue)
            let (cur, pri) = try await (current, prior)
            // Zip rows by position (same bucket count expected)
            let n = min(cur.rows.count, pri.rows.count)
            yoyPoints = (0..<n).map { idx in
                YoYDataPoint(
                    period: cur.rows[idx].date,
                    currentRevenue: cur.rows[idx].amountDollars,
                    priorRevenue: pri.rows[idx].amountDollars
                )
            }
        } catch {
            yoyPoints = []
        }
    }

    // MARK: - §15.3 Tickets trend → GET /api/v1/reports/tickets-trend

    private func loadTicketsTrend() async {
        do {
            ticketsTrend = try await repository.getTicketsTrend(
                from: fromDateString, to: toDateString
            )
        } catch {
            ticketsTrend = []
        }
    }

    // MARK: - §15.3 Busy hours → GET /api/v1/reports/tickets-heatmap

    private func loadBusyHours() async {
        do {
            busyHours = try await repository.getBusyHours(
                from: fromDateString, to: toDateString
            )
        } catch {
            busyHours = []
        }
    }

    // MARK: - §15.3 SLA summary → GET /api/v1/reports/sla

    private func loadSLASummary() async {
        do {
            slaSummary = try await repository.getSLASummary(
                from: fromDateString, to: toDateString
            )
        } catch {
            slaSummary = nil
        }
    }

    // MARK: - §15.7 Warranty claims → GET /api/v1/reports/warranty-claims

    private func loadWarrantyClaims() async {
        do {
            warrantyClaims = try await repository.getWarrantyClaims(
                from: fromDateString, to: toDateString
            )
        } catch { warrantyClaims = [] }
    }

    // MARK: - §15.7 Device models repaired → GET /api/v1/reports/device-models

    private func loadDeviceModelsRepaired() async {
        do {
            deviceModelsRepaired = try await repository.getDeviceModelsRepaired(
                from: fromDateString, to: toDateString
            )
        } catch { deviceModelsRepaired = [] }
    }

    // MARK: - §15.7 Parts usage → GET /api/v1/reports/parts-usage

    private func loadPartsUsage() async {
        do {
            partsUsage = try await repository.getPartsUsage(
                from: fromDateString, to: toDateString
            )
        } catch { partsUsage = [] }
    }

    // MARK: - §15.7 Tech hours → GET /api/v1/reports/tech-hours

    private func loadTechHours() async {
        do {
            techHours = try await repository.getTechHours(
                from: fromDateString, to: toDateString
            )
        } catch { techHours = [] }
    }

    // MARK: - §15.7 Stalled tickets → GET /api/v1/reports/stalled-tickets

    private func loadStalledTickets() async {
        do {
            stalledTickets = try await repository.getStalledTickets(
                from: fromDateString, to: toDateString
            )
        } catch { stalledTickets = nil }
    }

    // MARK: - §15.7 Customer acquisition & churn → GET /api/v1/reports/customer-acquisition

    private func loadCustomerAcquisitionChurn() async {
        do {
            customerAcquisitionChurn = try await repository.getCustomerAcquisitionChurn(
                from: fromDateString, to: toDateString
            )
        } catch { customerAcquisitionChurn = nil }
    }

    // MARK: - §15.9 Revenue by category → GET /api/v1/reports/revenue-by-category

    private func loadRevenueByCategory() async {
        do {
            revenueByCategory = try await repository.getRevenueByCategory(
                from: fromDateString, to: toDateString
            )
        } catch { revenueByCategory = [] }
    }

    // MARK: - §15.9 Repeat customer stats → GET /api/v1/reports/repeat-customers

    private func loadRepeatCustomerStats() async {
        do {
            repeatCustomerStats = try await repository.getRepeatCustomerStats(
                from: fromDateString, to: toDateString
            )
        } catch { repeatCustomerStats = nil }
    }

    // MARK: - §15.9 Avg ticket value trend → derived from multiple periods

    private func loadAvgTicketValueTrend() async {
        do {
            avgTicketValueTrend = try await repository.getAvgTicketValueTrend(
                from: fromDateString, to: toDateString
            )
        } catch { avgTicketValueTrend = [] }
    }

    // MARK: - §15.9 Conversion funnel → GET /api/v1/reports/conversion-funnel

    private func loadConversionFunnel() async {
        do {
            conversionFunnel = try await repository.getConversionFunnel(
                from: fromDateString, to: toDateString
            )
        } catch { conversionFunnel = nil }
    }

    // MARK: - §15.9 Labor utilization → GET /api/v1/reports/labor-utilization

    private func loadLaborUtilization() async {
        do {
            laborUtilization = try await repository.getLaborUtilization(
                from: fromDateString, to: toDateString
            )
        } catch { laborUtilization = [] }
    }
}
