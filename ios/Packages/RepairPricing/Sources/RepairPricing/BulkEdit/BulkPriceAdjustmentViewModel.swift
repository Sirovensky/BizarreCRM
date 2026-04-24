import Foundation
import Observation
import Networking
import Core

// MARK: - §43 Bulk Edit — Bulk Price Adjustment ViewModel

/// Backing ViewModel for `BulkPriceAdjustmentSheet`.
///
/// Workflow:
/// 1. Caller presents the sheet; VM auto-loads available price rows.
/// 2. User selects adjustment kind + enters a value.
/// 3. VM generates a live preview via `PricingAdjustmentEngine.preview(...)`.
/// 4. User taps "Apply" → VM calls `PUT /repair-pricing/prices/:id` for each
///    changed row via `applyChanges()`.
///
/// State machine:
///   `.idle` → `.loadingPrices` → `.preview([...])` → `.applying` → `.applied` | `.failed`
@MainActor
@Observable
public final class BulkPriceAdjustmentViewModel {

    // MARK: - Form fields

    /// Whether the adjustment is percentage or fixed dollar.
    public var adjustmentKind: PricingAdjustmentKind = .percentage

    /// Raw string entered by the user (e.g. "10" or "-2.50").
    public var rawValue: String = ""

    /// The user-visible error message for the value field.
    public var valueValidationMessage: String? {
        guard !rawValue.isEmpty, let parsed = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return rawValue.isEmpty ? nil : "Enter a valid number."
        }
        let rule = PricingAdjustmentRule(kind: adjustmentKind, value: parsed)
        return PricingAdjustmentEngine.validate(rule: rule)?.errorDescription
    }

    /// Whether the form is ready to preview/apply.
    public var canPreview: Bool {
        guard let parsed = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        let rule = PricingAdjustmentRule(kind: adjustmentKind, value: parsed)
        return PricingAdjustmentEngine.validate(rule: rule) == nil
    }

    // MARK: - Optional category filter

    /// If set, only prices for services in this category are loaded/adjusted.
    public var categoryFilter: String? = nil

    // MARK: - Phase state

    public enum Phase: Sendable, Equatable {
        case idle
        case loadingPrices
        case preview([PriceAdjustmentResult])
        case applying(progress: Int, total: Int)
        case applied(successCount: Int)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    /// Convenience: whether we are actively sending network requests.
    public var isBusy: Bool {
        switch phase {
        case .loadingPrices, .applying: return true
        default: return false
        }
    }

    // MARK: - Loaded data

    /// All price rows loaded from the server.
    public private(set) var priceRows: [RepairPriceRow] = []

    /// Currently computed preview results (non-empty only in `.preview` phase).
    public var previewResults: [PriceAdjustmentResult] {
        if case .preview(let results) = phase { return results }
        return []
    }

    /// Summary stats for the preview panel.
    public var previewSummary: PreviewSummary {
        let results = previewResults
        guard !results.isEmpty else { return PreviewSummary(count: 0, totalIncrease: 0, avgDelta: 0) }
        let totalDelta = results.reduce(0) { $0 + $1.delta }
        return PreviewSummary(
            count: results.count,
            totalIncrease: totalDelta,
            avgDelta: totalDelta / Double(results.count)
        )
    }

    // MARK: - Private

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Load available price rows from the server.
    public func loadPrices() async {
        phase = .loadingPrices
        do {
            priceRows = try await api.listRepairPrices(category: categoryFilter)
            phase = .idle
        } catch {
            AppLog.ui.error("BulkPriceAdjustment load failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Build and show the preview. Does NOT send any network requests.
    public func generatePreview() {
        guard canPreview else { return }
        guard let parsed = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let rule = PricingAdjustmentRule(kind: adjustmentKind, value: parsed)
        let items = priceRows.map {
            PriceInputItem(id: $0.id, name: $0.repairServiceName ?? "Service \($0.id)", laborPrice: $0.laborPrice)
        }
        let results = PricingAdjustmentEngine.preview(items: items, rule: rule)
        phase = .preview(results)
    }

    /// Discard the preview and return to idle.
    public func cancelPreview() {
        phase = .idle
    }

    /// Apply all previewed changes by PUTting each changed price.
    ///
    /// Only rows where `newPrice != originalPrice` are sent to the server
    /// (i.e. a zero-delta row is skipped).
    public func applyChanges() async {
        guard case .preview(let results) = phase else { return }
        let changed = results.filter { abs($0.delta) > 0.001 }
        guard !changed.isEmpty else {
            phase = .applied(successCount: 0)
            return
        }

        phase = .applying(progress: 0, total: changed.count)
        var successCount = 0
        var lastError: String?

        for (index, result) in changed.enumerated() {
            phase = .applying(progress: index, total: changed.count)
            do {
                _ = try await api.updateRepairPrice(id: result.id, laborPrice: result.newPrice)
                successCount += 1
            } catch {
                AppLog.ui.error("BulkPriceAdjustment PUT \(result.id) failed: \(error.localizedDescription, privacy: .public)")
                lastError = error.localizedDescription
            }
        }

        if successCount == changed.count {
            phase = .applied(successCount: successCount)
        } else {
            let msg = lastError ?? "Some updates failed."
            phase = .failed("Applied \(successCount)/\(changed.count). \(msg)")
        }
    }

    /// Reset form state so the sheet can be re-used.
    public func reset() {
        rawValue = ""
        adjustmentKind = .percentage
        categoryFilter = nil
        priceRows = []
        phase = .idle
    }
}

// MARK: - Preview Summary

public struct PreviewSummary: Sendable, Equatable {
    /// Number of rows that will change.
    public let count: Int
    /// Total dollar change across all rows.
    public let totalIncrease: Double
    /// Average delta per row.
    public let avgDelta: Double

    public init(count: Int, totalIncrease: Double, avgDelta: Double) {
        self.count = count
        self.totalIncrease = totalIncrease
        self.avgDelta = avgDelta
    }
}
