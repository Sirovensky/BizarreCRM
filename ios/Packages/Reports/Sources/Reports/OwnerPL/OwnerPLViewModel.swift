import Foundation
import Observation

// MARK: - OwnerPLViewModel

@Observable
@MainActor
public final class OwnerPLViewModel {

    // MARK: - State

    public var summary: OwnerPLSummary?
    public var isLoading = false
    public var errorMessage: String?

    // MARK: - Date controls

    public var selectedPreset: DateRangePreset = .thirtyDays {
        didSet { if selectedPreset != .custom { applyPreset(selectedPreset) } }
    }
    public var rollup: OwnerPLRollup = .day

    // MARK: - Display toggles

    /// When true the time-series chart and revenue KPI use net revenue (after refunds/discounts).
    /// When false they show gross revenue. Toggled via the gross/net segmented control.
    public var showNetRevenue: Bool = false
    public private(set) var fromDateString: String = ""
    public private(set) var toDateString: String   = ""

    // MARK: - Private

    private let repository: OwnerPLRepository

    // MARK: - Init

    public init(repository: OwnerPLRepository) {
        self.repository = repository
        applyPreset(.thirtyDays)
    }

    // MARK: - Public API

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await repository.getSummary(
                from: fromDateString, to: toDateString, rollup: rollup
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func applyCustomRange(from: Date, to: Date) {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fromDateString = fmt.string(from: from)
        toDateString   = fmt.string(from: to)
        selectedPreset = .custom
    }

    // MARK: - Private

    private func applyPreset(_ preset: DateRangePreset) {
        let range = preset.dateRange()
        fromDateString = range.from
        toDateString   = range.to
    }
}
