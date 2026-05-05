import XCTest
@testable import BizarreCRM

// MARK: - MockPasteboard

/// In-memory pasteboard for hermetic unit tests.
final class MockPasteboard: PasteboardProtocol, @unchecked Sendable {
    var string: String?
}

// MARK: - UniversalClipboardBridgeTests

/// Tests for `UniversalClipboardBridge`.
///
/// All tests inject a `MockPasteboard` — no actual `UIPasteboard` is touched,
/// making the suite safe to run anywhere (CI, macOS, simulator).
///
/// Coverage target: ≥ 80 %.
final class UniversalClipboardBridgeTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeBridge() -> (bridge: UniversalClipboardBridge, mock: MockPasteboard) {
        let mock = MockPasteboard()
        let bridge = UniversalClipboardBridge(pasteboard: mock)
        return (bridge, mock)
    }

    // MARK: - writePlainText

    @MainActor
    func test_writePlainText_setsStringOnPasteboard() {
        let (bridge, mock) = makeBridge()
        bridge.writePlainText("Hello, Clipboard!")
        XCTAssertEqual(mock.string, "Hello, Clipboard!")
    }

    @MainActor
    func test_writePlainText_emptyString_setsEmptyString() {
        let (bridge, mock) = makeBridge()
        bridge.writePlainText("")
        XCTAssertEqual(mock.string, "")
    }

    @MainActor
    func test_writePlainText_overwritesPreviousValue() {
        let (bridge, mock) = makeBridge()
        bridge.writePlainText("first")
        bridge.writePlainText("second")
        XCTAssertEqual(mock.string, "second")
    }

    @MainActor
    func test_writePlainText_phoneNumber_roundTrips() {
        let (bridge, mock) = makeBridge()
        let phone = "+1 555 0100"
        bridge.writePlainText(phone)
        XCTAssertEqual(mock.string, phone)
    }

    @MainActor
    func test_writePlainText_skuString_roundTrips() {
        let (bridge, mock) = makeBridge()
        let sku = "SKU-AB12-XY99"
        bridge.writePlainText(sku)
        XCTAssertEqual(mock.string, sku)
    }

    // MARK: - readPlainText

    @MainActor
    func test_readPlainText_returnsNilWhenEmpty() async {
        let (bridge, _) = makeBridge()
        let result = await bridge.readPlainText()
        XCTAssertNil(result)
    }

    @MainActor
    func test_readPlainText_returnsWrittenValue() async {
        let (bridge, _) = makeBridge()
        bridge.writePlainText("copy me")
        let result = await bridge.readPlainText()
        XCTAssertEqual(result, "copy me")
    }

    @MainActor
    func test_readPlainText_afterOverwrite_returnsLatestValue() async {
        let (bridge, _) = makeBridge()
        bridge.writePlainText("v1")
        bridge.writePlainText("v2")
        let result = await bridge.readPlainText()
        XCTAssertEqual(result, "v2")
    }

    // MARK: - Round-trip (write → read)

    @MainActor
    func test_roundTrip_unicode_preserved() async {
        let (bridge, _) = makeBridge()
        let text = "Rëpàïr Cëñtér — Ïñv #12345"
        bridge.writePlainText(text)
        let result = await bridge.readPlainText()
        XCTAssertEqual(result, text)
    }

    @MainActor
    func test_roundTrip_multiline_preserved() async {
        let (bridge, _) = makeBridge()
        let text = "Line 1\nLine 2\nLine 3"
        bridge.writePlainText(text)
        let result = await bridge.readPlainText()
        XCTAssertEqual(result, text)
    }

    // MARK: - Singleton

    @MainActor
    func test_shared_isNotNil() {
        XCTAssertNotNil(UniversalClipboardBridge.shared)
    }
}
