import XCTest
@testable import Camera

// MARK: - BarcodeChecksumValidatorTests

final class BarcodeChecksumValidatorTests: XCTestCase {

    // MARK: - EAN-13

    func test_ean13_validChecksum() {
        // Known-valid EAN-13: 4006381333931
        XCTAssertTrue(BarcodeChecksumValidator.validateEAN("4006381333931", expectedLength: 13))
    }

    func test_ean13_invalidChecksum() {
        // Corrupt last digit
        XCTAssertFalse(BarcodeChecksumValidator.validateEAN("4006381333932", expectedLength: 13))
    }

    func test_ean13_wrongLength() {
        XCTAssertFalse(BarcodeChecksumValidator.validateEAN("40063813339", expectedLength: 13))
    }

    // MARK: - EAN-8

    func test_ean8_validChecksum() {
        // Known-valid EAN-8: 73513537
        XCTAssertTrue(BarcodeChecksumValidator.validateEAN("73513537", expectedLength: 8))
    }

    func test_ean8_invalidChecksum() {
        XCTAssertFalse(BarcodeChecksumValidator.validateEAN("73513530", expectedLength: 8))
    }

    // MARK: - ITF-14

    func test_itf14_validChecksum() {
        // Standard ITF-14: 10614141000415
        XCTAssertTrue(BarcodeChecksumValidator.validateEAN("10614141000415", expectedLength: 14))
    }

    func test_itf14_invalidChecksum() {
        XCTAssertFalse(BarcodeChecksumValidator.validateEAN("10614141000416", expectedLength: 14))
    }

    // MARK: - UPC-E validation (digit-only + length)

    func test_upce_valid6DigitString() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertTrue(BarcodeChecksumValidator.validate(value: "012345", symbology: .upce))
    }

    func test_upce_tooShort() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertFalse(BarcodeChecksumValidator.validate(value: "0123", symbology: .upce))
    }

    func test_upce_nonDigits() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertFalse(BarcodeChecksumValidator.validate(value: "01234A", symbology: .upce))
    }

    // MARK: - Pass-through symbologies

    func test_code128_alwaysValid() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertTrue(BarcodeChecksumValidator.validate(value: "ANY-VALUE", symbology: .code128))
    }

    func test_qr_alwaysValid() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertTrue(BarcodeChecksumValidator.validate(value: "https://example.com", symbology: .qr))
    }

    // MARK: - Symbology human-readable names

    func test_humanReadableName_ean13() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertEqual(VNBarcodeSymbology.ean13.humanReadableName, "EAN-13")
    }

    func test_humanReadableName_code128() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertEqual(VNBarcodeSymbology.code128.humanReadableName, "Code 128")
    }
}

// MARK: - BarcodeA11yAnnouncerTests

final class BarcodeA11yAnnouncerTests: XCTestCase {

    func test_announcement_withMatchedItem() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        let result = BarcodeVisionResult(
            value: "4006381333931",
            symbology: .ean13,
            checksumValid: true,
            boundingBox: .zero
        )
        let announcement = BarcodeA11yAnnouncer.announcement(for: result, itemName: "Blue Widget")
        XCTAssertTrue(announcement.contains("EAN-13"))
        XCTAssertTrue(announcement.contains("Blue Widget"))
        XCTAssertFalse(announcement.contains("checksum invalid"))
    }

    func test_announcement_withInvalidChecksum() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        let result = BarcodeVisionResult(
            value: "4006381333932",
            symbology: .ean13,
            checksumValid: false,
            boundingBox: .zero
        )
        let announcement = BarcodeA11yAnnouncer.announcement(for: result, itemName: nil)
        XCTAssertTrue(announcement.contains("checksum invalid"))
    }

    func test_announcement_withNoMatchedItem() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        let result = BarcodeVisionResult(
            value: "ITEM-SKU-001",
            symbology: .code128,
            checksumValid: true,
            boundingBox: .zero
        )
        let announcement = BarcodeA11yAnnouncer.announcement(for: result, itemName: nil)
        XCTAssertTrue(announcement.contains("ITEM-SKU-001"))
    }

    // MARK: - UPC-A (§17 symbologies — added b10)

    func test_upca_validChecksum() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        // Known-valid UPC-A: 012345678905
        XCTAssertTrue(BarcodeChecksumValidator.validate(value: "012345678905", symbology: .upca))
    }

    func test_upca_invalidChecksum() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        // Corrupt last digit
        XCTAssertFalse(BarcodeChecksumValidator.validate(value: "012345678900", symbology: .upca))
    }

    func test_upca_wrongLength() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertFalse(BarcodeChecksumValidator.validate(value: "01234567890", symbology: .upca))
    }

    func test_allSymbologies_contains12Types() {
        // We now support 12 symbologies (EAN-13/8, UPC-A/E, Code 128/39/93, ITF-14, DataMatrix, QR, Aztec, PDF417)
        XCTAssertEqual(BarcodeVisionScanner.allSymbologies.count, 12)
    }

    func test_upca_humanReadableName() throws {
        guard #available(iOS 16, *) else { throw XCTSkip("VNBarcodeSymbology unavailable") }
        XCTAssertEqual(VNBarcodeSymbology.upca.humanReadableName, "UPC-A")
    }
}
