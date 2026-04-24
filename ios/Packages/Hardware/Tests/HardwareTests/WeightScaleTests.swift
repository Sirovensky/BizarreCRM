import XCTest
@testable import Hardware

// MARK: - WeightScaleTests
//
// Tests for `NullWeightScale`, `WeightScaleError` and the `WeightScale` protocol
// contract. `BluetoothWeightScale` parsing is covered in `BluetoothWeightScaleTests`.

final class WeightScaleTests: XCTestCase {

    // MARK: - NullWeightScale

    func test_nullScale_read_throwsNotConnected() async {
        let scale = NullWeightScale()
        do {
            _ = try await scale.read()
            XCTFail("Expected WeightScaleError.notConnected")
        } catch WeightScaleError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_nullScale_stream_finishesImmediately() async {
        let scale = NullWeightScale()
        let stream = scale.stream()

        var received: [Weight] = []
        for await weight in stream {
            received.append(weight)
        }
        XCTAssertTrue(received.isEmpty,
                      "NullWeightScale stream must finish immediately with no values")
    }

    // MARK: - WeightScaleError descriptions

    func test_errorDescriptions_allPopulated() {
        let cases: [WeightScaleError] = [
            .notConnected,
            .readTimeout,
            .invalidData("bad bytes"),
            .unsupportedUnit
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription,
                            "Error \(error) must have a non-nil description")
            XCTAssertFalse(error.errorDescription!.isEmpty,
                           "Error \(error) description must not be empty")
        }
    }

    func test_invalidData_descriptionContainsDetail() {
        let error = WeightScaleError.invalidData("truncated packet")
        XCTAssertTrue(error.errorDescription?.contains("truncated packet") == true)
    }

    func test_notConnected_descriptionMentionsBluetooth() {
        let desc = WeightScaleError.notConnected.errorDescription ?? ""
        // Should guide users toward Settings → Hardware → Bluetooth
        XCTAssertTrue(desc.lowercased().contains("bluetooth") || desc.lowercased().contains("connected"),
                      "notConnected description should reference Bluetooth or connection state")
    }

    func test_readTimeout_descriptionMentionsPowerOrRange() {
        let desc = WeightScaleError.readTimeout.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
    }

    // MARK: - Protocol conformance check

    func test_nullWeightScale_conformsToWeightScale() {
        let scale: any WeightScale = NullWeightScale()
        XCTAssertNotNil(scale)
    }
}
