#if canImport(AuthenticationServices)
import AuthenticationServices
import Foundation
@testable import Auth

/// Test stub for the AuthorizationControllerProtocol abstraction.
/// Bypasses the OS sheet entirely so PasskeyManager can be unit-tested.
@MainActor
final class MockAuthorizationController: AuthorizationControllerProtocol, @unchecked Sendable {
    // Inject the result or an error before calling performRequests.
    var stubbedResult: ASAuthorization?
    var stubbedError: Error?

    private(set) var performRequestsCallCount = 0
    private(set) var lastRequests: [ASAuthorizationRequest] = []

    func performRequests(_ requests: [ASAuthorizationRequest]) async throws -> ASAuthorization {
        performRequestsCallCount += 1
        lastRequests = requests
        if let err = stubbedError { throw err }
        guard let result = stubbedResult else {
            throw ASAuthorizationError(.unknown)
        }
        return result
    }
}
#endif
