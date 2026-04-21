import Foundation
import Networking
import Core

// MARK: - Protocol

public protocol TwoFactorRepository: Sendable {
    func enroll() async throws -> TwoFactorEnrollResponse
    func verify(code: String) async throws -> TwoFactorVerifyResponse
    func challenge(challengeToken: String, code: String) async throws -> TwoFactorChallengeResponse
    func disable(currentPassword: String, totpCode: String) async throws -> TwoFactorDisableResponse
    func regenerateCodes(totpCode: String) async throws -> TwoFactorRegenerateCodesResponse
    func verifyRecovery(code: String) async throws -> TwoFactorVerifyRecoveryResponse
    func status() async throws -> TwoFactorStatusResponse
}

// MARK: - Live implementation

public actor LiveTwoFactorRepository: TwoFactorRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func enroll() async throws -> TwoFactorEnrollResponse {
        do {
            return try await api.twoFactorEnroll()
        } catch {
            throw AppError.from(error)
        }
    }

    public func verify(code: String) async throws -> TwoFactorVerifyResponse {
        do {
            return try await api.twoFactorVerify(code: code)
        } catch {
            throw AppError.from(error)
        }
    }

    public func challenge(challengeToken: String, code: String) async throws -> TwoFactorChallengeResponse {
        do {
            return try await api.twoFactorChallenge(challengeToken: challengeToken, code: code)
        } catch {
            throw AppError.from(error)
        }
    }

    public func disable(currentPassword: String, totpCode: String) async throws -> TwoFactorDisableResponse {
        do {
            return try await api.twoFactorDisable(currentPassword: currentPassword, totpCode: totpCode)
        } catch {
            throw AppError.from(error)
        }
    }

    public func regenerateCodes(totpCode: String) async throws -> TwoFactorRegenerateCodesResponse {
        do {
            return try await api.twoFactorRegenerateCodes(totpCode: totpCode)
        } catch {
            throw AppError.from(error)
        }
    }

    public func verifyRecovery(code: String) async throws -> TwoFactorVerifyRecoveryResponse {
        do {
            return try await api.twoFactorVerifyRecovery(code: code)
        } catch {
            throw AppError.from(error)
        }
    }

    public func status() async throws -> TwoFactorStatusResponse {
        do {
            return try await api.twoFactorStatus()
        } catch {
            throw AppError.from(error)
        }
    }
}
