import Foundation
import SwiftUI
import Observation

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

    // MARK: - Data state

    public var revenue: [RevenuePoint] = []
    public var ticketsByStatus: [TicketStatusPoint] = []
    public var avgTicketValue: AvgTicketValue?
    public var employeePerf: [EmployeePerf] = []
    public var inventoryTurnover: [InventoryTurnoverRow] = []
    public var csatScore: CSATScore?
    public var npsScore: NPSScore?
    public var lastSyncedAt: Date?

    // MARK: - Loading / error

    public var isLoading = false
    public var errorMessage: String?

    // MARK: - Hero tile computed

    public var revenueTotalCents: Int64 { revenue.reduce(0) { $0 + $1.amountCents } }
    public var revenueTotalDollars: Double { Double(revenueTotalCents) / 100.0 }

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
            group.addTask { await self.loadCSAT() }
            group.addTask { await self.loadNPS() }
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
            revenue = try await repository.getRevenue(from: fromDateString, to: toDateString, groupBy: "day")
        } catch {
            errorMessage = "Revenue: \(error.localizedDescription)"
        }
    }

    private func loadTicketsByStatus() async {
        do {
            ticketsByStatus = try await repository.getTicketsByStatus(from: fromDateString, to: toDateString)
        } catch {
            errorMessage = "Tickets: \(error.localizedDescription)"
        }
    }

    private func loadAvgTicketValue() async {
        do {
            avgTicketValue = try await repository.getAvgTicketValue(from: fromDateString, to: toDateString)
        } catch {
            errorMessage = "Avg value: \(error.localizedDescription)"
        }
    }

    private func loadEmployeePerf() async {
        do {
            employeePerf = try await repository.getEmployeesPerformance(from: fromDateString, to: toDateString)
        } catch {
            errorMessage = "Employees: \(error.localizedDescription)"
        }
    }

    private func loadInventoryTurnover() async {
        do {
            inventoryTurnover = try await repository.getInventoryTurnover(from: fromDateString, to: toDateString)
        } catch {
            errorMessage = "Inventory: \(error.localizedDescription)"
        }
    }

    private func loadCSAT() async {
        do {
            csatScore = try await repository.getCSAT(from: fromDateString, to: toDateString)
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
}
