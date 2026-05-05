import Foundation
import Observation
import Core

// MARK: - FinancialDashboardViewModel
//
// §59 Financial Dashboard — owner home screen KPI view model.
//
// Responsibilities:
//   - Holds the current date range (defaults to last 30 days).
//   - Drives loading state transitions: .idle → .loading → .loaded | .failed.
//   - Exposes the snapshot to `FinancialDashboardView`.
//
// Pattern mirrors `DashboardViewModel` in the same package.

@MainActor
@Observable
public final class FinancialDashboardViewModel {

    // MARK: - State

    public enum State: Sendable {
        case idle
        case loading
        case loaded(FinancialDashboardSnapshot)
        case failed(String)
    }

    // MARK: - Published properties

    public var state: State = .idle
    public var params: FinancialQueryParams = .defaultLast30Days

    // MARK: - Private

    @ObservationIgnored private let repo: FinancialDashboardRepository

    // MARK: - Init

    public init(repo: FinancialDashboardRepository) {
        self.repo = repo
    }

    // MARK: - Load

    /// Load or soft-refresh: keeps existing data visible during re-fetch.
    public func load() async {
        if case .loaded = state {
            // Soft refresh — don't regress to .loading; keep existing data.
        } else {
            state = .loading
        }

        do {
            let snapshot = try await repo.load(params: params)
            state = .loaded(snapshot)
        } catch {
            AppLog.ui.error(
                "FinancialDashboard load failed: \(error.localizedDescription, privacy: .public)"
            )
            state = .failed(error.localizedDescription)
        }
    }

    /// Force full reload (e.g. after period picker change or pull-to-refresh).
    public func reload() async {
        state = .loading
        await load()
    }

    /// Apply a new date range and reload.
    public func applyParams(_ newParams: FinancialQueryParams) async {
        params = newParams
        await reload()
    }
}

// MARK: - Formatting helpers (pure functions; testable without UIKit)

/// Format an integer cents value as a compact currency string, e.g. "$12.4k".
func financialFormatCurrency(_ dollars: Double) -> String {
    let abs = Swift.abs(dollars)
    let sign = dollars < 0 ? "-" : ""
    switch abs {
    case 1_000_000...:
        return "\(sign)$\(financialCompactNumber(abs / 1_000_000))M"
    case 1_000...:
        return "\(sign)$\(financialCompactNumber(abs / 1_000))k"
    default:
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: dollars)) ?? "\(sign)$\(Int(abs))"
    }
}

private func financialCompactNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

/// Format a percentage to one decimal place, e.g. "42.3%".
func financialFormatPercent(_ pct: Double) -> String {
    String(format: "%.1f%%", pct)
}
