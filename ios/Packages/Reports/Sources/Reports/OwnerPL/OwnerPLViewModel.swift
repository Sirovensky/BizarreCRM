import Foundation
import Observation
import Core

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
    /// BUGHUNT-2026-05-17: track the in-flight load so a rapid preset swap
    /// (e.g. ThisMonth → ThisQuarter while still loading) cancels the older
    /// fetch. Without this, the older response could land second and the
    /// summary would show data labelled with the newer preset, or paint
    /// a fake "cancelled" banner from `error.localizedDescription`.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    // MARK: - Init

    public init(repository: OwnerPLRepository) {
        self.repository = repository
        applyPreset(.thirtyDays)
    }

    // MARK: - Public API

    public func load() async {
        // BUGHUNT-2026-05-17: cancel any prior load and run the new fetch in
        // a tracked Task so .onChange (preset/rollup) callers' Task wrapper
        // gets a cancellable handle. Stomping the older request prevents the
        // ".thirtyDays → .thisQuarter" race where the slower thirty-days
        // response lands second and overwrites the freshly painted summary.
        loadTask?.cancel()
        let task = Task<Void, Never> { [weak self] in
            await self?.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await repository.getSummary(
                from: fromDateString, to: toDateString, rollup: rollup
            )
            if Task.isCancelled { return }
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: superseded by a newer load. Stay silent so
            // the newer task can drive isLoading/errorMessage cleanly.
            return
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
