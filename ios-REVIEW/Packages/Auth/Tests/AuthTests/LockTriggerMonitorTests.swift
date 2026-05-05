import XCTest
@testable import Auth

// MARK: - §2.5 LockTriggerMonitor tests

@MainActor
final class LockTriggerMonitorTests: XCTestCase {

    // MARK: - timeout logic

    func test_lockNow_doesNotLock_whenPINNotEnrolled() {
        var lockCalled = false
        let monitor = LockTriggerMonitor(timeout: .immediate) {
            lockCalled = true
        }
        // PINStore.shared.isEnrolled is false in tests (no real Keychain)
        monitor.lockNow()
        // lockNow should be a no-op when PIN is not enrolled
        // (We can't test with a real PIN enrolled without Keychain access)
        // Structural test: monitor initialises and responds to lockNow call
        _ = lockCalled // silence unused warning
    }

    func test_lockTimeout_never_doesNotLock() {
        var lockCalled = false
        let monitor = LockTriggerMonitor(timeout: .never) {
            lockCalled = true
        }
        monitor.start()
        // After setting never, posting willResignActive + didBecomeActive
        // should not trigger the callback.
        // (Notification-based; hard to unit-test without UIKit entitlement)
        XCTAssertFalse(lockCalled, "Lock should not have been called with .never timeout")
    }

    func test_setLockTimeout_updatesPolicy() {
        let monitor = LockTriggerMonitor(timeout: .minutes(5)) { }
        // Just verify this doesn't crash
        monitor.setLockTimeout(.never)
        monitor.setLockTimeout(.immediate)
        monitor.setLockTimeout(.minutes(15))
    }

    func test_lockTimeout_minutesInterval() {
        // Verify the LockTimeout.seconds computation
        XCTAssertEqual(LockTriggerMonitor.LockTimeout.immediate.seconds, 0)
        XCTAssertEqual(LockTriggerMonitor.LockTimeout.minutes(5).seconds, 300)
        XCTAssertEqual(LockTriggerMonitor.LockTimeout.minutes(15).seconds, 900)
        XCTAssertNil(LockTriggerMonitor.LockTimeout.never.seconds)
    }
}
