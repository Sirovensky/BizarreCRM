import Foundation
@testable import Auth

/// Test double for PasskeyRepository.
/// Configure `.stubbedChallenge`, `.stubbedCredential`, `.stubbedToken`,
/// or `.error` to drive specific paths.
final class MockPasskeyRepository: PasskeyRepository, @unchecked Sendable {
    // MARK: Stubs
    var stubbedChallenge = PasskeyChallenge(
        challenge: "dGVzdGNoYWxsZW5nZQ",  // "testchallenge" base64url
        rpId: "app.bizarrecrm.com",
        userId: "dXNlcjEyMw",              // "user123"
        timeout: 60_000,
        userDisplayName: "Test User"
    )
    var stubbedCredential = PasskeyCredential(
        id: "cred-1",
        nickname: "iPhone 15",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastUsedAt: nil,
        deviceType: "iPhone"
    )
    var stubbedToken = PasskeyAuthToken(
        token: "tok-abc123",
        refreshToken: "ref-xyz",
        userId: "user-1"
    )
    var stubbedCredentials: [PasskeyCredential] = []
    var error: Error?

    // MARK: Call tracking
    private(set) var beginRegistrationCallCount = 0
    private(set) var completeRegistrationCallCount = 0
    private(set) var beginAuthCallCount = 0
    private(set) var completeAuthCallCount = 0
    private(set) var listCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastDeletedId: String?
    private(set) var lastNickname: String?

    // MARK: Protocol conformance

    func beginRegistration(username: String) async throws -> PasskeyChallenge {
        beginRegistrationCallCount += 1
        if let err = error { throw err }
        return stubbedChallenge
    }

    func completeRegistration(
        credentialId: String,
        attestationObject: String,
        clientDataJSON: String,
        nickname: String
    ) async throws -> PasskeyCredential {
        completeRegistrationCallCount += 1
        lastNickname = nickname
        if let err = error { throw err }
        return stubbedCredential
    }

    func beginAuthentication(username: String?) async throws -> PasskeyChallenge {
        beginAuthCallCount += 1
        if let err = error { throw err }
        return stubbedChallenge
    }

    func completeAuthentication(
        credentialId: String,
        authenticatorData: String,
        clientDataJSON: String,
        signature: String,
        userHandle: String?
    ) async throws -> PasskeyAuthToken {
        completeAuthCallCount += 1
        if let err = error { throw err }
        return stubbedToken
    }

    func listCredentials() async throws -> [PasskeyCredential] {
        listCallCount += 1
        if let err = error { throw err }
        return stubbedCredentials
    }

    func deleteCredential(id: String) async throws {
        deleteCallCount += 1
        lastDeletedId = id
        if let err = error { throw err }
    }
}
