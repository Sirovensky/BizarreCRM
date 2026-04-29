import XCTest
#if canImport(UIKit)
@testable import BizarreCRM

// MARK: - SceneStateRestorerTests

final class SceneStateRestorerTests: XCTestCase {

    // MARK: - activityType

    func test_activityType_hasExpectedValue() {
        XCTAssertEqual(SceneStateRestorer.activityType, "com.bizarrecrm.sceneState")
    }

    // MARK: - restore

    func test_restore_returnsNil_forWrongActivityType() {
        let activity = NSUserActivity(activityType: "com.other.type")
        activity.userInfo = ["deepLinkURL": "bizarrecrm://ticket/1"]
        XCTAssertNil(SceneStateRestorer.restore(from: activity))
    }

    func test_restore_returnsNil_whenNoDeepLinkURL() {
        let activity = NSUserActivity(activityType: SceneStateRestorer.activityType)
        activity.userInfo = [:]
        XCTAssertNil(SceneStateRestorer.restore(from: activity))
    }

    func test_restore_returnsURLString_forValidActivity() {
        let activity = NSUserActivity(activityType: SceneStateRestorer.activityType)
        let expectedURL = "bizarrecrm://ticket/42"
        activity.userInfo = ["deepLinkURL": expectedURL, "sessionPersistentId": "abc-123"]
        let result = SceneStateRestorer.restore(from: activity)
        XCTAssertEqual(result, expectedURL)
    }

    func test_restore_returnsCustomerURL() {
        let activity = NSUserActivity(activityType: SceneStateRestorer.activityType)
        let expectedURL = "bizarrecrm://customer/99"
        activity.userInfo = ["deepLinkURL": expectedURL]
        XCTAssertEqual(SceneStateRestorer.restore(from: activity), expectedURL)
    }

    func test_restore_returnsInvoiceURL() {
        let activity = NSUserActivity(activityType: SceneStateRestorer.activityType)
        let expectedURL = "bizarrecrm://invoice/INV-007"
        activity.userInfo = ["deepLinkURL": expectedURL]
        XCTAssertEqual(SceneStateRestorer.restore(from: activity), expectedURL)
    }
}

#endif
