import Testing
import SwiftUI
@testable import KioskMode

@Suite("BurnInNudgeModifier")
struct BurnInNudgeTests {

    // MARK: - nudgeOffset computation

    @Test("Tick 0 returns zero offset")
    func tick0isZero() {
        let offset = BurnInNudgeModifier.nudgeOffset(for: 0, amplitude: 1.0)
        #expect(offset == .zero)
    }

    @Test("Tick 1 returns positive x offset")
    func tick1PositiveX() {
        let offset = BurnInNudgeModifier.nudgeOffset(for: 1, amplitude: 1.0)
        #expect(offset.width == 1.0)
        #expect(offset.height == 0)
    }

    @Test("Tick 2 returns positive y offset")
    func tick2PositiveY() {
        let offset = BurnInNudgeModifier.nudgeOffset(for: 2, amplitude: 1.0)
        #expect(offset.width == 0)
        #expect(offset.height == 1.0)
    }

    @Test("Tick 3 returns negative x offset")
    func tick3NegativeX() {
        let offset = BurnInNudgeModifier.nudgeOffset(for: 3, amplitude: 1.0)
        #expect(offset.width == -1.0)
        #expect(offset.height == 0)
    }

    @Test("Offsets cycle with period 4")
    func cyclesPeriod4() {
        let amplitude: CGFloat = 0.5
        for base in 0..<4 {
            let a = BurnInNudgeModifier.nudgeOffset(for: base, amplitude: amplitude)
            let b = BurnInNudgeModifier.nudgeOffset(for: base + 4, amplitude: amplitude)
            #expect(a == b, "tick \(base) and \(base + 4) should match")
        }
    }

    @Test("Amplitude scales offset proportionally")
    func amplitudeScaling() {
        let amp1 = BurnInNudgeModifier.nudgeOffset(for: 1, amplitude: 1.0)
        let amp2 = BurnInNudgeModifier.nudgeOffset(for: 1, amplitude: 2.0)
        #expect(amp2.width == amp1.width * 2)
        #expect(amp2.height == amp1.height * 2)
    }

    @Test("Zero amplitude yields zero for all ticks")
    func zeroAmplitude() {
        for tick in 0..<8 {
            let offset = BurnInNudgeModifier.nudgeOffset(for: tick, amplitude: 0)
            #expect(offset == .zero, "tick \(tick) with amplitude 0 should be zero")
        }
    }

    @Test("Custom amplitude matches expectation at tick 2")
    func customAmplitudeTick2() {
        let offset = BurnInNudgeModifier.nudgeOffset(for: 2, amplitude: 0.5)
        #expect(offset.height == 0.5)
        #expect(offset.width == 0)
    }

    @Test("All 4 offsets cover distinct directions")
    func distinctDirections() {
        let amp: CGFloat = 1.0
        let offsets = (0..<4).map { BurnInNudgeModifier.nudgeOffset(for: $0, amplitude: amp) }
        // Ensure all 4 are unique
        let unique = Set(offsets.map { "\($0.width),\($0.height)" })
        #expect(unique.count == 4)
    }
}
