import XCTest
#if os(iOS)
@testable import Core

/// Verifies that `BizarreDeepAppShortcuts` provides the expected three shortcuts
/// and that each intent is instantiable (no crash on default init).
@available(iOS 16, *)
final class AppShortcutsProviderTests: XCTestCase {

    // MARK: - BizarreDeepAppShortcuts

    func test_appShortcuts_count_isThree() {
        let shortcuts = BizarreDeepAppShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 3)
    }

    // MARK: - Constituent intents are instantiable

    func test_createTicketIntent_defaultInit_doesNotCrash() {
        let intent = CreateTicketIntent()
        XCTAssertNil(intent.customer)
        XCTAssertNil(intent.device)
    }

    func test_lookupTicketIntent_defaultInit_doesNotCrash() {
        let intent = LookupTicketIntent()
        XCTAssertEqual(intent.orderId, "")
    }

    func test_scanBarcodeIntent_defaultInit_doesNotCrash() {
        let intent = ScanBarcodeIntent()
        XCTAssertNil(intent.context)
    }

    // MARK: - Intent metadata sanity

    func test_createTicketIntent_title_nonEmpty() {
        let title = String(localized: CreateTicketIntent.title)
        XCTAssertFalse(title.isEmpty)
    }

    func test_lookupTicketIntent_title_nonEmpty() {
        let title = String(localized: LookupTicketIntent.title)
        XCTAssertFalse(title.isEmpty)
    }

    func test_scanBarcodeIntent_title_nonEmpty() {
        let title = String(localized: ScanBarcodeIntent.title)
        XCTAssertFalse(title.isEmpty)
    }

    // MARK: - openAppWhenRun is set for all three

    func test_allIntents_openAppWhenRun() {
        XCTAssertTrue(CreateTicketIntent.openAppWhenRun)
        XCTAssertTrue(LookupTicketIntent.openAppWhenRun)
        XCTAssertTrue(ScanBarcodeIntent.openAppWhenRun)
    }
}
#endif // os(iOS)
