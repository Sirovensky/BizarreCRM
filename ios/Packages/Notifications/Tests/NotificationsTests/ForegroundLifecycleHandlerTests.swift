import XCTest
@testable import Notifications
import Core

// MARK: - §21.6 Foreground lifecycle tests

final class ForegroundLifecycleHandlerTests: XCTestCase {

    // MARK: - Notification name

    func test_notificationsFlushPendingWrites_nameIsConsistent() {
        let name1 = Notification.Name.notificationsFlushPendingWrites
        let name2 = Notification.Name.notificationsFlushPendingWrites
        XCTAssertEqual(name1, name2)
    }

    func test_notificationsFlushPendingWrites_hasExpectedRawValue() {
        XCTAssertEqual(
            Notification.Name.notificationsFlushPendingWrites.rawValue,
            "com.bizarrecrm.notifications.flushPendingWrites"
        )
    }

    // MARK: - Handler can be instantiated without crash

    @MainActor
    func test_handler_init_doesNotCrash() {
        let api = makeMockAPI()
        let ws  = WebSocketManager()
        let handler = ForegroundLifecycleHandler(api: api, wsManager: ws)
        XCTAssertNotNil(handler)
    }

    @MainActor
    func test_handler_start_doesNotCrash() {
        let api = makeMockAPI()
        let ws  = WebSocketManager()
        let handler = ForegroundLifecycleHandler(api: api, wsManager: ws)
        handler.start()
        // No assertion — we just verify no exception/crash is thrown
    }

    @MainActor
    func test_handler_securityBlur_defaultIsFalse() {
        let api = makeMockAPI()
        let ws  = WebSocketManager()
        let handler = ForegroundLifecycleHandler(api: api, wsManager: ws)
        XCTAssertFalse(handler.securityBlurEnabled)
    }

    // MARK: - Helpers

    private func makeMockAPI() -> APIClient { APIClient() }
}
