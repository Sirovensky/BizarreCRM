#if canImport(UIKit)
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Tickets

// MARK: - ExifStripper unit tests

final class ExifStripperTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal JPEG with GPS and timestamp metadata injected via ImageIO.
    private func makeJPEGWithGPS() throws -> Data {
        // 1×1 white pixel as the base JPEG
        let pixel = makeMinimalJPEG()

        guard let source = CGImageSourceCreateWithData(pixel as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("Could not create CGImage for test JPEG")
        }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw XCTSkip("Could not create JPEG destination")
        }

        let gpsDict: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: 37.7749,
            kCGImagePropertyGPSLatitudeRef as String: "N",
            kCGImagePropertyGPSLongitude as String: 122.4194,
            kCGImagePropertyGPSLongitudeRef as String: "W"
        ]
        let exifDict: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String: "2025:01:15 12:00:00"
        ]
        let tiffDict: [String: Any] = [
            kCGImagePropertyTIFFDateTime as String: "2025:01:15 12:00:00"
        ]
        let props: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: gpsDict,
            kCGImagePropertyExifDictionary as String: exifDict,
            kCGImagePropertyTIFFDictionary as String: tiffDict
        ]

        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw XCTSkip("Could not finalize JPEG destination")
        }
        return output as Data
    }

    /// Returns a minimal 1×1 white JPEG without any metadata.
    private func makeMinimalJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return img.jpegData(compressionQuality: 0.5)!
    }

    // MARK: - Tests

    func test_strip_removesGPSDictionary() throws {
        let data = try makeJPEGWithGPS()
        let result = try ExifStripper.strip(from: data)

        // Verify GPS is absent from output
        guard let outSource = CGImageSourceCreateWithData(result.jpegData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(outSource, 0, nil) as? [String: Any] else {
            XCTFail("Could not read output image properties")
            return
        }
        XCTAssertNil(props[kCGImagePropertyGPSDictionary as String], "GPS dictionary should be removed")
    }

    func test_strip_strippedKeysContainsGPS() throws {
        let data = try makeJPEGWithGPS()
        let result = try ExifStripper.strip(from: data)

        XCTAssertTrue(
            result.strippedKeys.contains(kCGImagePropertyGPSDictionary as String),
            "strippedKeys should include GPS key; got \(result.strippedKeys)"
        )
    }

    func test_strip_outputIsValidJPEG() throws {
        let data = try makeJPEGWithGPS()
        let result = try ExifStripper.strip(from: data)

        XCTAssertFalse(result.jpegData.isEmpty, "Output JPEG should not be empty")

        // Verify JPEG magic bytes FF D8
        let magic = result.jpegData.prefix(2)
        XCTAssertEqual(magic[0], 0xFF)
        XCTAssertEqual(magic[1], 0xD8)
    }

    func test_strip_emptyData_throwsInvalidImageData() {
        XCTAssertThrowsError(try ExifStripper.strip(from: Data())) { error in
            guard let stripError = error as? ExifStripError else {
                XCTFail("Expected ExifStripError, got \(error)")
                return
            }
            XCTAssertEqual(stripError, .invalidImageData)
        }
    }

    func test_strip_plainJpegWithoutGPS_succeeds() throws {
        let plain = makeMinimalJPEG()
        let result = try ExifStripper.strip(from: plain)

        XCTAssertFalse(result.jpegData.isEmpty)
        // No GPS to strip — strippedKeys should not contain GPS
        XCTAssertFalse(result.strippedKeys.contains(kCGImagePropertyGPSDictionary as String))
    }

    func test_strip_removesExifDateTimeOriginal() throws {
        let data = try makeJPEGWithGPS()
        let result = try ExifStripper.strip(from: data)

        guard let outSource = CGImageSourceCreateWithData(result.jpegData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(outSource, 0, nil) as? [String: Any],
              let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            // No exif dict at all is also acceptable
            return
        }
        XCTAssertNil(
            exif[kCGImagePropertyExifDateTimeOriginal as String],
            "DateTimeOriginal should be stripped"
        )
    }

    func test_strip_removesTimestampFromTIFF() throws {
        let data = try makeJPEGWithGPS()
        let result = try ExifStripper.strip(from: data)

        guard let outSource = CGImageSourceCreateWithData(result.jpegData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(outSource, 0, nil) as? [String: Any],
              let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] else {
            return
        }
        XCTAssertNil(tiff[kCGImagePropertyTIFFDateTime as String], "TIFF DateTime should be stripped")
    }

    func test_exifStripError_descriptions_areNonEmpty() {
        let errors: [ExifStripError] = [
            .invalidImageData,
            .cgImageSourceCreationFailed,
            .cgImageSourceCopyFailed,
            .destinationCreationFailed,
            .destinationFinalizationFailed
        ]
        for err in errors {
            XCTAssertFalse(
                err.errorDescription?.isEmpty ?? true,
                "Error description should not be empty for \(err)"
            )
        }
    }
}
#endif
