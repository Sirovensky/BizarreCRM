import XCTest
@testable import Camera

/// Unit tests for the pure-Swift value types in the barcode subsystem:
/// ``Barcode``, ``BarcodeError``, and (where UIKit+VisionKit available)
/// ``BarcodeCoordinator``.
///
/// `Barcode` and `BarcodeError` are defined at the top level with no UIKit
/// dependency so these tests always run, including under `swift test` on macOS.

// MARK: - Barcode value type tests

final class BarcodeValueTests: XCTestCase {

    func test_init_storesValueAndSymbology() {
        let b = Barcode(value: "123456789012", symbology: "ean13")
        XCTAssertEqual(b.value, "123456789012")
        XCTAssertEqual(b.symbology, "ean13")
    }

    func test_equality_sameValueAndSymbology() {
        let a = Barcode(value: "ABC", symbology: "code128")
        let b = Barcode(value: "ABC", symbology: "code128")
        XCTAssertEqual(a, b)
    }

    func test_inequality_differentValue() {
        let a = Barcode(value: "AAA", symbology: "qr")
        let b = Barcode(value: "BBB", symbology: "qr")
        XCTAssertNotEqual(a, b)
    }

    func test_inequality_differentSymbology() {
        let a = Barcode(value: "123", symbology: "qr")
        let b = Barcode(value: "123", symbology: "ean13")
        XCTAssertNotEqual(a, b)
    }

    func test_emptyValue_isValid() {
        let b = Barcode(value: "", symbology: "unknown")
        XCTAssertEqual(b.value, "")
    }

    func test_sendable_crossActorCapture() async {
        // Verifies Barcode is Sendable — if it weren't, this async block
        // would produce a compiler error.
        let b = Barcode(value: "X", symbology: "qr")
        let result = await Task.detached { b }.value
        XCTAssertEqual(result, b)
    }
}

// MARK: - BarcodeError tests

final class BarcodeErrorTests: XCTestCase {

    func test_notAuthorized_hasNonEmptyDescription() {
        let err = BarcodeError.notAuthorized
        XCTAssertFalse((err.errorDescription ?? "").isEmpty)
    }

    func test_notAuthorized_mentionsSettings() {
        XCTAssertTrue(
            (BarcodeError.notAuthorized.errorDescription ?? "")
                .localizedCaseInsensitiveContains("settings")
        )
    }

    func test_unavailable_hasNonEmptyDescription() {
        XCTAssertFalse((BarcodeError.unavailable.errorDescription ?? "").isEmpty)
    }

    func test_notFound_containsCode() {
        let err = BarcodeError.notFound("SKU-9999")
        XCTAssertTrue((err.errorDescription ?? "").contains("SKU-9999"))
    }

    func test_networkError_containsDetail() {
        let err = BarcodeError.networkError("connection timed out")
        XCTAssertTrue((err.errorDescription ?? "").contains("connection timed out"))
    }

    func test_allCasesHaveNonEmptyDescription() {
        let cases: [BarcodeError] = [
            .notAuthorized,
            .unavailable,
            .notFound("code"),
            .networkError("err"),
        ]
        for c in cases {
            XCTAssertFalse(
                (c.errorDescription ?? "").isEmpty,
                "\(c) must have a non-empty errorDescription"
            )
        }
    }
}

// MARK: - BarcodeCoordinator tests (UIKit + VisionKit only)

#if canImport(UIKit) && canImport(VisionKit)
import UIKit
import VisionKit

extension BarcodeScanMode: Equatable {
    public static func == (lhs: BarcodeScanMode, rhs: BarcodeScanMode) -> Bool {
        switch (lhs, rhs) {
        case (.single, .single), (.continuous, .continuous): return true
        default: return false
        }
    }
}

/// Tests for ``BarcodeCoordinator`` — drives the coordinator through its
/// public testable API without live hardware.
@MainActor
final class BarcodeCoordinatorTests: XCTestCase {

    // MARK: - Default state

    func test_defaultState_isNotScanning() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        XCTAssertFalse(sut.isScanning)
    }

    func test_defaultState_lastScannedIsNil() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        XCTAssertNil(sut.lastScanned)
    }

    func test_defaultState_scanErrorIsNil() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        XCTAssertNil(sut.scanError)
    }

    // MARK: - Mode storage

    func test_singleMode_storedCorrectly() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        XCTAssertEqual(sut.mode, .single)
    }

    func test_continuousMode_storedCorrectly() {
        let sut = BarcodeCoordinator(mode: .continuous) { _ in }
        XCTAssertEqual(sut.mode, .continuous)
    }

    // MARK: - handleRawPayload

    func test_handleRawPayload_setsLastScanned() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        sut.handleRawPayload("123456789012", symbology: "ean13")
        XCTAssertEqual(sut.lastScanned?.value, "123456789012")
        XCTAssertEqual(sut.lastScanned?.symbology, "ean13")
    }

    func test_handleRawPayload_firesOnScanCallback() {
        var received: Barcode?
        let sut = BarcodeCoordinator(mode: .single) { barcode in received = barcode }
        sut.handleRawPayload("HELLO-WORLD", symbology: "code128")
        XCTAssertEqual(received?.value, "HELLO-WORLD")
        XCTAssertEqual(received?.symbology, "code128")
    }

    func test_handleRawPayload_defaultSymbologyIsUnknown() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        sut.handleRawPayload("TEST")
        XCTAssertEqual(sut.lastScanned?.symbology, "unknown")
    }

    // MARK: - Debounce

    func test_rapidDuplicateCalls_fireOnlyOnce() {
        var callCount = 0
        let sut = BarcodeCoordinator(mode: .continuous) { _ in callCount += 1 }
        sut.handleRawPayload("CODE", symbology: "qr")
        sut.handleRawPayload("CODE2", symbology: "qr")   // within 100 ms window
        XCTAssertEqual(callCount, 1, "Second call within debounce window must be ignored")
    }

    // MARK: - resetLastScanned

    func test_resetLastScanned_clearsState() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        sut.handleRawPayload("ABC")
        XCTAssertNotNil(sut.lastScanned)
        sut.resetLastScanned()
        XCTAssertNil(sut.lastScanned)
    }

    // MARK: - Lifecycle

    func test_markScannerStarted_setsIsScanning() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        sut.markScannerStarted()
        XCTAssertTrue(sut.isScanning)
    }

    func test_markScannerStopped_clearsIsScanning() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        sut.markScannerStarted()
        sut.markScannerStopped()
        XCTAssertFalse(sut.isScanning)
    }

    func test_markScannerStarted_clearsScanError() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        sut.markScannerStarted()
        XCTAssertNil(sut.scanError)
    }

    // MARK: - isScannerSupported

    func test_isScannerSupported_isAccessible() {
        let sut = BarcodeCoordinator(mode: .single) { _ in }
        // Value depends on runtime — just verify it doesn't crash.
        _ = sut.isScannerSupported
    }

    // MARK: - Independent coordinators each fire their own callback

    func test_twoCoordinators_eachFireOwnCallback() {
        var received1: [String] = []
        var received2: [String] = []
        let sut1 = BarcodeCoordinator(mode: .continuous) { received1.append($0.value) }
        let sut2 = BarcodeCoordinator(mode: .continuous) { received2.append($0.value) }

        sut1.handleRawPayload("CODE-A")
        sut2.handleRawPayload("CODE-B")

        XCTAssertEqual(received1, ["CODE-A"])
        XCTAssertEqual(received2, ["CODE-B"])
    }
}
#endif
