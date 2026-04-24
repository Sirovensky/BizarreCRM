import Foundation
import Networking
import Persistence

/// §39 — Production implementation of `CashSessionRepository`.
///
/// Network calls hit confirmed POS routes. Local session lifecycle
/// delegates to `CashRegisterStore` (actor-isolated, GRDB-backed).
///
/// Thread safety: `Sendable` actor-isolated storage is handled entirely
/// by the underlying `APIClient` and `CashRegisterStore` actors.
public struct CashSessionRepositoryImpl: CashSessionRepository {

    private let api: APIClient
    private let store: CashRegisterStore

    public init(api: APIClient, store: CashRegisterStore = .shared) {
        self.api = api
        self.store = store
    }

    // MARK: - Network layer (confirmed server routes)

    public func fetchRegisterState() async throws -> RegisterStateDTO {
        try await api.get("/api/v1/pos/register", as: RegisterStateDTO.self)
    }

    public func postCashIn(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO {
        guard amountCents > 0 else {
            throw CashSessionValidationError.nonPositiveAmount
        }
        guard amountCents <= 5_000_000 else {
            throw CashSessionValidationError.exceedsLimit
        }
        let req = CashMoveRequest(amount: amountCents, reason: reason)
        let wrapper = try await api.post("/api/v1/pos/cash-in", body: req, as: CashMoveResponseWrapper.self)
        return wrapper.entry
    }

    public func postCashOut(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO {
        guard amountCents > 0 else {
            throw CashSessionValidationError.nonPositiveAmount
        }
        guard amountCents <= 5_000_000 else {
            throw CashSessionValidationError.exceedsLimit
        }
        let req = CashMoveRequest(amount: amountCents, reason: reason)
        let wrapper = try await api.post("/api/v1/pos/cash-out", body: req, as: CashMoveResponseWrapper.self)
        return wrapper.entry
    }

    // MARK: - Local session lifecycle

    public func openSession(openingFloatCents: Int, userId: Int64) async throws -> CashSessionRecord {
        try await store.openSession(
            openingFloat: max(0, openingFloatCents),
            userId: userId
        )
    }

    public func closeSession(
        countedCash: Int,
        expectedCash: Int,
        notes: String?,
        closedBy: Int64
    ) async throws -> CashSessionRecord {
        try await store.closeSession(
            countedCash: countedCash,
            expectedCash: expectedCash,
            notes: notes,
            closedBy: closedBy
        )
    }

    public func currentSession() async throws -> CashSessionRecord? {
        try await store.currentSession()
    }

    public func recentSessions(limit: Int = 20) async throws -> [CashSessionRecord] {
        try await store.recentSessions(limit: limit)
    }
}

// MARK: - Validation errors

/// Client-side validation errors raised before the network call.
/// These supplement the server's own 400 responses so we fail fast.
public enum CashSessionValidationError: Error, LocalizedError, Sendable {
    case nonPositiveAmount
    case exceedsLimit

    public var errorDescription: String? {
        switch self {
        case .nonPositiveAmount:
            return "Amount must be greater than zero."
        case .exceedsLimit:
            return "Amount cannot exceed $50,000."
        }
    }
}
