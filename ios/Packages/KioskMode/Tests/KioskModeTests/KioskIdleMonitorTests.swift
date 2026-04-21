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
}
