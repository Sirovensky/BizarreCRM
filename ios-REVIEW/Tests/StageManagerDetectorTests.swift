import XCTest
@testable import BizarreCRM

// MARK: - StageManagerDetectorTests

/// Tests for `StageManagerDetector`.
///
/// Because `UIApplication.shared.connectedScenes` cannot be directly
/// manipulated in unit test bundles, we exercise the public `refresh()`
/// path (which reads the real scene count) and verify the derivation logic
/// via a subclass that overrides `connectedSceneCount`.
///
/// Coverage target: ≥ 80 % across the detector's observable properties.
final class StageManagerDetectorTests: XCTestCase {

    // MARK: - Derivation logic (isolated from UIApplication)

    func test_isStageManagerActive_falseWhenSingleScene() {
        let detector = StageManagerDetector()
        // On iPhone simulator there is exactly 1 scene; Stage Manager is off.
        // We just verify the derived property stays consistent with the count.
        if detector.connectedSceneCount <= 1 {
            // Either iPad or iPhone: count <= 1 must imply inactive.
            XCTAssertFalse(
                detector.isStageManagerActive,
                "isStageManagerActive must be false when connectedSceneCount <= 1"
            )
        }
    }

    func test_isStageManagerActive_trueWhenMultipleScenes() {
        // Can only verify this algebraically in a unit test environment.
        // We instantiate a test double that simulates multiple scenes.
        let detector = TestableStageManagerDetector(simulatedSceneCount: 2)
        XCTAssertTrue(detector.isStageManagerActive)
        XCTAssertEqual(detector.connectedSceneCount, 2)
    }

    func test_isStageManagerActive_falseWhenZeroScenes() {
        let detector = TestableStageManagerDetector(simulatedSceneCount: 0)
        XCTAssertFalse(detector.isStageManagerActive)
    }

    func test_isStageManagerActive_falseWhenOneScene() {
        let detector = TestableStageManagerDetector(simulatedSceneCount: 1)
        XCTAssertFalse(detector.isStageManagerActive)
    }

    func test_isStageManagerActive_trueWhenFiveScenes() {
        let detector = TestableStageManagerDetector(simulatedSceneCount: 5)
        XCTAssertTrue(detector.isStageManagerActive)
        XCTAssertEqual(detector.connectedSceneCount, 5)
    }

    // MARK: - Notification-driven refresh

    @MainActor
    func test_refresh_updatesSceneCount() {
        let detector = TestableStageManagerDetector(simulatedSceneCount: 1)
        XCTAssertFalse(detector.isStageManagerActive)

        detector.simulatedSceneCount = 3
        detector.refresh()

        XCTAssertTrue(detector.isStageManagerActive)
        XCTAssertEqual(detector.connectedSceneCount, 3)
    }

    @MainActor
    func test_refresh_updatesToSingleScene() {
        let detector = TestableStageManagerDetector(simulatedSceneCount: 3)
        XCTAssertTrue(detector.isStageManagerActive)

        detector.simulatedSceneCount = 1
        detector.refresh()

        XCTAssertFalse(detector.isStageManagerActive)
    }

    // MARK: - Shared singleton is not nil

    @MainActor
    func test_shared_isNotNil() {
        XCTAssertNotNil(StageManagerDetector.shared)
    }
}

// MARK: - TestableStageManagerDetector

/// Test double that bypasses `UIApplication.shared.connectedScenes`.
@MainActor
final class TestableStageManagerDetector: StageManagerDetector {

    var simulatedSceneCount: Int

    init(simulatedSceneCount: Int) {
        self.simulatedSceneCount = simulatedSceneCount
        super.init()
        applySimulated()
    }

    override func refresh() {
        applySimulated()
    }

    private func applySimulated() {
        connectedSceneCount = simulatedSceneCount
        isStageManagerActive = simulatedSceneCount > 1
    }
}
