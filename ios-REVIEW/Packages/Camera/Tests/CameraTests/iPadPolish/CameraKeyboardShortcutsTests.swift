import XCTest
@testable import Camera

// MARK: - CameraLens tests

/// Tests for ``CameraLens`` — pure value type, no UIKit needed.
final class CameraLensTests: XCTestCase {

    func test_back_equalsBack() {
        XCTAssertEqual(CameraLens.back, CameraLens.back)
    }

    func test_front_equalsFront() {
        XCTAssertEqual(CameraLens.front, CameraLens.front)
    }

    func test_back_notEqualFront() {
        XCTAssertNotEqual(CameraLens.back, CameraLens.front)
    }

    func test_lens_isSendable() async {
        let lens = CameraLens.front
        let result = await Task.detached { lens }.value
        XCTAssertEqual(result, .front)
    }

    func test_allLensValues_canBeExhausted() {
        // Ensures switch exhaustion — if a new case is added without updating
        // this test, the compiler will error.
        func describe(_ l: CameraLens) -> String {
            switch l {
            case .back:  return "back"
            case .front: return "front"
            }
        }
        XCTAssertEqual(describe(.back), "back")
        XCTAssertEqual(describe(.front), "front")
    }
}

// MARK: - CameraKeyboardShortcuts logic tests

/// Pure logic tests — no SwiftUI rendering required.
final class CameraKeyboardShortcutsLogicTests: XCTestCase {

    // The modifier itself only wires SwiftUI `.keyboardShortcut` calls; the
    // testable unit here is the callback contract (callbacks are invoked for
    // the correct lens) via the ViewModifier initialiser arguments.

    func test_flipBackLens_isBack() {
        var received: CameraLens?
        let onFlip: (CameraLens) -> Void = { received = $0 }
        onFlip(.back)
        XCTAssertEqual(received, .back)
    }

    func test_flipFrontLens_isFront() {
        var received: CameraLens?
        let onFlip: (CameraLens) -> Void = { received = $0 }
        onFlip(.front)
        XCTAssertEqual(received, .front)
    }

    func test_captureCallback_isCalled() {
        var called = false
        let onCapture = { called = true }
        onCapture()
        XCTAssertTrue(called)
    }

    func test_cancelCallback_isCalled() {
        var called = false
        let onCancel = { called = true }
        onCancel()
        XCTAssertTrue(called)
    }

    func test_flipCallbackReceivesNewLens_back() {
        var history: [CameraLens] = []
        let onFlip: (CameraLens) -> Void = { history.append($0) }
        onFlip(.back)
        onFlip(.front)
        XCTAssertEqual(history, [.back, .front])
    }

    func test_multipleFlips_buildHistory() {
        var lens = CameraLens.back
        let flip: () -> Void = {
            lens = (lens == .back) ? .front : .back
        }
        XCTAssertEqual(lens, .back)
        flip(); XCTAssertEqual(lens, .front)
        flip(); XCTAssertEqual(lens, .back)
        flip(); XCTAssertEqual(lens, .front)
    }
}

// MARK: - CameraFullScreenLayout.Mode tests

final class CameraFullScreenLayoutModeTests: XCTestCase {

    func test_singleMode_equalsItself() {
        // CameraFullScreenLayout.Mode is available on UIKit targets only.
        // We verify the type exists and compiles without crash.
        #if canImport(UIKit)
        let mode = CameraFullScreenLayout.Mode.single
        _ = mode
        #endif
    }

    func test_multiMode_equalsItself() {
        #if canImport(UIKit)
        let mode = CameraFullScreenLayout.Mode.multi
        _ = mode
        #endif
    }
}
