import XCTest
@testable import Settings

final class AboutViewTests: XCTestCase {

    func test_engagementCounter_increments() {
        let key = "com.bizarrecrm.sessionCount"
        let defaults = UserDefaults.standard
        let before = defaults.integer(forKey: key)
        let result = AppEngagementCounter.increment()
        XCTAssertEqual(result, before + 1)
        // cleanup
        defaults.set(before, forKey: key)
    }

    func test_engagementCounter_count_returnsCurrentValue() {
        let key = "com.bizarrecrm.sessionCount"
        UserDefaults.standard.set(42, forKey: key)
        XCTAssertEqual(AppEngagementCounter.count, 42)
        UserDefaults.standard.removeObject(forKey: key)
    }

    @MainActor
    func test_requestReviewIfEligible_skips_belowThreshold() {
        let countKey = "com.bizarrecrm.sessionCount"
        let ratedKey = "com.bizarrecrm.storeReviewRequested"
        UserDefaults.standard.set(5, forKey: countKey)
        UserDefaults.standard.set(false, forKey: ratedKey)
        // Should not crash or set ratedKey when below 10 sessions
        AppEngagementCounter.requestReviewIfEligible()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: ratedKey))
        // cleanup
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: ratedKey)
    }
}
