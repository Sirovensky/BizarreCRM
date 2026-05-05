import Foundation
import Networking

// MARK: - Protocol

/// §16 — Repository protocol for receipt reprint operations.
///
/// Wraps the Networking layer so ViewModels never call `APIClient` directly
/// (§20 containment rule). Production impl uses `APIClient+CashRegister` typed
/// wrappers; test impl can be a lightweight fake.
public protocol ReprintRepository: Sendable {
    /// `GET /api/v1/sales/:id` — fetch full sale detail for reprint.
    func fetchSale(id: Int64) async throws -> SaleRecord

    /// `GET /api/v1/sales/search?q=<query>` — search past sales.
    func searchSales(query: String) async throws -> [SaleSummary]

    /// `POST /api/v1/sales/:id/reprint-event` — audit-log a reprint.
    func logReprintEvent(saleId: Int64, reason: String) async throws
}

// MARK: - Production implementation

/// §16 — Live `ReprintRepository` backed by `APIClient+CashRegister` wrappers.
public struct ReprintRepositoryImpl: ReprintRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func fetchSale(id: Int64) async throws -> SaleRecord {
        try await api.getSale(id: id, as: SaleRecord.self)
    }

    public func searchSales(query: String) async throws -> [SaleSummary] {
        try await api.searchSales(query: query, as: [SaleSummary].self)
    }

    public func logReprintEvent(saleId: Int64, reason: String) async throws {
        struct ReprintEventBody: Encodable, Sendable {
            let reason: String
        }
        try await api.postReprintEvent(saleId: saleId, body: ReprintEventBody(reason: reason))
    }
}
