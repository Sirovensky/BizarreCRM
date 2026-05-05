import XCTest
#if os(iOS)
@testable import Core

@available(iOS 16, *)
final class ScanBarcodeIntentTests: XCTestCase {

    // MARK: - perform()

    func test_perform_withoutContext_doesNotThrow() async throws {
        let intent = ScanBarcodeIntent()
        _ = try await intent.perform()
    }

    func test_perform_withInventoryContext_doesNotThrow() async throws {
        let intent = ScanBarcodeIntent(context: "inventory")
        _ = try await intent.perform()
    }

    func test_perform_withTicketContext_doesNotThrow() async throws {
        let intent = ScanBarcodeIntent(context: "ticket")
        _ = try await intent.perform()
    }

    func test_perform_withEmptyContext_doesNotThrow() async throws {
        let intent = ScanBarcodeIntent(context: "")
        _ = try await intent.perform()
    }

    // MARK: - Metadata

    func test_title_isScanBarcode() {
        let title = String(localized: ScanBarcodeIntent.title)
        XCTAssertEqual(title, "Scan Barcode")
    }

    func test_openAppWhenRun_isTrue() {
        XCTAssertTrue(ScanBarcodeIntent.openAppWhenRun)
    }

    // MARK: - Init

    func test_defaultInit_contextIsNil() {
        let intent = ScanBarcodeIntent()
        XCTAssertNil(intent.context)
    }

    func test_memberwise_init_preservesContext() {
        let intent = ScanBarcodeIntent(context: "inventory")
        XCTAssertEqual(intent.context, "inventory")
    }

    func test_memberwise_init_nilContext_isNil() {
        let intent = ScanBarcodeIntent(context: nil)
        XCTAssertNil(intent.context)
    }
}
#endif // os(iOS)
