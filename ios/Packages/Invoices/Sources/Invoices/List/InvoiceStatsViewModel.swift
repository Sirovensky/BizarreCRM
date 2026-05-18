import Foundation
import Observation
import Core
import Networking

// §7.1 Invoice stats header ViewModel
// Endpoint: GET /api/v1/invoices/stats

@MainActor
@Observable
public final class InvoiceStatsViewModel {
    public private(set) var stats: InvoiceStats?
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await api.invoiceStats()
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: nav-away cancels stats fetch; keep prior
            // stats visible instead of clearing.
            return
        } catch {
            AppLog.ui.error("Invoice stats load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
