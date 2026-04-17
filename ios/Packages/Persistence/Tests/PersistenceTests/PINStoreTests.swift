import XCTest
@testable import Persistence

@MainActor
final class PINStoreTests: XCTestCase {
    override func setUp() async throws {
        PINStore.shared.reset()
    }

    func test_enrolAndVerify() throws {
        try PINStore.shared.enrol(pin: "1234")
        XCTAssertTrue(PINStore.shared.isEnrolled)
        XCTAssertTrue(PINStore.shared.verify(pin: "1234"))
        XCTAssertFalse(PINStore.shared.verify(pin: "0000"))
    }
}
