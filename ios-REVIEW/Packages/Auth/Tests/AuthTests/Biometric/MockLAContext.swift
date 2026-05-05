import Foundation
import LocalAuthentication
@testable import Auth

// MARK: - MockLAContext

/// Controllable `LAContextProtocol` implementation for unit tests.
///
/// Configure the canned responses before calling the service:
/// ```swift
/// let mock = MockLAContext()
/// mock.canEvaluateResult = (true, nil)
/// mock.evaluateResult = .success(true)
/// mock.stubbedBiometryType = .faceID
/// ```
final class MockLAContext: LAContextProtocol, @unchecked Sendable {

    // MARK: - Configurable stubs

    /// Returned by `canEvaluate(policy:)`.
    var canEvaluateResult: (canEvaluate: Bool, error: Error?) = (false, nil)

    /// Returned / thrown by `evaluate(policy:localizedReason:)`.
    var evaluateResult: Result<Bool, Error> = .success(false)

    /// The biometry type reported after `canEvaluate`.
    var stubbedBiometryType: LABiometryType = .none

    // MARK: - Call tracking

    private(set) var canEvaluateCallCount = 0
    private(set) var evaluateCallCount = 0
    private(set) var lastEvaluateReason: String?

    // MARK: - LAContextProtocol

    func canEvaluate(policy: LAPolicy) -> (canEvaluate: Bool, error: Error?) {
        canEvaluateCallCount += 1
        return canEvaluateResult
    }

    func evaluate(policy: LAPolicy, localizedReason: String) async throws -> Bool {
        evaluateCallCount += 1
        lastEvaluateReason = localizedReason
        return try evaluateResult.get()
    }

    var biometryType: LABiometryType { stubbedBiometryType }
}
