import XCTest

final class SmokeTests: XCTestCase {
    /// Tautological — ensures the app target links against every package and
    /// the test bundle can launch. Real UI tests land in Phase 2+.
    func test_appLinks() {
        XCTAssertTrue(true)
    }
}
