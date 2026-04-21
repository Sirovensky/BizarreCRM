import Foundation
import Observation
import Core
import Networking
import Sync

// MARK: - Start VM

@MainActor
@Observable
public final class StocktakeStartViewModel {
    public var selectedCategory: String = ""
    public var selectedLocation: String = ""
    public var sessionName: String = ""

    public private(set) var isStarting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var startedSession: StocktakeSession?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var scopeDescription: String {
        if !selectedCategory.isEmpty { return "Category: \(selectedCategory)" }
        if !selectedLocation.isEmpty { return "Location: \(selectedLocation)" }
        return "All items"
    }

    public func start() async {
        guard !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        let req = StartStocktakeRequest(
            category: selectedCategory.isEmpty ? nil : selectedCategory,
            location: selectedLocation.isEmpty ? nil : selectedLocation,
            name: sessionName.isEmpty ? nil : sessionName
        )

        do {
            startedSession = try await api.startStocktake(req)
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                errorMessage = "You're offline. Connect to start a stocktake."
            } else {
                AppLog.ui.error("Stocktake start failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Scan VM

@MainActor
@Observable
public final class StocktakeScanViewModel {
    public private(set) var session: StocktakeSession?
    public private(set) var isLoading: Bool = false
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var showReview: Bool = false
    public private(set) var isOffline: Bool = false

    /// Live mutable counts: key = sku, value = operator-entered qty.
    public var actualCounts: [String: String] = [:]

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let sessionId: Int64
    /// Pending finalize request queued for offline drain.
    @ObservationIgnored private var pendingOfflineSync: Bool = false

    public init(api: APIClient, sessionId: Int64) {
        self.api = api
        self.sessionId = sessionId
    }

    public var rows: [StocktakeRow] {
        session?.rows ?? []
    }

    public var summary: StocktakeSummary {
        let liveRows = rows.map { row -> StocktakeRow in
            var r = row
            r.actualQty = Int(actualCounts[row.sku] ?? "")
            return r
        }
        return StocktakeDiscrepancyCalculator.summary(from: liveRows)
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await api.stocktakeSession(id: sessionId)
            session = fetched
            // Pre-fill any already-counted rows
            for row in fetched.rows {
                if let existing = row.actualQty {
                    actualCounts[row.sku] = String(existing)
                }
            }
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                isOffline = true
                errorMessage = "Offline — showing cached data"
            } else {
                AppLog.ui.error("StocktakeScan load: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Scan a barcode → find row by SKU → set actual qty = 1 (or increment).
    @discardableResult
    public func applyBarcode(_ value: String) -> Bool {
        guard let session,
              session.rows.contains(where: { $0.sku == value }) else { return false }
        let current = Int(actualCounts[value] ?? "0") ?? 0
        actualCounts[value] = String(current + 1)
        return true
    }

    public func finalize() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let lines: [FinalizeStocktakeLine] = rows.compactMap { row in
            guard let qty = Int(actualCounts[row.sku] ?? "") else { return nil }
            return FinalizeStocktakeLine(sku: row.sku, actualQty: qty)
        }

        let req = FinalizeStocktakeRequest(lines: lines)

        do {
            _ = try await api.finalizeStocktake(id: sessionId, request: req)
            showReview = true
        } catch {
            if InventoryOfflineQueue.isNetworkError(error) {
                // Enqueue for offline drain
                if let payload = try? InventoryOfflineQueue.encode(req) {
                    await InventoryOfflineQueue.enqueue(
                        op: "stocktake.finalize",
                        entityServerId: sessionId,
                        payload: payload
                    )
                }
                pendingOfflineSync = true
                isOffline = true
                showReview = true
            } else {
                AppLog.ui.error("Stocktake finalize: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Testing support

    /// Inject a session directly — used by unit tests to bypass network loading.
    internal func _setSessionForTesting(_ s: StocktakeSession) {
        self.session = s
        for row in s.rows {
            if let existing = row.actualQty {
                actualCounts[row.sku] = String(existing)
            }
        }
    }

    /// Computed discrepancies from current live counts.
    public var discrepancies: [StocktakeDiscrepancy] {
        let liveRows = rows.map { row -> StocktakeRow in
            var r = row
            r.actualQty = Int(actualCounts[row.sku] ?? "")
            return r
        }
        return StocktakeDiscrepancyCalculator.discrepancies(from: liveRows)
    }
}
