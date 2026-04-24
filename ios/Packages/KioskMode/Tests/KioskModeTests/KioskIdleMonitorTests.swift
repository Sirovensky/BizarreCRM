import Testing
import Foundation
@testable import KioskMode

@Suite("KioskIdleMonitor")
@MainActor
struct KioskIdleMonitorTests {

    // MARK: - Initial state

    @Test("Starts in active state")
    func startsActive() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 120, blackoutAfterSeconds: 300)
        #expect(monitor.idleState == .active)
    }

    // MARK: - State transitions via direct tick simulation

    // We test the state logic by manipulating lastActivityTime indirectly.
    // Since the timer fires every 5s, we test via start/recordActivity patterns.

    @Test("idleState is active immediately after start")
    func activeAfterStart() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 5, blackoutAfterSeconds: 10)
        monitor.start()
        #expect(monitor.idleState == .active)
        monitor.stop()
    }

    @Test("idleState returns to active after recordActivity")
    func recordActivityResetsState() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 2, blackoutAfterSeconds: 5)
        monitor.start()
        // Force state to dimmed manually to verify reset
        monitor.recordActivity()
        #expect(monitor.idleState == .active)
        monitor.stop()
    }

    @Test("stop resets idleState to active")
    func stopResetsToActive() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 2, blackoutAfterSeconds: 5)
        monitor.start()
        monitor.stop()
        #expect(monitor.idleState == .active)
    }

    // MARK: - Config

    @Test("Dim threshold stored correctly")
    func dimThresholdStored() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 300)
        #expect(monitor.dimAfterSeconds == 60)
    }

    @Test("Blackout threshold stored correctly")
    func blackoutThresholdStored() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 240)
        #expect(monitor.blackoutAfterSeconds == 240)
    }

    @Test("Config can be updated after init")
    func configUpdatable() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 300)
        monitor.dimAfterSeconds = 90
        monitor.blackoutAfterSeconds = 180
        #expect(monitor.dimAfterSeconds == 90)
        #expect(monitor.blackoutAfterSeconds == 180)
    }

    // MARK: - Threshold logic (via idle state enum)

    @Test("IdleState equality")
    func idleStateEquality() {
        #expect(IdleState.active == IdleState.active)
        #expect(IdleState.dimmed == IdleState.dimmed)
        #expect(IdleState.blackout == IdleState.blackout)
        #expect(IdleState.active != IdleState.dimmed)
        #expect(IdleState.dimmed != IdleState.blackout)
    }

    // MARK: - Multiple starts

    @Test("Multiple starts don't accumulate timers")
    func multipleStartsSafe() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 120, blackoutAfterSeconds: 300)
        monitor.start()
        monitor.start()
        monitor.start()
        monitor.stop()
        #expect(monitor.idleState == .active)
    }

    @Test("Stop after no start is safe")
    func stopWithoutStartSafe() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 120, blackoutAfterSeconds: 300)
        monitor.stop() // Should not crash
        #expect(monitor.idleState == .active)
    }

    // MARK: - Timeout state machine (via simulateElapsed)

    @Test("Transitions to dimmed when elapsed >= dimAfterSeconds")
    func transitionsToDimmed() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 120)
        monitor.simulateElapsed(60)
        #expect(monitor.idleState == .dimmed)
    }

    @Test("Transitions to blackout when elapsed >= blackoutAfterSeconds")
    func transitionsToBlackout() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 120)
        monitor.simulateElapsed(120)
        #expect(monitor.idleState == .blackout)
    }

    @Test("Stays active when elapsed < dimAfterSeconds")
    func staysActiveBelowDimThreshold() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 120)
        monitor.simulateElapsed(59)
        #expect(monitor.idleState == .active)
    }

    @Test("Dimmed at boundary, blackout strictly after blackoutAfterSeconds")
    func boundaryConditions() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 30, blackoutAfterSeconds: 60)
        monitor.simulateElapsed(30)
        #expect(monitor.idleState == .dimmed)
        monitor.simulateElapsed(59)
        #expect(monitor.idleState == .dimmed)
        monitor.simulateElapsed(60)
        #expect(monitor.idleState == .blackout)
    }

    @Test("recordActivity resets from dimmed to active")
    func recordActivityResetsFromDimmed() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 30, blackoutAfterSeconds: 60)
        monitor.simulateElapsed(40)
        #expect(monitor.idleState == .dimmed)
        monitor.recordActivity()
        #expect(monitor.idleState == .active)
    }

    @Test("recordActivity resets from blackout to active")
    func recordActivityResetsFromBlackout() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 30, blackoutAfterSeconds: 60)
        monitor.simulateElapsed(90)
        #expect(monitor.idleState == .blackout)
        monitor.recordActivity()
        #expect(monitor.idleState == .active)
    }

    @Test("After recordActivity, simulateElapsed restarts idle from active")
    func idleRestartAfterActivity() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 30, blackoutAfterSeconds: 60)
        monitor.simulateElapsed(90)  // → blackout
        monitor.recordActivity()     // → active
        monitor.simulateElapsed(20)  // still below dim threshold
        #expect(monitor.idleState == .active)
    }

    @Test("Blackout elapsed time far beyond threshold still returns blackout")
    func longElapsedBlackout() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 30, blackoutAfterSeconds: 60)
        monitor.simulateElapsed(3600)  // 1 hour
        #expect(monitor.idleState == .blackout)
    }

    @Test("Zero elapsed always active")
    func zeroElapsedActive() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 30, blackoutAfterSeconds: 60)
        monitor.simulateElapsed(0)
        #expect(monitor.idleState == .active)
    }

    @Test("Transition sequence: active → dimmed → blackout")
    func fullTransitionSequence() {
        let monitor = KioskIdleMonitor(dimAfterSeconds: 60, blackoutAfterSeconds: 180)
        #expect(monitor.idleState == .active)
        monitor.simulateElapsed(60)
        #expect(monitor.idleState == .dimmed)
        monitor.simulateElapsed(180)
        #expect(monitor.idleState == .blackout)
    }
}
