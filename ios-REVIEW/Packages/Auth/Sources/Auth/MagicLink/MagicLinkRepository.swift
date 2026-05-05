import Foundation
import Networking
import Core

// MARK: - Protocol

public protocol MagicLinkRepository: Sendable {
    func requestLink(email: String) async throws -> MagicLinkRequestResponse
    func verifyToken(_ token: String) async throws -> MagicLinkVerifyResponse
}

// MARK: - Live implementation

public actor LiveMagicLinkRepository: MagicLinkRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func requestLink(email: String) async throws -> MagicLinkRequestResponse {
        do {
            return try await api.magicLinkRequest(email: email)
        } catch {
            throw AppError.from(error)
        }
    }

    public func verifyToken(_ token: String) async throws -> MagicLinkVerifyResponse {
        do {
            return try await api.magicLinkVerify(token: token)
        } catch {
            throw AppError.from(error)
        }
    }
}
