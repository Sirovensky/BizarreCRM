import XCTest
@testable import Hardware

// MARK: - WeighCaptureViewModelTests
//
// §17 Scale: weigh button + capture + tare + re-weigh.

@MainActor
final class WeighCaptureViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        scale: any WeightScale = StubWeightScale(weight: Weight(grams: 500, isStable: true)),
        capture: ((Weight) -> Void)? = nil
    ) -> WeighCaptureViewModel {
        WeighCaptureViewModel(scale: scale, onCapture: capture ?? { _ in })
    }

    // MARK: - Initial state

    func test_initialDisplayWeight_isDash() {
        let vm = makeVM()
        XCTAssertEqual(vm.displayWeight, "–")
    }

    func test_initialIsStable_isFalse() {
        let vm = makeVM()
        XCTAssertFalse(vm.isStable)
    }

    func test_initialHasCapturedWeight_isFalse() {
        let vm = makeVM()
        XCTAssertFalse(vm.hasCapturedWeight)
    }

    // MARK: - reWeigh resets state

    func test_reWeigh_resetsHasCapturedWeight() async {
        var captured = false
        let vm = makeVM(capture: { _ in captured = true })
        // Start streaming so we get a weight
        await vm.startStreaming()
        try? await Task.sleep(for: .milliseconds(20))
        vm.captureCurrentReading()
        XCTAssertTrue(vm.hasCapturedWeight)
        vm.reWeigh()
        XCTAssertFalse(vm.hasCapturedWeight)
        XCTAssertEqual(vm.displayWeight, "–")
        XCTAssertFalse(vm.isStable)
    }

    // MARK: - captureCurrentReading

    func test_captureCurrentReading_whenStable_callsCallback() async throws {
        var received: Weight?
        let vm = makeVM(
            scale: StubWeightScale(weight: Weight(grams: 750, isStable: true)),
            capture: { received = $0 }
        )
        await vm.startStreaming()
        try await Task.sleep(for: .milliseconds(30))
        vm.captureCurrentReading()
        XCTAssertNotNil(received)
        XCTAssertTrue(vm.hasCapturedWeight)
    }

    func test_captureCurrentReading_whenNotStable_doesNotCapture() {
        let vm = makeVM(scale: StubWeightScale(weight: Weight(grams: 0, isStable: false)))
        vm.captureCurrentReading()
        XCTAssertFalse(vm.hasCapturedWeight)
    }

    // MARK: - tare

    func test_tare_doesNotCrash() async {
        let vm = makeVM(scale: StubWeightScale(weight: Weight(grams: 200, isStable: true)))
        // tare on stub should succeed without throwing
        await vm.tare()
        // No error expected
        XCTAssertNil(vm.errorMessage)
    }

    func test_tare_onNullScale_setsErrorMessage() async {
        let vm = makeVM(scale: NullWeightScale())
        await vm.tare()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Streaming

    func test_streaming_updatesDisplayWeight() async throws {
        let vm = makeVM(scale: StubWeightScale(weight: Weight(grams: 1000, isStable: true)))
        await vm.startStreaming()
        try await Task.sleep(for: .milliseconds(30))
        // Display should no longer be "–" after first reading
        XCTAssertNotEqual(vm.displayWeight, "–")
    }
}

// MARK: - StubWeightScale

/// Deterministic weight scale for testing: emits a single reading then finishes.
struct StubWeightScale: WeightScale {
    let weight: Weight

    func read() async throws -> Weight { weight }

    func stream() -> AsyncStream<Weight> {
        let w = weight
        return AsyncStream { continuation in
            continuation.yield(w)
            continuation.finish()
        }
    }

    func tare() async throws -> Weight { weight }
}
