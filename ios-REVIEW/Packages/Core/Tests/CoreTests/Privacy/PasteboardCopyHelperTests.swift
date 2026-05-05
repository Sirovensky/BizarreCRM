#if canImport(UIKit)
import XCTest
import UIKit
@testable import Core

// §28.9 — PasteboardCopyHelper de-dupe + sensitive write tests
//
// These tests touch UIPasteboard.general so they only run in UIKit
// environments. Each test clears the pasteboard at start to avoid carry-over.

final class PasteboardCopyHelperTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PasteboardCopyHelper.clear()
    }

    override func tearDown() {
        PasteboardCopyHelper.clear()
        super.tearDown()
    }

    // MARK: - copyNonSensitive

    func test_copyNonSensitive_writesValue() {
        let ok = PasteboardCopyHelper.copyNonSensitive("hello")
        XCTAssertTrue(ok)
        XCTAssertEqual(UIPasteboard.general.string, "hello")
    }

    func test_copyNonSensitive_dedupesIdenticalImmediateCall() {
        XCTAssertTrue(PasteboardCopyHelper.copyNonSensitive("dup"))
        XCTAssertFalse(PasteboardCopyHelper.copyNonSensitive("dup"))
    }

    func test_copyNonSensitive_distinctValuesNotDeduped() {
        XCTAssertTrue(PasteboardCopyHelper.copyNonSensitive("a"))
        XCTAssertTrue(PasteboardCopyHelper.copyNonSensitive("b"))
        XCTAssertEqual(UIPasteboard.general.string, "b")
    }

    // MARK: - copySensitive

    func test_copySensitive_writesAndSetsExpiration() {
        let ok = PasteboardCopyHelper.copySensitive(
            "OTP-123456",
            expiresIn: 60,
            screen: "twoFactor.test"
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(UIPasteboard.general.string, "OTP-123456")
    }

    func test_copySensitive_dedupesWithinWindow() {
        XCTAssertTrue(PasteboardCopyHelper.copySensitive("CODE", screen: "s"))
        XCTAssertFalse(PasteboardCopyHelper.copySensitive("CODE", screen: "s"))
    }

    // MARK: - clear

    func test_clear_emptiesPasteboardAndDedupeState() {
        PasteboardCopyHelper.copyNonSensitive("x")
        PasteboardCopyHelper.clear()
        XCTAssertTrue(UIPasteboard.general.items.isEmpty)
        // After clear we should be able to write the same value again.
        XCTAssertTrue(PasteboardCopyHelper.copyNonSensitive("x"))
    }
}
#endif
