import XCTest
@testable import Core

// §28 Security & Privacy helpers — BiometricLockTimeoutPolicy state machine tests

final class BiometricLockTimeoutPolicyTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a policy with a controllable clock.
    private func makePolicy(
        timeout: TimeInterval = 300,
        startDate: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> (BiometricLockTimeoutPolicy, currentDate: Box<Date>) {
        let box = Box(startDate)
        let policy = BiometricLockTimeoutPolicy(timeout: timeout, now: { box.value })
        return (policy, box)
    }

    // MARK: - Initial state

    func test_initialState_isAuthenticated() {
        let (policy, _) = makePolicy()
        XCTAssertEqual(policy.state, .authenticated)
        XCTAssertFalse(policy.requiresReAuthentication)
    }

    // MARK: - Background transition

    func test_appDidEnterBackground_transitionsToBackgrounded() {
        let (policy, clock) = makePolicy()
        let now = clock.value
        policy.appDidEnterBackground()
        XCTAssertEqual(policy.state, .backgrounded(since: now))
    }

    func test_appDidEnterBackground_whenAlreadyBackgrounded_isNoop() {
        let (policy, clock) = makePolicy()
        policy.appDidEnterBackground()
        let firstBackgroundDate = clock.value

        // Advance clock and call again — state must not change.
        clock.value = clock.value.addingTimeInterval(30)
        policy.appDidEnterBackground()

        XCTAssertEqual(policy.state, .backgrounded(since: firstBackgroundDate))
    }

    func test_appDidEnterBackground_whenRequiresReAuth_isNoop() {
        let (policy, clock) = makePolicy(timeout: 60)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(120) // exceed timeout
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .requiresReAuthentication)

        // Calling background again while locked should not change state.
        policy.appDidEnterBackground()
        XCTAssertEqual(policy.state, .requiresReAuthentication)
    }

    // MARK: - Foreground within timeout

    func test_foregroundWithinTimeout_restoresAuthenticated() {
        let (policy, clock) = makePolicy(timeout: 300)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(200) // 200 < 300
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .authenticated)
        XCTAssertFalse(policy.requiresReAuthentication)
    }

    func test_foregroundExactlyAtTimeout_isAuthenticated() {
        // Elapsed == timeout means NOT exceeded (strictly greater than triggers lock)
        let (policy, clock) = makePolicy(timeout: 300)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(300)
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .authenticated)
    }

    // MARK: - Foreground after timeout exceeded

    func test_foregroundAfterTimeout_requiresReAuthentication() {
        let (policy, clock) = makePolicy(timeout: 300)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(301) // 301 > 300
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .requiresReAuthentication)
        XCTAssertTrue(policy.requiresReAuthentication)
    }

    func test_foregroundLongAfterTimeout_requiresReAuthentication() {
        let (policy, clock) = makePolicy(timeout: 60)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(3600) // 1 hour
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .requiresReAuthentication)
    }

    // MARK: - markAuthenticated

    func test_markAuthenticated_clearsReAuthRequirement() {
        let (policy, clock) = makePolicy(timeout: 60)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(120)
        policy.appWillEnterForeground()
        XCTAssertTrue(policy.requiresReAuthentication)

        policy.markAuthenticated()
        XCTAssertEqual(policy.state, .authenticated)
        XCTAssertFalse(policy.requiresReAuthentication)
    }

    func test_markAuthenticated_whenAlreadyAuthenticated_isNoop() {
        let (policy, _) = makePolicy()
        policy.markAuthenticated()
        XCTAssertEqual(policy.state, .authenticated)
    }

    // MARK: - Full cycle

    func test_fullCycle_backgroundForegroundReAuthBackground() {
        let (policy, clock) = makePolicy(timeout: 120)

        // 1. Start authenticated
        XCTAssertEqual(policy.state, .authenticated)

        // 2. Background
        policy.appDidEnterBackground()
        XCTAssertNotEqual(policy.state, .authenticated)

        // 3. Return quickly — stays authenticated
        clock.value = clock.value.addingTimeInterval(30)
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .authenticated)

        // 4. Background again and stay too long
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(300)
        policy.appWillEnterForeground()
        XCTAssertTrue(policy.requiresReAuthentication)

        // 5. Re-authenticate
        policy.markAuthenticated()
        XCTAssertEqual(policy.state, .authenticated)
    }

    // MARK: - requiresReAuthentication computed property

    func test_requiresReAuthentication_falseWhenBackgrounded() {
        let (policy, _) = makePolicy()
        policy.appDidEnterBackground()
        XCTAssertFalse(policy.requiresReAuthentication)
    }

    // MARK: - Custom timeout values

    func test_zeroTimeout_alwaysRequiresReAuth() {
        let (policy, clock) = makePolicy(timeout: 0)
        policy.appDidEnterBackground()
        clock.value = clock.value.addingTimeInterval(0.001)
        policy.appWillEnterForeground()
        XCTAssertEqual(policy.state, .requiresReAuthentication)
    }
}

// MARK: - Box helper (mutable clock container)

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
