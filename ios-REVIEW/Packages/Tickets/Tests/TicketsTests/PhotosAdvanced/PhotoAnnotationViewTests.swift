#if canImport(UIKit)
import XCTest
@testable import Tickets

// MARK: - PhotoAnnotationView unit tests
//
// UI views cannot be fully exercised in headless XCTest without a window, so
// these tests focus on the non-UI value types and errors exposed by the module.

final class PhotoAnnotationViewTests: XCTestCase {

    // MARK: - AnnotationError

    func test_annotationError_renderFailed_hasDescription() {
        let err = AnnotationError.renderFailed
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    // MARK: - PhotoAnnotationResult

    func test_photoAnnotationResult_storesPNGData() {
        let data = Data("fake-png-data".utf8)
        let result = PhotoAnnotationResult(compositedPNG: data)
        XCTAssertEqual(result.compositedPNG, data)
    }

    func test_photoAnnotationResult_emptyData_isAccepted() {
        // Model itself has no validation; consumer checks emptiness.
        let result = PhotoAnnotationResult(compositedPNG: Data())
        XCTAssertTrue(result.compositedPNG.isEmpty)
    }

    // MARK: - View instantiation (smoke test)

    @MainActor
    func test_photoAnnotationView_init_doesNotCrash() {
        let image = UIImage(systemName: "photo")!
        var savedResult: PhotoAnnotationResult?
        var cancelled = false

        let view = PhotoAnnotationView(
            photo: image,
            onSave: { result in savedResult = result },
            onCancel: { cancelled = true }
        )

        // The view exists and its callbacks can be stored
        _ = view
        XCTAssertNil(savedResult)
        XCTAssertFalse(cancelled)
    }

    // MARK: - Annotation logic (compositing path is tested indirectly via PDF builder)

    /// Validates that a UIImage can be round-tripped through pngData() —
    /// the same code path used by PhotoAnnotationView.saveAnnotation().
    func test_uiImagePngData_returnsNonNilForValidImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let img = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        XCTAssertNotNil(img.pngData(), "pngData() should succeed on a valid UIImage")
    }
}
#endif
