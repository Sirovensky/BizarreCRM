import XCTest
@testable import Camera

// MARK: - ScannedBarcodeEntry unit tests

/// Tests for the ``ScannedBarcodeEntry`` value type — pure Swift, no UIKit
/// dependency required, so these run under `swift test` on macOS as well.
final class ScannedBarcodeEntryTests: XCTestCase {

    // MARK: - Initialisation

    func test_init_storesAllFields() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let entry = ScannedBarcodeEntry(
            id: id,
            value: "987654321",
            symbology: "code128",
            scannedAt: date
        )
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.value, "987654321")
        XCTAssertEqual(entry.symbology, "code128")
        XCTAssertEqual(entry.scannedAt, date)
    }

    func test_init_defaultId_isUnique() {
        let a = ScannedBarcodeEntry(value: "A", symbology: "qr")
        let b = ScannedBarcodeEntry(value: "A", symbology: "qr")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_init_defaultDate_isRecent() {
        let before = Date()
        let entry = ScannedBarcodeEntry(value: "X", symbology: "ean13")
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.scannedAt, before)
        XCTAssertLessThanOrEqual(entry.scannedAt, after)
    }

    func test_emptyValue_isAllowed() {
        let entry = ScannedBarcodeEntry(value: "", symbology: "unknown")
        XCTAssertEqual(entry.value, "")
    }

    // MARK: - Equatable

    func test_equality_sameId() {
        let id = UUID()
        let date = Date()
        let a = ScannedBarcodeEntry(id: id, value: "X", symbology: "qr", scannedAt: date)
        let b = ScannedBarcodeEntry(id: id, value: "X", symbology: "qr", scannedAt: date)
        XCTAssertEqual(a, b)
    }

    func test_inequality_differentId() {
        let a = ScannedBarcodeEntry(value: "X", symbology: "qr")
        let b = ScannedBarcodeEntry(value: "X", symbology: "qr")
        XCTAssertNotEqual(a, b)
    }

    func test_inequality_differentValue() {
        let id = UUID()
        let a = ScannedBarcodeEntry(id: id, value: "A", symbology: "qr")
        let b = ScannedBarcodeEntry(id: id, value: "B", symbology: "qr")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Sendable (cross-actor capture)

    func test_sendable_crossActorCapture() async {
        let entry = ScannedBarcodeEntry(value: "CROSS", symbology: "qr")
        let result = await Task.detached { entry }.value
        XCTAssertEqual(result, entry)
    }

    // MARK: - Identifiable

    func test_identifiable_idMatchesProperty() {
        let id = UUID()
        let entry = ScannedBarcodeEntry(id: id, value: "X", symbology: "qr")
        XCTAssertEqual(entry.id, id)
    }
}

// MARK: - ScanHistoryInspector.prepending tests

/// Tests for the pure ``ScanHistoryInspector/prepending(_:to:limit:)`` helper.
/// No UIKit needed — just logic.
final class ScanHistoryInspectorLogicTests: XCTestCase {

    #if canImport(UIKit)

    func test_prepending_insertsAtFront() {
        let existing = [
            ScannedBarcodeEntry(value: "OLD", symbology: "qr"),
        ]
        let newEntry = ScannedBarcodeEntry(value: "NEW", symbology: "ean13")
        let result = ScanHistoryInspector.prepending(newEntry, to: existing)
        XCTAssertEqual(result.first?.value, "NEW")
        XCTAssertEqual(result.last?.value, "OLD")
    }

    func test_prepending_emptyExisting_returnsSingleton() {
        let entry = ScannedBarcodeEntry(value: "ONLY", symbology: "qr")
        let result = ScanHistoryInspector.prepending(entry, to: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.value, "ONLY")
    }

    func test_prepending_respectsLimit() {
        var existing: [ScannedBarcodeEntry] = []
        for i in 0..<10 {
            existing.append(ScannedBarcodeEntry(value: "\(i)", symbology: "qr"))
        }
        let extra = ScannedBarcodeEntry(value: "EXTRA", symbology: "qr")
        let result = ScanHistoryInspector.prepending(extra, to: existing, limit: 10)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.first?.value, "EXTRA")
    }

    func test_prepending_doesNotMutateOriginal() {
        let original = [
            ScannedBarcodeEntry(value: "A", symbology: "qr"),
        ]
        let snapshot = original
        let newEntry = ScannedBarcodeEntry(value: "B", symbology: "qr")
        _ = ScanHistoryInspector.prepending(newEntry, to: original)
        XCTAssertEqual(original.count, snapshot.count, "Original array must not be mutated")
    }

    func test_prepending_limitOne_keepsNewEntry() {
        let existing = [
            ScannedBarcodeEntry(value: "OLD1", symbology: "qr"),
            ScannedBarcodeEntry(value: "OLD2", symbology: "qr"),
        ]
        let newEntry = ScannedBarcodeEntry(value: "NEW", symbology: "qr")
        let result = ScanHistoryInspector.prepending(newEntry, to: existing, limit: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.value, "NEW")
    }

    func test_prepending_preservesOrder() {
        let a = ScannedBarcodeEntry(value: "1", symbology: "qr")
        let b = ScannedBarcodeEntry(value: "2", symbology: "qr")
        let c = ScannedBarcodeEntry(value: "3", symbology: "qr")
        var list: [ScannedBarcodeEntry] = []
        list = ScanHistoryInspector.prepending(a, to: list)
        list = ScanHistoryInspector.prepending(b, to: list)
        list = ScanHistoryInspector.prepending(c, to: list)
        XCTAssertEqual(list.map(\.value), ["3", "2", "1"])
    }

    #endif
}
