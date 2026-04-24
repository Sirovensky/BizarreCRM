import XCTest
@testable import Pos

/// §Agent-E — Logic tests for `PosCartCollapseModifier` that can run without
/// a simulator host (no SwiftUI rendering, just the math the modifier expresses).
///
/// Since `ViewModifier.body(content:)` requires a concrete SwiftUI render
/// pass, we test the modifier's observable invariants:
/// - The collapsed width target is 0.
/// - The expanded width target is 420.
/// - The reduce-motion animation is the linear 150ms fallback.
/// - The spring animation is .spring(response:0.24, dampingFraction:0.8).
final class PosCartCollapseModifierTests: XCTestCase {

    // MARK: - §1: Collapsed width is 0

    func test_collapseModifier_collapsedWidth_isZero() {
        // The modifier's collapsed target is a constant in the source.
        // We verify the constant rather than executing SwiftUI rendering.
        XCTAssertEqual(PosCartCollapseModifier.collapsedWidth, 0)
    }

    // MARK: - §2: Expanded width is 420

    func test_collapseModifier_expandedWidth_is420() {
        XCTAssertEqual(PosCartCollapseModifier.expandedWidth, 420)
    }

    // MARK: - §3: Normal motion spring response is 0.24

    func test_collapseModifier_springResponse_is024() {
        XCTAssertEqual(PosCartCollapseModifier.springResponse, 0.24, accuracy: 0.001)
    }

    // MARK: - §4: Normal motion spring damping is 0.8

    func test_collapseModifier_springDamping_is08() {
        XCTAssertEqual(PosCartCollapseModifier.springDampingFraction, 0.8, accuracy: 0.001)
    }

    // MARK: - §5: Reduce-motion fallback duration is 150ms

    func test_collapseModifier_reduceMotionDuration_is150ms() {
        XCTAssertEqual(PosCartCollapseModifier.reduceMotionDuration, 0.15, accuracy: 0.001)
    }
}
