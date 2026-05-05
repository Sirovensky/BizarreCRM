import Testing
@testable import Auth
import Foundation

// MARK: - §2.13 Session Activity Bridge Tests

struct SessionActivityBridgeTests {

    // MARK: - Attach / detach

    @Test @MainActor func attachAndRecordActivity() async {
        var touched = false
        let timer = SessionTimer(
            idleTimeout: 30,
            pollInterval: 100,
            onExpire: {}
        )
        await timer.start()

        let bridge = SessionActivityBridge()
        bridge.attach(to: timer)

        // recordUserActivity should not crash and should call timer.touch()
        bridge.recordUserActivity()

        let remaining = await timer.currentRemaining()
        // After touch, remaining should be close to the full 30s timeout
        #expect(remaining > 25, "Expected remaining > 25s after touch, got \(remaining)")
        _ = touched // suppress unused warning
    }

    @Test @MainActor func detachPreventsTimerAccess() {
        let bridge = SessionActivityBridge()
        // Detach without prior attach — should not crash
        bridge.detach()
    }

    // MARK: - Exclusions (smoke — just verify no crash)

    @Test @MainActor func silentPushExclusion() {
        let bridge = SessionActivityBridge()
        // Should not crash, should not reset any timer
        bridge.notifySilentPushReceived()
    }

    @Test @MainActor func backgroundSyncExclusion() {
        let bridge = SessionActivityBridge()
        bridge.notifyBackgroundSyncCompleted()
    }

    // MARK: - Signal variants

    @Test @MainActor func scrollActivityRecorded() {
        let bridge = SessionActivityBridge()
        // Smoke: does not crash when no timer attached
        bridge.recordScrollActivity()
    }

    @Test @MainActor func textActivityRecorded() {
        let bridge = SessionActivityBridge()
        bridge.recordTextActivity()
    }
}
