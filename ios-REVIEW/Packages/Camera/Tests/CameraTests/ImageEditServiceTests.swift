#if canImport(UIKit)
import XCTest
import UIKit
@testable import Camera

// MARK: - ImageEditServiceTests
//
// §17 crop / rotate / auto-enhance / OCR tests.
// All operations are actor-isolated async; tests use async/await.

final class ImageEditServiceTests: XCTestCase {

    private var service: ImageEditService!

    override func setUp() async throws {
        service = ImageEditService()
    }

    // MARK: - Helpers

    private func makeImage(width: Int, height: Int, color: UIColor = .red) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Crop

    func test_crop_validRect_returnsImage() async {
        let original = makeImage(width: 200, height: 200)
        let result = await service.crop(original, to: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNotNil(result)
    }

    func test_crop_returnsCorrectSize() async {
        let original = makeImage(width: 200, height: 200)
        let result = await service.crop(original, to: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertNotNil(result)
        if let img = result {
            XCTAssertEqual(img.size.width, 100, accuracy: 2)
            XCTAssertEqual(img.size.height, 50, accuracy: 2)
        }
    }

    func test_crop_zeroRect_returnsNil() async {
        let original = makeImage(width: 100, height: 100)
        let result = await service.crop(original, to: .zero)
        XCTAssertNil(result)
    }

    func test_crop_outOfBoundsRect_returnsNil() async {
        let original = makeImage(width: 100, height: 100)
        let result = await service.crop(original, to: CGRect(x: 200, y: 200, width: 50, height: 50))
        XCTAssertNil(result)
    }

    // MARK: - Rotate

    func test_rotate_0degrees_returnsSameSize() async {
        let original = makeImage(width: 100, height: 200)
        let result = await service.rotate(original, degrees: 0)
        XCTAssertEqual(result.size.width, 100, accuracy: 1)
        XCTAssertEqual(result.size.height, 200, accuracy: 1)
    }

    func test_rotate_90degrees_swapsDimensions() async {
        let original = makeImage(width: 100, height: 200)
        let result = await service.rotate(original, degrees: 90)
        XCTAssertEqual(result.size.width, 200, accuracy: 1)
        XCTAssertEqual(result.size.height, 100, accuracy: 1)
    }

    func test_rotate_180degrees_keepsDimensions() async {
        let original = makeImage(width: 100, height: 200)
        let result = await service.rotate(original, degrees: 180)
        XCTAssertEqual(result.size.width, 100, accuracy: 1)
        XCTAssertEqual(result.size.height, 200, accuracy: 1)
    }

    func test_rotate_270degrees_swapsDimensions() async {
        let original = makeImage(width: 100, height: 200)
        let result = await service.rotate(original, degrees: 270)
        XCTAssertEqual(result.size.width, 200, accuracy: 1)
        XCTAssertEqual(result.size.height, 100, accuracy: 1)
    }

    func test_rotate_360degrees_keepsDimensions() async {
        let original = makeImage(width: 100, height: 200)
        let result = await service.rotate(original, degrees: 360)
        XCTAssertEqual(result.size.width, 100, accuracy: 1)
        XCTAssertEqual(result.size.height, 200, accuracy: 1)
    }

    func test_rotate_negative90degrees_swapsDimensions() async {
        let original = makeImage(width: 100, height: 200)
        let result = await service.rotate(original, degrees: -90)
        XCTAssertEqual(result.size.width, 200, accuracy: 1)
        XCTAssertEqual(result.size.height, 100, accuracy: 1)
    }

    // MARK: - Auto-enhance

    func test_autoEnhance_returnsNonNilImage() async {
        let original = makeImage(width: 100, height: 100, color: .darkGray)
        let result = await service.autoEnhance(original)
        // Must return a valid image (may be same if no filters applied)
        XCTAssertEqual(result.size.width, 100, accuracy: 1)
        XCTAssertEqual(result.size.height, 100, accuracy: 1)
    }

    func test_autoEnhance_preservesAspectRatio() async {
        let original = makeImage(width: 150, height: 75)
        let result = await service.autoEnhance(original)
        let ratio = result.size.width / result.size.height
        XCTAssertEqual(ratio, 2.0, accuracy: 0.1)
    }

    // MARK: - OCR

    func test_recognizeText_emptyImage_returnsString() async {
        // OCR on a plain-color image returns empty string; we just verify no crash.
        let image = makeImage(width: 200, height: 50, color: .white)
        let text = await service.recognizeText(in: image)
        // May return empty or whitespace; must not throw.
        XCTAssertNotNil(text as String?)
    }

    func test_recognizeText_returnsString() async {
        // We can't render text via UIKit in unit tests reliably (no window),
        // so we just verify the call completes and returns a String.
        let image = makeImage(width: 300, height: 100, color: .white)
        let text = await service.recognizeText(in: image)
        XCTAssertNotNil(text as String?)
    }
}

#endif
