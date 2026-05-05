import Foundation
import Networking
import Core

// MARK: - Protocol

public protocol TwoFactorRepository: Sendable {
    func enroll() async throws -> TwoFactorEnrollResponse
    func verify(code: String) async throws -> TwoFactorVerifyResponse
    func challenge(challengeToken: String, code: String) async throws -> TwoFactorChallengeResponse
    // Self-service 2FA disable removed 2026-04-23 per security policy. Recovery
    // happens via backup-code flow (atomic password + 2FA reset) or super-admin
    // force-disable. See TwoFactorEndpoints.swift header.
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
