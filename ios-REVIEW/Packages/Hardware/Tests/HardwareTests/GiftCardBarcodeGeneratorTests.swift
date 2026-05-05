import XCTest
@testable import Hardware

// MARK: - GiftCardBarcodeGeneratorTests
//
// Tests for §17.2 "Gift cards: unique Code 128 per card (§40)."

final class GiftCardBarcodeGeneratorTests: XCTestCase {

    private var generator: GiftCardBarcodeGenerator!

    override func setUp() async throws {
        generator = GiftCardBarcodeGenerator()
    }

    // MARK: - generateCardNumber

    func test_generateCardNumber_startsWithGCPrefix() async {
        let number = await generator.generateCardNumber()
        XCTAssertTrue(number.hasPrefix("GC-"),
                      "Card number must start with 'GC-' but got '\(number)'")
    }

    func test_generateCardNumber_hasCorrectFormat() async {
        let number = await generator.generateCardNumber()
        // Format: "GC-" + 16 uppercase hex chars = 19 total characters.
        XCTAssertEqual(number.count, 19, "Card number must be 19 characters (GC-XXXXXXXXXXXXXXXX)")
        let hexPart = String(number.dropFirst(3))
        XCTAssertTrue(hexPart.allSatisfy({ $0.isHexDigit && ($0.isLetter ? $0.isUppercase : true) }),
                      "Hex part must be uppercase hexadecimal: \(hexPart)")
    }

    func test_generateCardNumber_producesUniqueValues() async {
        let n1 = await generator.generateCardNumber()
        let n2 = await generator.generateCardNumber()
        XCTAssertNotEqual(n1, n2, "Two generated card numbers must not be identical (random)")
    }

    // MARK: - generate(for:)

    func test_generate_succeeds_forValidCardNumber() async throws {
        let cardNumber = await generator.generateCardNumber()
        let barcode = try await generator.generate(for: cardNumber)
        XCTAssertEqual(barcode.cardNumber, cardNumber)
        XCTAssertNotNil(barcode.image.cgImage, "Generated barcode must have a valid CGImage")
        XCTAssertEqual(barcode.printPayload.format, .code128)
        XCTAssertEqual(barcode.printPayload.code, cardNumber)
    }

    func test_generate_trims_whitespace() async throws {
        let barcode = try await generator.generate(for: "  GC-AABBCCDDEEFF1122  ")
        XCTAssertEqual(barcode.cardNumber, "GC-AABBCCDDEEFF1122")
    }

    func test_generate_throws_forEmptyString() async {
        do {
            _ = try await generator.generate(for: "")
            XCTFail("Expected GiftCardBarcodeError.emptyCardNumber to be thrown")
        } catch GiftCardBarcodeError.emptyCardNumber {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_generate_throws_forWhitespaceOnlyString() async {
        do {
            _ = try await generator.generate(for: "   ")
            XCTFail("Expected GiftCardBarcodeError.emptyCardNumber to be thrown")
        } catch GiftCardBarcodeError.emptyCardNumber {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_generate_imageIsNonEmpty() async throws {
        let barcode = try await generator.generate(for: "GC-0123456789ABCDEF")
        XCTAssertGreaterThan(barcode.image.size.width, 0)
        XCTAssertGreaterThan(barcode.image.size.height, 0)
    }

    // MARK: - printPayload

    func test_printPayload_format_isCode128() async throws {
        let barcode = try await generator.generate(for: "GC-AAAAAAAAAAAAAAAA")
        XCTAssertEqual(barcode.printPayload.format, .code128)
    }
}
