import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class InvoiceDetailViewModel {
    public enum State: Sendable {
        case loading
        case loaded(InvoiceDetail)
        case failed(String)
    }

    public var state: State = .loading
    public let invoiceId: Int64

    @ObservationIgnored private let repo: InvoiceDetailRepository

    public init(repo: InvoiceDetailRepository, invoiceId: Int64) {
        self.repo = repo
        self.invoiceId = invoiceId
    }

    public func load() async {
        if case .loaded = state { /* soft-refresh */ } else { state = .loading }
        do {
            state = .loaded(try await repo.detail(id: invoiceId))
        } catch {
            AppLog.ui.error("Invoice detail load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

public protocol InvoiceDetailRepository: Sendable {
    func detail(id: Int64) async throws -> InvoiceDetail
}

public actor InvoiceDetailRepositoryImpl: InvoiceDetailRepository {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func detail(id: Int64) async throws -> InvoiceDetail { try await api.invoice(id: id) }
}
