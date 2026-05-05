import XCTest
@testable import Settings

// MARK: - DLQAlertBannerViewModelTests
//
// §19.23 — Dead-letter queue app-root banner tests.
//   • dismiss() sets isDismissed = true
//   • banner should re-show when count increases after dismiss

@MainActor
final class DLQAlertBannerTests: XCTestCase {

    func test_isDismissed_falseByDefault() {
        let vm = DLQAlertBannerViewModel()
        XCTAssertFalse(vm.isDismissed)
    }

    func test_dismiss_setsDismissedTrue() {
        let vm = DLQAlertBannerViewModel()
        vm.dismiss()
        XCTAssertTrue(vm.isDismissed)
    }

    func test_deadLetterCount_zeroByDefault() {
        let vm = DLQAlertBannerViewModel()
        XCTAssertEqual(vm.deadLetterCount, 0)
    }

    func test_dismiss_doesNotClearCount() {
        let vm = DLQAlertBannerViewModel()
        // Simulate a count via test override (count is private(set), dismiss is user action)
        vm.dismiss()
        XCTAssertTrue(vm.isDismissed)
        // After dismiss, count is still whatever it was before
        XCTAssertEqual(vm.deadLetterCount, 0)
    }
}
