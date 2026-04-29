import Foundation
import SwiftUI
import Observation
import Networking

// MARK: - ReportsViewModel

@Observable
@MainActor
public final class ReportsViewModel {

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
    /// nil = not yet loaded / endpoint not implemented; hasBreaches drives card visibility.
    public var slaBreaches: SLABreachReport?
    public var lastSyncedAt: Date?

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
            group.addTask { await self.loadSLABreaches() }
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

    private func loadSLABreaches() async {
        do {
            slaBreaches = try await repository.getSLABreaches(
                from: fromDateString, to: toDateString
            )
        } catch let err as ReportsRepositoryError {
            // Suppress stub error — card stays hidden until server implements the endpoint.
            _ = err
        } catch {
            errorMessage = "SLA: \(error.localizedDescription)"
        }
    }
}
