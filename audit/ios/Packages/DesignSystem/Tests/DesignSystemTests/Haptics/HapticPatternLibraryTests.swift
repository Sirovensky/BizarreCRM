import Testing
import Foundation
@testable import DesignSystem

// §66 — HapticPatternLibrary, HapticPatternCue, ReduceMotionGate tests

// MARK: - Mock helpers

/// Controllable accessibility flags — both on or off.
struct MockAccessibilityFlags: AccessibilityFlagsProviding {
    var isReduceMotionEnabled: Bool
    var isReduceTransparencyEnabled: Bool

    init(reduceMotion: Bool = false, reduceTransparency: Bool = false) {
        self.isReduceMotionEnabled = reduceMotion
        self.isReduceTransparencyEnabled = reduceTransparency
    }
}

/// Records `play(_:)` invocations for assertion.
actor MockHapticPatternPlayer: HapticPatternPlaying {
    private(set) var playedDescriptors: [HapticPatternDescriptor] = []
    var shouldSucceed: Bool = true

    func play(_ descriptor: HapticPatternDescriptor) async -> Bool {
        playedDescriptors.append(descriptor)
        return shouldSucceed
    }

    func reset() {
        playedDescriptors = []
    }
}

// MARK: - HapticPatternLibrary tests

@Suite("HapticPatternLibrary")
struct HapticPatternLibraryTests {

    // All named factory methods must return non-nil descriptors.

    @Test("success descriptor is non-nil")
    func successNonNil() {
        let d = HapticPatternLibrary.success
        #expect(d.name == "success")
    }

    @Test("warning descriptor is non-nil")
    func warningNonNil() {
        let d = HapticPatternLibrary.warning
        #expect(d.name == "warning")
    }

    @Test("error descriptor is non-nil")
    func errorNonNil() {
        let d = HapticPatternLibrary.error
        #expect(d.name == "error")
    }

    @Test("saleComplete descriptor is non-nil")
    func saleCompleteNonNil() {
        let d = HapticPatternLibrary.saleComplete
        #expect(d.name == "saleComplete")
    }

    @Test("cardTap descriptor is non-nil")
    func cardTapNonNil() {
        let d = HapticPatternLibrary.cardTap
        #expect(d.name == "cardTap")
    }

    @Test("deviceConnected descriptor is non-nil")
    func deviceConnectedNonNil() {
        let d = HapticPatternLibrary.deviceConnected
        #expect(d.name == "deviceConnected")
    }

    @Test("barcodeScanned descriptor is non-nil")
    func barcodeScannedNonNil() {
        let d = HapticPatternLibrary.barcodeScanned
        #expect(d.name == "barcodeScanned")
    }

    @Test("notification descriptor is non-nil")
    func notificationNonNil() {
        let d = HapticPatternLibrary.notification
        #expect(d.name == "notification")
    }

    @Test("all eight named patterns have unique names")
    func allPatternsHaveUniqueNames() {
        let patterns: [HapticPatternDescriptor] = [
            HapticPatternLibrary.success,
            HapticPatternLibrary.warning,
            HapticPatternLibrary.error,
            HapticPatternLibrary.saleComplete,
            HapticPatternLibrary.cardTap,
            HapticPatternLibrary.deviceConnected,
            HapticPatternLibrary.barcodeScanned,
            HapticPatternLibrary.notification
        ]
        let names = patterns.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("HapticPatternDescriptor equality is name-based")
    func descriptorEquality() {
        let a = HapticPatternLibrary.success
        let b = HapticPatternLibrary.success
        let c = HapticPatternLibrary.error
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - HapticPatternCue composition tests

@Suite("HapticPatternCue")
struct HapticPatternCueTests {

    @Test("saleTap cue has two steps")
    func saleTapStepCount() {
        #expect(HapticPatternCue.saleTap.steps.count == 2)
    }

    @Test("saleTap first step is cardTap")
    func saleTapFirstStep() {
        #expect(HapticPatternCue.saleTap.steps[0].descriptor == HapticPatternLibrary.cardTap)
    }

    @Test("saleTap second step is success with positive delay")
    func saleTapSecondStep() {
        let step = HapticPatternCue.saleTap.steps[1]
        #expect(step.descriptor == HapticPatternLibrary.success)
        #expect(step.delay > 0)
    }

    @Test("scanAndConfirm cue has two steps")
    func scanAndConfirmStepCount() {
        #expect(HapticPatternCue.scanAndConfirm.steps.count == 2)
    }

    @Test("deviceConnectWelcome cue has two steps")
    func deviceConnectWelcomeStepCount() {
        #expect(HapticPatternCue.deviceConnectWelcome.steps.count == 2)
    }

    @Test("criticalAlert cue has two steps")
    func criticalAlertStepCount() {
        #expect(HapticPatternCue.criticalAlert.steps.count == 2)
    }

    @Test("single(_:) cue has exactly one step")
    func singleCueStepCount() {
        let cue = HapticPatternCue.single(HapticPatternLibrary.notification)
        #expect(cue.steps.count == 1)
    }

    @Test("single(_:) cue name includes descriptor name")
    func singleCueName() {
        let cue = HapticPatternCue.single(HapticPatternLibrary.notification)
        #expect(cue.name.contains("notification"))
    }

    @Test("cue equality is name + steps based")
    func cueEquality() {
        let a = HapticPatternCue.saleTap
        let b = HapticPatternCue.saleTap
        let c = HapticPatternCue.criticalAlert
        #expect(a == b)
        #expect(a != c)
    }

    @Test("cue player calls play for each step via mock")
    func cuePlayerCallsPlayPerStep() async {
        let mock = MockHapticPatternPlayer()
        let cuePlayer = HapticPatternCuePlayer(hapticPlayer: mock)

        // Use a cue whose steps have zero delay to avoid real sleep in tests.
        let zeroCue = HapticPatternCue(
            name: "testZero",
            steps: [
                HapticPatternCue.Step(descriptor: HapticPatternLibrary.cardTap, delay: 0),
                HapticPatternCue.Step(descriptor: HapticPatternLibrary.success, delay: 0)
            ]
        )
        let count = await cuePlayer.play(zeroCue)
        let played = await mock.playedDescriptors
        #expect(played.count == 2)
        #expect(count == 2)
    }

    @Test("cue player returns 0 when mock always fails")
    func cuePlayerZeroOnFailure() async {
        let mock = MockHapticPatternPlayer()
        await mock.play(HapticPatternLibrary.success) // warm up actor
        // Drive failure path
        let failMock = MockHapticPatternPlayer()
        // Override shouldSucceed via separate actor — use a new type:
        let cuePlayer = HapticPatternCuePlayer(hapticPlayer: FailingMockPlayer())
        let zeroCue = HapticPatternCue(
            name: "testFail",
            steps: [
                HapticPatternCue.Step(descriptor: HapticPatternLibrary.error, delay: 0)
            ]
        )
        let count = await cuePlayer.play(zeroCue)
        _ = failMock // silence unused warning
        #expect(count == 0)
    }
}

/// Always returns false from play(_:).
private actor FailingMockPlayer: HapticPatternPlaying {
    func play(_ descriptor: HapticPatternDescriptor) async -> Bool { false }
}

// MARK: - ReduceMotionGate tests

@Suite("ReduceMotionGate")
struct ReduceMotionGateTests {

    @Test("isHapticAllowed is true when both flags are false")
    func allowedWhenNoFlags() {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags())
        #expect(gate.isHapticAllowed == true)
    }

    @Test("isHapticAllowed is false when reduceMotion is true")
    func blockedByReduceMotion() {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags(reduceMotion: true))
        #expect(gate.isHapticAllowed == false)
    }

    @Test("isHapticAllowed is false when reduceTransparency is true")
    func blockedByReduceTransparency() {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags(reduceTransparency: true))
        #expect(gate.isHapticAllowed == false)
    }

    @Test("isHapticAllowed is false when both flags are true")
    func blockedWhenBothFlags() {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags(reduceMotion: true, reduceTransparency: true))
        #expect(gate.isHapticAllowed == false)
    }

    @Test("isReduceMotionActive reflects flag")
    func reduceMotionActiveFlag() {
        let on = ReduceMotionGate(flags: MockAccessibilityFlags(reduceMotion: true))
        let off = ReduceMotionGate(flags: MockAccessibilityFlags(reduceMotion: false))
        #expect(on.isReduceMotionActive == true)
        #expect(off.isReduceMotionActive == false)
    }

    @Test("isReduceTransparencyActive reflects flag")
    func reduceTransparencyActiveFlag() {
        let on = ReduceMotionGate(flags: MockAccessibilityFlags(reduceTransparency: true))
        let off = ReduceMotionGate(flags: MockAccessibilityFlags(reduceTransparency: false))
        #expect(on.isReduceTransparencyActive == true)
        #expect(off.isReduceTransparencyActive == false)
    }

    @Test("play(descriptor:) returns false when gated")
    func playDescriptorGatedReturnsFalse() async {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags(reduceMotion: true))
        let mock = MockHapticPatternPlayer()
        let result = await gate.play(HapticPatternLibrary.success, using: mock)
        let played = await mock.playedDescriptors
        #expect(result == false)
        #expect(played.isEmpty)
    }

    @Test("play(descriptor:) delegates to player when allowed")
    func playDescriptorDelegatesToPlayer() async {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags())
        let mock = MockHapticPatternPlayer()
        _ = await gate.play(HapticPatternLibrary.success, using: mock)
        let played = await mock.playedDescriptors
        #expect(played.count == 1)
        #expect(played[0] == HapticPatternLibrary.success)
    }

    @Test("play(cue:) returns 0 when gated")
    func playCueGatedReturnsZero() async {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags(reduceTransparency: true))
        let mock = MockHapticPatternPlayer()
        let cuePlayer = HapticPatternCuePlayer(hapticPlayer: mock)
        let count = await gate.play(HapticPatternCue.saleTap, using: cuePlayer)
        let played = await mock.playedDescriptors
        #expect(count == 0)
        #expect(played.isEmpty)
    }

    @Test("play(cue:) delegates to cue player when allowed")
    func playCueDelegatesToCuePlayer() async {
        let gate = ReduceMotionGate(flags: MockAccessibilityFlags())
        let mock = MockHapticPatternPlayer()
        let cuePlayer = HapticPatternCuePlayer(hapticPlayer: mock)
        let zeroCue = HapticPatternCue(
            name: "allowedCue",
            steps: [
                HapticPatternCue.Step(descriptor: HapticPatternLibrary.cardTap, delay: 0),
                HapticPatternCue.Step(descriptor: HapticPatternLibrary.success, delay: 0)
            ]
        )
        let count = await gate.play(zeroCue, using: cuePlayer)
        let played = await mock.playedDescriptors
        #expect(played.count == 2)
        #expect(count == 2)
    }
}

// MARK: - HapticPatternPlayer protocol conformance test

@Suite("HapticPatternPlayer protocol")
struct HapticPatternPlayerProtocolTests {

    @Test("HapticPatternPlayer conforms to HapticPatternPlaying")
    func conformance() {
        // Compile-time proof: assignment to protocol variable succeeds.
        let player: any HapticPatternPlaying = HapticPatternPlayer()
        #expect(player is HapticPatternPlayer)
    }

    @Test("MockHapticPatternPlayer records calls")
    func mockRecordsCalls() async {
        let mock = MockHapticPatternPlayer()
        _ = await mock.play(HapticPatternLibrary.barcodeScanned)
        _ = await mock.play(HapticPatternLibrary.notification)
        let played = await mock.playedDescriptors
        #expect(played.count == 2)
        #expect(played[0] == HapticPatternLibrary.barcodeScanned)
        #expect(played[1] == HapticPatternLibrary.notification)
    }
}
