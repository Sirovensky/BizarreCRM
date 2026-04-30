import Foundation
import Networking
import Persistence

/// §39 — Production implementation of `CashSessionRepository`.
///
/// Network calls hit confirmed POS routes via typed `APIClient+CashRegister`
/// wrappers (§20 containment — no raw `.get`/`.post` path strings here).
/// Local session lifecycle delegates to `CashRegisterStore` (actor-isolated, GRDB-backed).
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
    // Calls go through typed APIClient+CashRegister wrappers — no bare path strings.

    public func fetchRegisterState() async throws -> RegisterStateDTO {
        let response = try await api.getPosRegisterState()
        return RegisterStateDTO(
            cashIn: response.cashIn,
            cashOut: response.cashOut,
            cashSales: response.cashSales,
            net: response.net,
            entries: response.entries.map {
                RegisterEntryDTO(
                    id: $0.id,
                    type: $0.type,
                    amount: $0.amount,
                    reason: $0.reason,
                    userName: $0.userName,
                    createdAt: $0.createdAt
                )
            }
        )
    }

    public func postCashIn(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO {
        guard amountCents > 0 else {
            throw CashSessionValidationError.nonPositiveAmount
        }
        guard amountCents <= 5_000_000 else {
            throw CashSessionValidationError.exceedsLimit
        }
        let response = try await api.postPosCashIn(amountCents: amountCents, reason: reason)
        return RegisterEntryDTO(
            id: response.entry.id,
            type: response.entry.type,
            amount: response.entry.amount,
            reason: response.entry.reason,
            userName: response.entry.userName,
            createdAt: response.entry.createdAt
        )
    }

    public func postCashOut(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO {
        guard amountCents > 0 else {
            throw CashSessionValidationError.nonPositiveAmount
        }
        guard amountCents <= 5_000_000 else {
            throw CashSessionValidationError.exceedsLimit
        }
        let response = try await api.postPosCashOut(amountCents: amountCents, reason: reason)
        return RegisterEntryDTO(
            id: response.entry.id,
            type: response.entry.type,
            amount: response.entry.amount,
            reason: response.entry.reason,
            userName: response.entry.userName,
            createdAt: response.entry.createdAt
        )
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
