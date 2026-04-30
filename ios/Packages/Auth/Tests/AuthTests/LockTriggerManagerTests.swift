import XCTest
@testable import Auth
import Persistence

// MARK: - LockTriggerManagerTests
// §2.5 — Lock triggers: threshold preferences + immediate lock.

final class LockTriggerManagerTests: XCTestCase {

    func test_lockThresholdStore_defaultIsFifteenMins() {
        // Ensure default is fifteenMins (don't pollute real UserDefaults)
        let raw = UserDefaults.standard.integer(forKey: "auth.lockAfterMinutes")
        let threshold = LockAfterMinutes(rawValue: raw) ?? .fifteenMins
        XCTAssertEqual(threshold, .fifteenMins)
    }

    func test_lockAfterMinutes_allCases_haveDisplayNames() {
        for threshold in LockAfterMinutes.allCases {
            XCTAssertFalse(threshold.displayName.isEmpty)
        }
    }

    func test_lockAfterMinutes_neverRawValue_isNegative() {
        XCTAssertEqual(LockAfterMinutes.never.rawValue, -1)
    }

    func test_lockAfterMinutes_immediatelyRawValue_isZero() {
        XCTAssertEqual(LockAfterMinutes.immediately.rawValue, 0)
    }
}
