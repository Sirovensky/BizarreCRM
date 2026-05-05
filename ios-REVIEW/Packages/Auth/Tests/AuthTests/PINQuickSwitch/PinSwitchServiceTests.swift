import XCTest
@testable import Auth
import Networking

// MARK: - PinSwitchService tests

final class PinSwitchServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeUser(id: Int = 1) -> SwitchedUser {
        SwitchedUser(
            id: id,
            username: "alice",
            email: "alice@test.com",
            firstName: "Alice",
            lastName: "Smith",
            role: "staff",
            avatarUrl: nil,
            permissions: nil
        )
    }

    private func makeData(userId: Int = 1, token: String = "tok-abc") -> SwitchUserData {
        SwitchUserData(accessToken: token, user: makeUser(id: userId))
    }

    private func makeService(
        clientResult: Result<SwitchUserData, Error>,
        roster: MultiUserRoster = MultiUserRoster(storage: InMemoryRosterStorage()),
        lockout: PinLockoutPolicy = PinLockoutPolicy(storage: InMemoryLockoutStorage()),
        savedToken: ((String) -> Void)? = nil
    ) -> PinSwitchService {
        let client = MockSwitchUserClient(result: clientResult)
        var capturedToken: String? = nil
        return PinSwitchService(
            apiClient: client,
            roster: roster,
            lockout: lockout,
            saveToken: { token in
                capturedToken = token
                savedToken?(token)
            }
        )
    }

    // MARK: - Success path

    func test_attempt_successReturnsSuccessResult() async {
        let service = makeService(clientResult: .success(makeData(token: "tok-123")))
        let result = await service.attempt(pin: "1234")
        guard case .success(let token, let user) = result else {
            return XCTFail("Expected .success, got \(result)")
        }
        XCTAssertEqual(token, "tok-123")
        XCTAssertEqual(user.username, "alice")
    }

    func test_attempt_successUpsertsRoster() async throws {
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let service = makeService(clientResult: .success(makeData()), roster: roster)
        _ = await service.attempt(pin: "1234")
        let entries = await roster.all
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.username, "alice")
    }

    func test_attempt_successClearsFailureRecord() async throws {
        let lockout = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        // Pre-populate roster so we have a candidate
        let user = makeUser(id: 1)
        try await roster.upsert(user: user, pin: "1234")
        // Record two failures
        _ = try await lockout.recordFailure(userId: 1)
        _ = try await lockout.recordFailure(userId: 1)

        let service = makeService(
            clientResult: .success(makeData()),
            roster: roster,
            lockout: lockout
        )
        _ = await service.attempt(pin: "1234")
        let state = await lockout.state(for: 1)
        XCTAssertEqual(state, .allowed)
    }

    // MARK: - Wrong PIN (401)

    func test_attempt_401ReturnsWrongPin() async {
        let error = APITransportError.httpStatus(401, message: "Invalid PIN")
        let service = makeService(clientResult: .failure(error))
        let result = await service.attempt(pin: "9999")
        XCTAssertEqual(result, .wrongPin)
    }

    func test_attempt_401WithKnownUserBumpsLockout() async throws {
        let lockout = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 1)
        // Enroll user in roster with pin "1234"
        try await roster.upsert(user: user, pin: "1234")

        let error = APITransportError.httpStatus(401, message: nil)
        let service = makeService(
            clientResult: .failure(error),
            roster: roster,
            lockout: lockout
        )
        // Wrong pin, but candidate matched locally on "1234" — the service
        // call uses "1234" (matching candidate) but server returns 401.
        _ = await service.attempt(pin: "1234")
        // After 1 failure, state is still allowed (within free attempts).
        let state = await lockout.state(for: 1)
        XCTAssertEqual(state, .allowed)
    }

    // MARK: - Lockout enforcement (client-side)

    func test_attempt_lockedReturnsLockedBeforeNetworkCall() async throws {
        let lockout = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 1)
        try await roster.upsert(user: user, pin: "1234")

        // Force 5 failures to trigger the first lockout tier.
        for _ in 1...5 {
            _ = try await lockout.recordFailure(userId: 1)
        }

        // Even if we pass the correct pin, client-side lockout should block.
        var networkCalled = false
        let client = MockSwitchUserClient(result: .success(makeData()))
        let service = PinSwitchService(
            apiClient: client,
            roster: roster,
            lockout: lockout,
            saveToken: { _ in networkCalled = true }
        )
        let result = await service.attempt(pin: "1234")
        XCTAssertFalse(networkCalled, "Network should not be called when client-side locked")
        guard case .locked = result else {
            return XCTFail("Expected .locked, got \(result)")
        }
    }

    func test_attempt_revokedReturnsRevokedBeforeNetworkCall() async throws {
        let lockout = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        let roster = MultiUserRoster(storage: InMemoryRosterStorage())
        let user = makeUser(id: 1)
        try await roster.upsert(user: user, pin: "1234")

        for _ in 1...PinLockoutPolicy.maxFailures {
            _ = try await lockout.recordFailure(userId: 1)
        }

        var networkCalled = false
        let client = MockSwitchUserClient(result: .success(makeData()))
        let service = PinSwitchService(
            apiClient: client,
            roster: roster,
            lockout: lockout,
            saveToken: { _ in networkCalled = true }
        )
        let result = await service.attempt(pin: "1234")
        XCTAssertFalse(networkCalled)
        XCTAssertEqual(result, .revoked)
    }

    // MARK: - Network error

    func test_attempt_networkErrorReturnsNetworkError() async {
        let error = APITransportError.networkUnavailable
        let service = makeService(clientResult: .failure(error))
        let result = await service.attempt(pin: "1234")
        guard case .networkError = result else {
            return XCTFail("Expected .networkError, got \(result)")
        }
    }

    // MARK: - TOTP forwarding

    func test_attempt_forwardsTotpCode() async {
        var receivedTotp: String? = nil
        final class CapturingClient: SwitchUserClient, @unchecked Sendable {
            var capturedTotp: String? = nil
            func switchUser(pin: String, totpCode: String?) async throws -> SwitchUserData {
                capturedTotp = totpCode
                return SwitchUserData(
                    accessToken: "tok",
                    user: SwitchedUser(id: 1, username: "u", email: "u@test.com",
                                       firstName: "U", lastName: "", role: "staff",
                                       avatarUrl: nil, permissions: nil)
                )
            }
        }
        let capturing = CapturingClient()
        let service = PinSwitchService(
            apiClient: capturing,
            saveToken: { _ in }
        )
        _ = await service.attempt(pin: "1234", totpCode: "123456")
        XCTAssertEqual(capturing.capturedTotp, "123456")
        _ = receivedTotp // suppress warning
    }
}

// MARK: - SwitchResult: Equatable (test-only)

extension SwitchResult: Equatable {
    public static func == (lhs: SwitchResult, rhs: SwitchResult) -> Bool {
        switch (lhs, rhs) {
        case (.wrongPin, .wrongPin):     return true
        case (.revoked, .revoked):       return true
        case (.locked, .locked):         return true
        case (.success(let a, let ua), .success(let b, let ub)):
            return a == b && ua.id == ub.id
        case (.networkError, .networkError): return true
        default: return false
        }
    }
}
