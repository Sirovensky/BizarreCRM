import Foundation
@testable import Networking

/// Minimum-surface APIClient stub. Only the two customer endpoints touched
/// by the view-model tests have canned answers; the rest throw to catch
/// accidental extra calls. Mirrors the pattern in
/// `Packages/Auth/Tests/AuthTests/LoginFlowTests.swift`.
actor StubAPIClient: APIClient {
    private let createResult: Result<CreatedResource, Error>?
    private let updateResult: Result<CreatedResource, Error>?

    init(
        createResult: Result<CreatedResource, Error>? = nil,
        updateResult: Result<CreatedResource, Error>? = nil
    ) {
        self.createResult = createResult
        self.updateResult = updateResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard path.hasPrefix("/api/v1/customers"), let result = createResult else {
            throw APITransportError.noBaseURL
        }
        switch result {
        case .success(let created):
            guard let cast = created as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard path.hasPrefix("/api/v1/customers/"), let result = updateResult else {
            throw APITransportError.noBaseURL
        }
        switch result {
        case .success(let updated):
            guard let cast = updated as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
