import XCTest
@testable import Hardware

final class BluetoothWeightScaleTests: XCTestCase {

    // MARK: - SI parsing (kg, resolution 0.005 kg / LSB)

    func test_parse_SI_1000g_rawValue200() {
        // 200 × 5g = 1000g = 1 kg
        let data = Data([0x00, 0xC8, 0x00]) // flags=SI, value=0x00C8=200
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertNotNil(w)
        XCTAssertEqual(w?.grams, 1000)
    }

    func test_parse_SI_500g_rawValue100() {
        // 100 × 5g = 500g
        let data = Data([0x00, 0x64, 0x00]) // flags=SI, value=0x0064=100
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertEqual(w?.grams, 500)
    }

    func test_parse_SI_zero_rawValue0() {
        let data = Data([0x00, 0x00, 0x00])
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertEqual(w?.grams, 0)
    }

    func test_parse_SI_littleEndianHighByte() {
        // value = 0x0100 = 256 → 256 × 5g = 1280g
        let data = Data([0x00, 0x00, 0x01]) // flags=SI, low=0x00, high=0x01
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertEqual(w?.grams, 1280)
    }

    // MARK: - Imperial parsing (lb, resolution 0.01 lb / LSB)

    func test_parse_imperial_100rawValue() {
        // flag bit 0 = 1 → imperial
        // 100 × 0.01 lb = 1 lb = 453 g
        let data = Data([0x01, 0x64, 0x00]) // flags=imperial, value=0x64=100
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertNotNil(w)
        XCTAssertEqual(w!.grams, 454, accuracy: 2)
    }

    func test_parse_imperial_200rawValue() {
        // 200 × 0.01 lb = 2 lb ≈ 907 g
        let data = Data([0x01, 0xC8, 0x00])
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertNotNil(w)
        XCTAssertEqual(w!.grams, 907, accuracy: 3)
    }

    // MARK: - Stability flag

    func test_parse_nonZeroValue_isStable() {
        let data = Data([0x00, 0x64, 0x00]) // 100 × 5 = 500g
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertEqual(w?.isStable, true)
    }

    func test_parse_zeroValue_isUnstable() {
        let data = Data([0x00, 0x00, 0x00])
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        XCTAssertEqual(w?.isStable, false)
    }

    // MARK: - Invalid data

    func test_parse_tooShort_1byte_returnsNil() {
        let data = Data([0x00])
        XCTAssertNil(BluetoothWeightScale.parseWeightMeasurement(data))
    }

    func test_parse_tooShort_2bytes_returnsNil() {
        let data = Data([0x00, 0x64])
        XCTAssertNil(BluetoothWeightScale.parseWeightMeasurement(data))
    }

    func test_parse_empty_returnsNil() {
        XCTAssertNil(BluetoothWeightScale.parseWeightMeasurement(Data()))
    }

    // MARK: - Extra bytes (ignored gracefully)

    func test_parse_extraBytes_ignoredGracefully() {
        // Timestamp / user-ID bytes appended; should not affect weight parsing.
        let data = Data([0x07, 0x64, 0x00, 0x12, 0x34, 0x56]) // flags with extra bits, value=100
        let w = BluetoothWeightScale.parseWeightMeasurement(data)
        // flags bit 0 = 1 (imperial path); value 100 → ~454g
        XCTAssertNotNil(w)
    }
}

// MARK: - XCTAssertEqual(Int, Int, accuracy:) helper

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(Double(a), Double(b), accuracy: Double(accuracy), file: file, line: line)
}
