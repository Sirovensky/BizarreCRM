import Foundation
import XCTest
@testable import Tickets
@testable import Networking

// Phase 4 stub for write-flow view model tests.
// Handles: createTicket, addTicketNote, addTicketDevice, updateTicketDevice,
//          updateDeviceChecklist, archiveTicket, assignTicket.

actor Phase4StubAPIClient: APIClient {

    // MARK: - Configurable results

    var createTicketResult: Result<CreatedResource, Error> = .success(.init(id: 99))
    var addNoteResult: Result<AddTicketNoteResponse, Error> =
        .success(AddTicketNoteResponse(id: 1, type: "internal", content: "Test note", isFlagged: false, createdAt: nil))
    var addDeviceResult: Result<CreatedResource, Error> = .success(.init(id: 10))
    var updateDeviceResult: Result<CreatedResource, Error> = .success(.init(id: 10))
    var updateChecklistResult: Result<CreatedResource, Error> = .success(.init(id: 10))
    var archiveResult: Result<ArchiveTicketResponse, Error> =
        .success(ArchiveTicketResponse(success: true, message: nil))
    var assignResult: Result<CreatedResource, Error> = .success(.init(id: 1))
    var updateTicketResult: Result<CreatedResource, Error> = .success(.init(id: 1))

    // MARK: - Tracking

    var postCallCount: Int = 0
    var putCallCount: Int = 0
    var patchCallCount: Int = 0
    var lastPostPath: String = ""
    var lastPutPath: String = ""

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        postCallCount += 1
        lastPostPath = path

        if path.hasSuffix("/notes") {
            switch addNoteResult {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        if path.contains("/devices") && !path.hasSuffix("/checklist") {
            switch addDeviceResult {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        if path.hasSuffix("/archive") {
            switch archiveResult {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        // Default: createTicket
        switch createTicketResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let e): throw e
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        putCallCount += 1
        lastPutPath = path

        if path.contains("/checklist") {
            switch updateChecklistResult {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        if path.contains("/devices/") {
            switch updateDeviceResult {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        // Default: updateTicket
        switch updateTicketResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let e): throw e
        }
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        patchCallCount += 1
        switch assignResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let e): throw e
        }
    }

    func delete(_ path: String) async throws {
        // Route archive/delete via archiveResult so tests can inject failures.
        if path.contains("/tickets/") {
            if case .failure(let e) = archiveResult { throw e }
        }
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - CustomerSummary test helper

extension XCTestCase {
    func makeSampleCustomer(id: Int64 = 1) -> CustomerSummary {
        let json = """
        {
          "id": \(id),
          "first_name": "Ada",
          "last_name": "Lovelace",
          "phone": "5555550101",
          "email": "ada@example.com"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(CustomerSummary.self, from: Data(json.utf8))
    }
}
