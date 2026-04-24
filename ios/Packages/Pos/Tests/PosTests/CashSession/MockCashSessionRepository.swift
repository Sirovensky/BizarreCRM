import Foundation
@testable import Pos
import Persistence

// MARK: - In-process mock

/// Test double for `CashSessionRepository`.
///
/// All methods record calls and return pre-configured results. Designed to
/// be shared across `OpenRegisterViewModelTests` and
/// `CloseRegisterViewModelTests`.
final class MockCashSessionRepository: CashSessionRepository, @unchecked Sendable {

    // MARK: - Recorded calls

    var openSessionCallCount: Int = 0
    var closeSessionCallCount: Int = 0
    var fetchRegisterStateCallCount: Int = 0
    var postCashInCallCount: Int = 0
    var postCashOutCallCount: Int = 0
    var recentSessionsCallCount: Int = 0
    var currentSessionCallCount: Int = 0

    var lastOpenFloat: Int?
    var lastOpenUserId: Int64?
    var lastCloseCounted: Int?
    var lastCloseExpected: Int?
    var lastCloseNotes: String??
    var lastCashInAmount: Int?
    var lastCashOutAmount: Int?

    // MARK: - Stubbable results

    var openSessionResult: Result<CashSessionRecord, Error> = .success(
        MockCashSessionRepository.makeOpenRecord()
    )
    var closeSessionResult: Result<CashSessionRecord, Error> = .success(
        MockCashSessionRepository.makeClosedRecord()
    )
    var fetchRegisterStateResult: Result<RegisterStateDTO, Error> = .success(
        RegisterStateDTO(cashIn: 0, cashOut: 0, cashSales: 5000, net: 5000, entries: [])
    )
    var postCashInResult: Result<RegisterEntryDTO, Error> = .success(
        RegisterEntryDTO(id: 1, type: "cash_in", amount: 1000, reason: nil, userName: nil, createdAt: nil)
    )
    var postCashOutResult: Result<RegisterEntryDTO, Error> = .success(
        RegisterEntryDTO(id: 2, type: "cash_out", amount: 500, reason: nil, userName: nil, createdAt: nil)
    )
    var currentSessionResult: Result<CashSessionRecord?, Error> = .success(nil)
    var recentSessionsResult: Result<[CashSessionRecord], Error> = .success([])

    // MARK: - Protocol conformance

    func openSession(openingFloatCents: Int, userId: Int64) async throws -> CashSessionRecord {
        openSessionCallCount += 1
        lastOpenFloat = openingFloatCents
        lastOpenUserId = userId
        return try openSessionResult.get()
    }

    func closeSession(countedCash: Int, expectedCash: Int, notes: String?, closedBy: Int64) async throws -> CashSessionRecord {
        closeSessionCallCount += 1
        lastCloseCounted = countedCash
        lastCloseExpected = expectedCash
        lastCloseNotes = notes
        return try closeSessionResult.get()
    }

    func fetchRegisterState() async throws -> RegisterStateDTO {
        fetchRegisterStateCallCount += 1
        return try fetchRegisterStateResult.get()
    }

    func postCashIn(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO {
        postCashInCallCount += 1
        lastCashInAmount = amountCents
        return try postCashInResult.get()
    }

    func postCashOut(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO {
        postCashOutCallCount += 1
        lastCashOutAmount = amountCents
        return try postCashOutResult.get()
    }

    func currentSession() async throws -> CashSessionRecord? {
        currentSessionCallCount += 1
        return try currentSessionResult.get()
    }

    func recentSessions(limit: Int) async throws -> [CashSessionRecord] {
        recentSessionsCallCount += 1
        return try recentSessionsResult.get()
    }

    // MARK: - Factories

    static func makeOpenRecord(id: Int64 = 1, float: Int = 5000, userId: Int64 = 42) -> CashSessionRecord {
        CashSessionRecord(
            id: id,
            openedBy: userId,
            openedAt: Date(timeIntervalSince1970: 0),
            openingFloat: float
        )
    }

    static func makeClosedRecord(
        id: Int64 = 1,
        float: Int = 5000,
        counted: Int = 15000,
        expected: Int = 14500,
        notes: String? = nil
    ) -> CashSessionRecord {
        var r = makeOpenRecord(id: id, float: float)
        r.closedAt = Date(timeIntervalSince1970: 3600)
        r.closedBy = 42
        r.countedCash = counted
        r.expectedCash = expected
        r.varianceCents = counted - expected
        r.notes = notes
        return r
    }
}
