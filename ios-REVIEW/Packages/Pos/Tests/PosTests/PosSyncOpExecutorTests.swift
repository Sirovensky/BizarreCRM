import Testing
import Foundation
@testable import Pos
import Core
import Persistence
import Sync
import Networking

// MARK: - MockPosAPIClient

/// Thread-safe mock APIClient. Uses an `actor` for state isolation so we can
/// safely call `capturedPaths` from async test functions.
actor MockPosAPIClient: APIClient {
    private(set) var capturedPaths: [String] = []
    var stubError: Error? = nil

    func recorded() -> [String] { capturedPaths }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        fatalError("not used in executor tests")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        capturedPaths.append(path)
        if let error = stubError { throw error }
        let data = "{}".data(using: .utf8)!
        return try JSONDecoder().decode(type, from: data)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        fatalError("not used in executor tests")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        fatalError("not used in executor tests")
    }

    func delete(_ path: String) async throws {
        fatalError("not used in executor tests")
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        fatalError("not used in executor tests")
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

// MARK: - Helpers

private func makeRecord(entity: String, op: String, payloadData: Data = Data("{}".utf8)) -> SyncQueueRecord {
    SyncQueueRecord(
        op: op,
        entity: entity,
        payload: String(data: payloadData, encoding: .utf8) ?? "{}"
    )
}

private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
}

// MARK: - PosSyncOpExecutorTests

@Suite("PosSyncOpExecutor")
struct PosSyncOpExecutorTests {

    // MARK: - Dispatch by kind

    @Test("dispatches pos.sale.finalize to /pos/sale/finalize")
    func dispatchFinalizeSale() async throws {
        let api = MockPosAPIClient()
        let executor = PosSyncOpExecutor(api: api)

        let sale = PosSalePayload(
            items: [],
            customerId: nil,
            subtotalCents: 1000,
            discountCents: 0,
            taxCents: 80,
            tipCents: 0,
            feesCents: 0,
            feesLabel: nil,
            totalCents: 1080,
            cashSessionId: nil,
            idempotencyKey: UUID().uuidString
        )
        let payloadData = try encode(sale)
        let record = makeRecord(entity: "pos", op: "sale.finalize", payloadData: payloadData)
        try await executor.execute(record)
        let paths = await api.recorded()
        #expect(paths.contains("/pos/sale/finalize"))
    }

    @Test("dispatches pos.return.create to /pos/returns")
    func dispatchCreateReturn() async throws {
        let api = MockPosAPIClient()
        let executor = PosSyncOpExecutor(api: api)

        let ret = PosReturnPayload(
            originalInvoiceId: 123,
            items: [PosReturnLinePayload(inventoryItemId: 1, name: "Widget", quantity: 1, refundCents: 500)],
            reasonCode: "defective",
            notes: nil
        )
        let payloadData = try encode(ret)
        let record = makeRecord(entity: "pos", op: "return.create", payloadData: payloadData)
        try await executor.execute(record)
        let paths = await api.recorded()
        #expect(paths.contains("/pos/returns"))
    }

    @Test("dispatches pos.cash.opening to /pos/cash/sessions/open")
    func dispatchCashOpening() async throws {
        let api = MockPosAPIClient()
        let executor = PosSyncOpExecutor(api: api)

        let opening = CashOpeningPayload(cashierId: 1, openingFloatCents: 20000, openedAt: Date())
        let payloadData = try encode(opening)
        let record = makeRecord(entity: "pos", op: "cash.opening", payloadData: payloadData)
        try await executor.execute(record)
        let paths = await api.recorded()
        #expect(paths.contains("/pos/cash/sessions/open"))
    }

    // MARK: - Unknown kind raises dead-letter

    @Test("unknown op kind throws AppError.syncDeadLetter")
    func unknownKindThrowsDeadLetter() async throws {
        let api = MockPosAPIClient()
        let executor = PosSyncOpExecutor(api: api)
        let record = makeRecord(entity: "pos", op: "something.unknown")
        do {
            try await executor.execute(record)
            Issue.record("Expected error to be thrown for unknown kind")
        } catch let AppError.syncDeadLetter(_, reason) {
            #expect(reason.contains("Unknown POS op kind"))
        } catch {
            Issue.record("Expected AppError.syncDeadLetter, got \(error)")
        }
    }

    // MARK: - Conflict → dead letter

    @Test("409 on pos.sale.finalize throws AppError.conflict")
    func conflictOnFinalizeSale() async throws {
        let api = MockPosAPIClient()
        await api.setStubError(APITransportError.httpStatus(409, message: "Items already sold"))
        let executor = PosSyncOpExecutor(api: api)

        let sale = PosSalePayload(
            items: [], customerId: nil, subtotalCents: 100,
            discountCents: 0, taxCents: 0, tipCents: 0, feesCents: 0,
            feesLabel: nil, totalCents: 100, cashSessionId: nil,
            idempotencyKey: UUID().uuidString
        )
        let payloadData = try encode(sale)
        let record = makeRecord(entity: "pos", op: "sale.finalize", payloadData: payloadData)
        do {
            try await executor.execute(record)
            Issue.record("Expected AppError.conflict")
        } catch let AppError.conflict(reason) {
            #expect(reason != nil)
        } catch {
            Issue.record("Expected AppError.conflict, got \(error)")
        }
    }

    // MARK: - Decoding failure

    @Test("malformed payload throws AppError.decoding")
    func malformedPayloadThrowsDecoding() async throws {
        let api = MockPosAPIClient()
        let executor = PosSyncOpExecutor(api: api)
        let record = makeRecord(entity: "pos", op: "sale.finalize", payloadData: Data("not-json".utf8))
        do {
            try await executor.execute(record)
            Issue.record("Expected AppError.decoding")
        } catch let AppError.decoding(type, _) {
            #expect(type.contains("pos"))
        } catch {
            Issue.record("Expected AppError.decoding, got \(error)")
        }
    }
}

// MARK: - MockPosAPIClient helpers

extension MockPosAPIClient {
    func setStubError(_ error: Error?) {
        stubError = error
    }
}
