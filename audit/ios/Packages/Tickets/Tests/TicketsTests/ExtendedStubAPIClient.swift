import Foundation
@testable import Tickets
@testable import Networking

/// Extended stub that handles §4 endpoints: merge, split, sign-off, photos.
actor ExtendedStubAPIClient: APIClient {

    // Configurable results per endpoint
    var mergeResult: Result<MergeResponse, Error>?
    var splitResult: Result<TicketSplitResponse, Error>?
    var signOffResult: Result<SignOffResponse, Error>?
    var detailResult: Result<TicketDetail, Error>?
    var listResult: Result<TicketsListResponse, Error>?
    // §4.4 / §4.5 — delete, duplicate, convert
    var deleteError: Error?
    var duplicateResult: Result<DuplicateTicketResponse, Error>?
    var convertResult: Result<ConvertToInvoiceResponse, Error>?
    var deletedPaths: [String] = []

    init() {}

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/tickets/") && !path.hasSuffix("/split") && !path.hasSuffix("/merge") && !path.hasSuffix("/sign-off") {
            if let result = detailResult {
                switch result {
                case .success(let d):
                    guard let cast = d as? T else { throw APITransportError.decoding("type mismatch") }
                    return cast
                case .failure(let e):
                    throw e
                }
            }
        }
        if path.contains("/tickets") {
            if let result = listResult {
                switch result {
                case .success(let l):
                    guard let cast = l as? T else { throw APITransportError.decoding("type mismatch") }
                    return cast
                case .failure(let e):
                    throw e
                }
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/merge") || path == "/api/v1/tickets/merge" {
            guard let result = mergeResult else { throw APITransportError.noBaseURL }
            switch result {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        if path.hasSuffix("/split") {
            guard let result = splitResult else { throw APITransportError.noBaseURL }
            switch result {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        if path.hasSuffix("/sign-off") {
            guard let result = signOffResult else { throw APITransportError.noBaseURL }
            switch result {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        if path.hasSuffix("/duplicate") {
            guard let result = duplicateResult else { throw APITransportError.noBaseURL }
            switch result {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        if path.hasSuffix("/convert-to-invoice") {
            guard let result = convertResult else { throw APITransportError.noBaseURL }
            switch result {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e): throw e
            }
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {
        deletedPaths.append(path)
        if let err = deleteError { throw err }
    }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
