import Testing
import Foundation
import Core
@testable import Auth

// MARK: - PasskeyRepository Happy + Error Path Tests
//
// These test MockPasskeyRepository directly as a contract-level check,
// confirming that the protocol interface correctly propagates values and errors.
// LivePasskeyRepository integration is covered by API-level E2E tests.

struct PasskeyRepositoryTests {

    // MARK: - beginRegistration

    @Test func beginRegistration_returnsChallengeFromServer() async throws {
        let repo = MockPasskeyRepository()
        repo.stubbedChallenge = PasskeyChallenge(
            challenge: "abc123",
            rpId: "app.bizarrecrm.com",
            userId: "userId42",
            timeout: 60_000,
            userDisplayName: "Alice"
        )

        let result = try await repo.beginRegistration(username: "alice@example.com")

        #expect(result.challenge == "abc123")
        #expect(result.rpId == "app.bizarrecrm.com")
        #expect(result.userId == "userId42")
        #expect(repo.beginRegistrationCallCount == 1)
    }

    @Test func beginRegistration_whenError_throws() async {
        let repo = MockPasskeyRepository()
        repo.error = AppError.server(statusCode: 500, message: "Internal error")

        await #expect(throws: AppError.self) {
            _ = try await repo.beginRegistration(username: "fail@example.com")
        }
    }

    // MARK: - completeRegistration

    @Test func completeRegistration_returnsCredential() async throws {
        let repo = MockPasskeyRepository()
        let expectedCred = PasskeyCredential(
            id: "cred-99",
            nickname: "iPhone 15 Pro",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: nil,
            deviceType: "iPhone"
        )
        repo.stubbedCredential = expectedCred

        let result = try await repo.completeRegistration(
            credentialId: "cId",
            attestationObject: "att",
            clientDataJSON: "cdj",
            nickname: "iPhone 15 Pro"
        )

        #expect(result.id == "cred-99")
        #expect(result.nickname == "iPhone 15 Pro")
        #expect(repo.lastNickname == "iPhone 15 Pro")
        #expect(repo.completeRegistrationCallCount == 1)
    }

    @Test func completeRegistration_whenUnauthorized_throws() async {
        let repo = MockPasskeyRepository()
        repo.error = AppError.unauthorized

        await #expect(throws: AppError.self) {
            _ = try await repo.completeRegistration(
                credentialId: "x", attestationObject: "y",
                clientDataJSON: "z", nickname: "n"
            )
        }
    }

    // MARK: - beginAuthentication

    @Test func beginAuthentication_withUsername_callsBegin() async throws {
        let repo = MockPasskeyRepository()
        _ = try await repo.beginAuthentication(username: "bob@example.com")
        #expect(repo.beginAuthCallCount == 1)
    }

    @Test func beginAuthentication_withNil_callsBegin() async throws {
        let repo = MockPasskeyRepository()
        _ = try await repo.beginAuthentication(username: nil)
        #expect(repo.beginAuthCallCount == 1)
    }

    @Test func beginAuthentication_whenError_throws() async {
        let repo = MockPasskeyRepository()
        repo.error = AppError.offline

        await #expect(throws: AppError.self) {
            _ = try await repo.beginAuthentication(username: nil)
        }
    }

    // MARK: - completeAuthentication

    @Test func completeAuthentication_returnsToken() async throws {
        let repo = MockPasskeyRepository()
        repo.stubbedToken = PasskeyAuthToken(token: "bearer-xyz", refreshToken: "ref-123", userId: "u1")

        let result = try await repo.completeAuthentication(
            credentialId: "cId", authenticatorData: "ad",
            clientDataJSON: "cdj", signature: "sig", userHandle: "uh"
        )

        #expect(result.token == "bearer-xyz")
        #expect(repo.completeAuthCallCount == 1)
    }

    @Test func completeAuthentication_whenForbidden_throws() async {
        let repo = MockPasskeyRepository()
        repo.error = AppError.forbidden(capability: "webauthn")

        await #expect(throws: AppError.self) {
            _ = try await repo.completeAuthentication(
                credentialId: "x", authenticatorData: "y",
                clientDataJSON: "z", signature: "s", userHandle: nil
            )
        }
    }

    // MARK: - listCredentials

    @Test func listCredentials_returnsAll() async throws {
        let repo = MockPasskeyRepository()
        repo.stubbedCredentials = [
            PasskeyCredential(id: "a", nickname: "iPhone", createdAt: Date(), lastUsedAt: nil, deviceType: nil),
            PasskeyCredential(id: "b", nickname: "iPad", createdAt: Date(), lastUsedAt: nil, deviceType: nil)
        ]

        let result = try await repo.listCredentials()

        #expect(result.count == 2)
        #expect(repo.listCallCount == 1)
    }

    @Test func listCredentials_whenError_throws() async {
        let repo = MockPasskeyRepository()
        repo.error = AppError.unauthorized

        await #expect(throws: AppError.self) {
            _ = try await repo.listCredentials()
        }
    }

    // MARK: - deleteCredential

    @Test func deleteCredential_callsEndpoint() async throws {
        let repo = MockPasskeyRepository()
        try await repo.deleteCredential(id: "cred-42")

        #expect(repo.deleteCallCount == 1)
        #expect(repo.lastDeletedId == "cred-42")
    }

    @Test func deleteCredential_whenNotFound_throws() async {
        let repo = MockPasskeyRepository()
        repo.error = AppError.notFound(entity: "Credential")

        await #expect(throws: AppError.self) {
            try await repo.deleteCredential(id: "missing")
        }
    }
}
