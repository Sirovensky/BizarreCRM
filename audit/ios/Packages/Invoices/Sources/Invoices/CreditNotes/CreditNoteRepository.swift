import Foundation
import Networking

// §7.10 Credit Note Repository + Endpoints

private struct VoidBody: Encodable, Sendable {
    let reason: String? = nil
}

public protocol CreditNoteRepository: Sendable {
    func list(customerId: Int64?) async throws -> [CreditNote]
    func create(_ request: CreateCreditNoteRequest) async throws -> CreditNote
    func apply(_ request: ApplyCreditNoteRequest) async throws -> CreditNote
    func void(id: Int64) async throws -> CreditNote
}

// MARK: - Endpoints

public extension APIClient {

    /// `GET /api/v1/credit-notes?customer_id=X`
    func listCreditNotes(customerId: Int64? = nil) async throws -> [CreditNote] {
        var query: [URLQueryItem] = []
        if let cid = customerId {
            query.append(URLQueryItem(name: "customer_id", value: "\(cid)"))
        }
        return try await get(
            "/api/v1/credit-notes",
            query: query.isEmpty ? nil : query,
            as: [CreditNote].self
        )
    }

    /// `POST /api/v1/credit-notes`
    func createCreditNote(_ req: CreateCreditNoteRequest) async throws -> CreditNote {
        try await post("/api/v1/credit-notes", body: req, as: CreditNote.self)
    }

    /// `POST /api/v1/credit-notes/:id/apply`
    /// Server: packages/server/src/routes/creditNotes.routes.ts:235
    func applyCreditNote(_ req: ApplyCreditNoteRequest) async throws -> CreditNote {
        try await post("/api/v1/credit-notes/\(req.creditNoteId)/apply", body: req, as: CreditNote.self)
    }

    /// `POST /api/v1/credit-notes/:id/void`
    func voidCreditNote(id: Int64) async throws -> CreditNote {
        try await post(
            "/api/v1/credit-notes/\(id)/void",
            body: VoidBody(),
            as: CreditNote.self
        )
    }
}

// MARK: - Impl

public actor CreditNoteRepositoryImpl: CreditNoteRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func list(customerId: Int64?) async throws -> [CreditNote] {
        try await api.listCreditNotes(customerId: customerId)
    }

    public func create(_ request: CreateCreditNoteRequest) async throws -> CreditNote {
        try await api.createCreditNote(request)
    }

    public func apply(_ request: ApplyCreditNoteRequest) async throws -> CreditNote {
        try await api.applyCreditNote(request)
    }

    public func void(id: Int64) async throws -> CreditNote {
        try await api.voidCreditNote(id: id)
    }
}
