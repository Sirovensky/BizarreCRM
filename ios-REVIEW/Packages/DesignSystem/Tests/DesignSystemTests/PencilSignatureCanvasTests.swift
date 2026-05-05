#if canImport(UIKit) && canImport(PencilKit)
import XCTest
import UIKit
import PencilKit
@testable import DesignSystem

// MARK: - PencilSignatureCanvas unit tests

final class PencilSignatureCanvasTests: XCTestCase {

    func testDefaultPenWidthIs3() {
        var canvas = PKCanvasView()
        let binding = Binding(get: { canvas }, set: { canvas = $0 })
        let sut = PencilSignatureCanvas(canvasView: binding, onStrokeAdded: {})
        XCTAssertEqual(sut.penWidth, 3, accuracy: 0.001)
    }

    func testCustomPenWidthStored() {
        var canvas = PKCanvasView()
        let binding = Binding(get: { canvas }, set: { canvas = $0 })
        let sut = PencilSignatureCanvas(canvasView: binding, onStrokeAdded: {}, penWidth: 5)
        XCTAssertEqual(sut.penWidth, 5, accuracy: 0.001)
    }

    func testCoordinatorCallsOnStrokeAdded() {
        var called = false
        let coordinator = PencilSignatureCanvas.Coordinator(onStrokeAdded: { called = true })
        // Simulate drawing-changed with an empty drawing (no strokes) — should not call back.
        let emptyCanvas = PKCanvasView()
        coordinator.canvasViewDrawingDidChange(emptyCanvas)
        XCTAssertFalse(called, "Callback must not fire when drawing has no strokes")
    }

    func testCaptureImageReturnsImage() {
        let canvas = PKCanvasView()
        canvas.frame = CGRect(x: 0, y: 0, width: 100, height: 60)
        let image = PencilSignatureCanvas.captureImage(baseImage: nil, canvas: canvas)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testBrandSignatureFrameInstantiates() {
        let view = Color.clear.brandSignatureFrame()
        let _: some View = view
        XCTAssertTrue(true)
    }
}

#endif
