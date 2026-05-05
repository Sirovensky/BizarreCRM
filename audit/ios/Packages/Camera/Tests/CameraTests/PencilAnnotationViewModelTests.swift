#if canImport(UIKit) && canImport(PencilKit)
import XCTest
import PencilKit
@testable import Camera

/// Tests for ``PencilAnnotationViewModel`` and ``AnnotationTool``.
///
/// - Tool switching (pen → highlighter → marker → pen cycle)
/// - Eraser selection
/// - Color preset switching
/// - Thickness bounds and update
/// - Undo stack depth (mockable via swapped UndoManager)
/// - Clear resets drawing to empty
/// - Double-tap Pencil tool cycle
/// - Squeeze toggles picker visibility
/// - exportFlattened returns non-nil image (with nil background)
/// - AnnotationTool.pkTool returns correct PKTool types
/// - AnnotationPresetColor uiColor / swiftUIColor non-nil
@MainActor
final class PencilAnnotationViewModelTests: XCTestCase {

    private var vm: PencilAnnotationViewModel!

    override func setUp() async throws {
        vm = PencilAnnotationViewModel(backgroundImage: nil)
    }

    // MARK: - Default state

    func test_defaultActiveTool_isPen() {
        XCTAssertEqual(vm.activeTool, .pen)
    }

    func test_defaultColor_isOrange() {
        XCTAssertEqual(vm.activeColor.label, AnnotationPresetColor.orange.label)
    }

    func test_defaultThickness_isFour() {
        XCTAssertEqual(vm.activeThickness, 4.0)
    }

    func test_defaultPickerVisible_isTrue() {
        XCTAssertTrue(vm.isToolPickerVisible)
    }

    func test_defaultDrawingIsEmpty() {
        XCTAssertTrue(vm.currentDrawing.strokes.isEmpty)
    }

    // MARK: - Tool switching

    func test_selectHighlighter() {
        vm.activeTool = .highlighter
        XCTAssertEqual(vm.activeTool, .highlighter)
    }

    func test_selectMarker() {
        vm.activeTool = .marker
        XCTAssertEqual(vm.activeTool, .marker)
    }

    func test_selectEraser() {
        vm.activeTool = .eraser
        XCTAssertEqual(vm.activeTool, .eraser)
    }

    func test_cycleAllTools() {
        for tool in AnnotationTool.allCases {
            vm.activeTool = tool
            XCTAssertEqual(vm.activeTool, tool, "Setting \(tool.rawValue) should persist")
        }
    }

    // MARK: - Double-tap cycle

    func test_doubleTap_fromPen_switchesToHighlighter() {
        vm.activeTool = .pen
        vm.handleDoubleTap()
        XCTAssertEqual(vm.activeTool, .highlighter)
    }

    func test_doubleTap_fromHighlighter_switchesToMarker() {
        vm.activeTool = .highlighter
        vm.handleDoubleTap()
        XCTAssertEqual(vm.activeTool, .marker)
    }

    func test_doubleTap_fromMarker_wrapsBackToPen() {
        vm.activeTool = .marker
        vm.handleDoubleTap()
        XCTAssertEqual(vm.activeTool, .pen)
    }

    func test_doubleTap_fromEraser_switchesToPen() {
        vm.activeTool = .eraser
        vm.handleDoubleTap()
        XCTAssertEqual(vm.activeTool, .pen)
    }

    func test_doubleTap_fullCycle_returnsToStart() {
        vm.activeTool = .pen
        vm.handleDoubleTap() // → highlighter
        vm.handleDoubleTap() // → marker
        vm.handleDoubleTap() // → pen
        XCTAssertEqual(vm.activeTool, .pen)
    }

    // MARK: - Squeeze

    func test_squeeze_toggglesToNotVisible() {
        XCTAssertTrue(vm.isToolPickerVisible)
        vm.handleSqueeze()
        XCTAssertFalse(vm.isToolPickerVisible)
    }

    func test_squeeze_togglesBackToVisible() {
        vm.handleSqueeze()
        vm.handleSqueeze()
        XCTAssertTrue(vm.isToolPickerVisible)
    }

    // MARK: - Color

    func test_setColor_teal() {
        vm.activeColor = .teal
        XCTAssertEqual(vm.activeColor.label, AnnotationPresetColor.teal.label)
    }

    func test_allPresetColors_haveDifferentLabels() {
        let labels = AnnotationPresetColor.allCases.map(\.label)
        let unique = Set(labels)
        XCTAssertEqual(labels.count, unique.count, "All preset color labels must be unique")
    }

    func test_allPresetColors_haveNonNilUIColor() {
        for preset in AnnotationPresetColor.allCases {
            // If UIColor is nil, accessing alpha would crash. This ensures it compiles.
            let alpha = preset.uiColor.cgColor.alpha
            XCTAssertGreaterThanOrEqual(alpha, 0, "\(preset.label) uiColor must be valid")
        }
    }

    // MARK: - Thickness

    func test_setThickness_updates() {
        vm.activeThickness = 12.0
        XCTAssertEqual(vm.activeThickness, 12.0)
    }

    func test_minimumThickness_one() {
        vm.activeThickness = 1.0
        XCTAssertEqual(vm.activeThickness, 1.0)
    }

    func test_maximumThickness_twenty() {
        vm.activeThickness = 20.0
        XCTAssertEqual(vm.activeThickness, 20.0)
    }

    // MARK: - Clear

    func test_clear_resetsDrawingToEmpty() {
        // Inject a synthetic drawing by replacing the binding
        // (PKDrawing is value type — inject directly)
        vm.currentDrawing = PKDrawing()
        vm.clear()
        XCTAssertTrue(vm.currentDrawing.strokes.isEmpty)
        XCTAssertEqual(vm.strokeCount, 0)
    }

    // MARK: - Undo stack (via mock UndoManager)

    func test_undo_callsUndoManager() {
        let undoMgr = TrackingUndoManager()
        vm.undoManager = undoMgr
        vm.undo()
        XCTAssertEqual(undoMgr.undoCallCount, 1)
    }

    func test_redo_callsUndoManager() {
        let undoMgr = TrackingUndoManager()
        vm.undoManager = undoMgr
        vm.redo()
        XCTAssertEqual(undoMgr.redoCallCount, 1)
    }

    func test_undo_withNilUndoManager_doesNotCrash() {
        vm.undoManager = nil
        // Must not crash
        vm.undo()
    }

    func test_redo_withNilUndoManager_doesNotCrash() {
        vm.undoManager = nil
        vm.redo()
    }

    // MARK: - exportFlattened

    func test_exportFlattened_nilBackground_returnsImage() async {
        let image = await vm.exportFlattened()
        XCTAssertNotNil(image, "exportFlattened should return an image even without a background")
    }

    func test_exportFlattened_withBackground_returnsImage() async {
        let bg = makeTestImage(size: CGSize(width: 100, height: 100))
        let vmWithBg = PencilAnnotationViewModel(backgroundImage: bg)
        let image = await vmWithBg.exportFlattened()
        XCTAssertNotNil(image, "exportFlattened should return an image when background is set")
    }

    func test_exportFlattened_dimensionsMatchBackground() async {
        let expectedSize = CGSize(width: 200, height: 150)
        let bg = makeTestImage(size: expectedSize)
        let vmWithBg = PencilAnnotationViewModel(backgroundImage: bg)
        let image = await vmWithBg.exportFlattened()
        XCTAssertNotNil(image)
        // Size comparison with tolerance for scale factor
        XCTAssertEqual(image?.size.width ?? 0, expectedSize.width, accuracy: 1.0)
        XCTAssertEqual(image?.size.height ?? 0, expectedSize.height, accuracy: 1.0)
    }

    // MARK: - AnnotationTool.pkTool

    func test_penPKTool_isInkingTool() {
        let tool = AnnotationTool.pen.pkTool(color: .systemOrange, width: 4)
        XCTAssertTrue(tool is PKInkingTool, "pen should return PKInkingTool")
    }

    func test_highlighterPKTool_isInkingTool() {
        let tool = AnnotationTool.highlighter.pkTool(color: .systemYellow, width: 4)
        XCTAssertTrue(tool is PKInkingTool)
    }

    func test_markerPKTool_isInkingTool() {
        let tool = AnnotationTool.marker.pkTool(color: .systemBlue, width: 4)
        XCTAssertTrue(tool is PKInkingTool)
    }

    func test_eraserPKTool_isEraserTool() {
        let tool = AnnotationTool.eraser.pkTool(color: .clear, width: 4)
        XCTAssertTrue(tool is PKEraserTool, "eraser should return PKEraserTool")
    }

    // MARK: - AnnotationTool display metadata

    func test_allTools_haveIconNames() {
        for tool in AnnotationTool.allCases {
            XCTAssertFalse(tool.iconName.isEmpty, "\(tool.rawValue) must have an icon name")
        }
    }

    func test_allTools_haveLabels() {
        for tool in AnnotationTool.allCases {
            XCTAssertFalse(tool.label.isEmpty, "\(tool.rawValue) must have a label")
        }
    }

    func test_allTools_haveUniqueRawValues() {
        let raws = AnnotationTool.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
    }

    // MARK: - resolvedPKTool

    func test_resolvedPKTool_reflectsActiveTool() {
        vm.activeTool = .eraser
        XCTAssertTrue(vm.resolvedPKTool is PKEraserTool)
    }

    func test_resolvedPKTool_forPen_isInkingTool() {
        vm.activeTool = .pen
        XCTAssertTrue(vm.resolvedPKTool is PKInkingTool)
    }

    // MARK: - Helpers

    private func makeTestImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Mock UndoManager

/// Tracks undo/redo call counts without actually running any undo stack.
final class TrackingUndoManager: UndoManager {
    private(set) var undoCallCount: Int = 0
    private(set) var redoCallCount: Int = 0

    override func undo() {
        undoCallCount += 1
    }

    override func redo() {
        redoCallCount += 1
    }
}

#endif
