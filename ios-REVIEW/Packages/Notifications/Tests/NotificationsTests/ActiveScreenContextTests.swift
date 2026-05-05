import XCTest
@testable import Notifications

final class ActiveScreenContextTests: XCTestCase {

    @MainActor
    func test_setActive_andCheckSuppression() {
        let ctx = ActiveScreenContext()
        ctx.setActive(entity: "sms_thread", id: "t1")
        XCTAssertTrue(ctx.isSuppressed(entityType: "sms_thread", entityId: "t1"))
        XCTAssertFalse(ctx.isSuppressed(entityType: "sms_thread", entityId: "t2"))
    }

    @MainActor
    func test_clearActive_removesEntry() {
        let ctx = ActiveScreenContext()
        ctx.setActive(entity: "ticket", id: "42")
        ctx.clearActive(entity: "ticket", id: "42")
        XCTAssertFalse(ctx.isSuppressed(entityType: "ticket", entityId: "42"))
    }

    @MainActor
    func test_payloadOverload_suppresses_whenOnScreen() {
        let ctx = ActiveScreenContext()
        ctx.setActive(entity: "sms_thread", id: "abc")
        let payload: [String: Any] = ["entity_type": "sms_thread", "entity_id": "abc"]
        XCTAssertTrue(ctx.isSuppressed(payload: payload))
    }

    @MainActor
    func test_payloadOverload_notSuppressed_missingKeys() {
        let ctx = ActiveScreenContext()
        XCTAssertFalse(ctx.isSuppressed(payload: [:]))
    }

    func test_pushCollapseWindow_firstDelivery() async {
        let window = PushCollapseWindow(windowSeconds: 60)
        let (deliver, count) = await window.receive(categoryID: "ticket", entityId: "1")
        XCTAssertTrue(deliver)
        XCTAssertEqual(count, 1)
    }

    func test_pushCollapseWindow_collapses_withinWindow() async {
        let window = PushCollapseWindow(windowSeconds: 60)
        _ = await window.receive(categoryID: "ticket", entityId: "2")
        let (deliver, count) = await window.receive(categoryID: "ticket", entityId: "2")
        XCTAssertFalse(deliver, "Second push should be collapsed")
        XCTAssertEqual(count, 2)
    }

    func test_pushCollapseWindow_differentEntity_delivers() async {
        let window = PushCollapseWindow(windowSeconds: 60)
        _ = await window.receive(categoryID: "ticket", entityId: "3")
        let (deliver, _) = await window.receive(categoryID: "ticket", entityId: "4")
        XCTAssertTrue(deliver, "Different entityId should not be collapsed")
    }

    func test_pushCollapseWindow_nilEntityId_tracksSeparately() async {
        let window = PushCollapseWindow(windowSeconds: 60)
        _ = await window.receive(categoryID: "system", entityId: nil)
        let (deliver, count) = await window.receive(categoryID: "system", entityId: nil)
        XCTAssertFalse(deliver)
        XCTAssertEqual(count, 2)
    }

    func test_pushCollapseWindow_reset_clearsEntries() async {
        let window = PushCollapseWindow(windowSeconds: 60)
        _ = await window.receive(categoryID: "ticket", entityId: "5")
        await window.reset()
        let (deliver, _) = await window.receive(categoryID: "ticket", entityId: "5")
        XCTAssertTrue(deliver, "After reset, same key should deliver again")
    }
}
