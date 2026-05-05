import XCTest
@testable import Notifications

// MARK: - Test double: spy handler

final class SpyPushHandler: SilentPushHandlerProtocol {

    let acceptsKind: String
    private(set) var handledPayloads: [SilentPushPayloadType] = []

    init(acceptsKind: String) {
        self.acceptsKind = acceptsKind
    }

    func canHandle(_ payload: SilentPushPayloadType) -> Bool {
        payload.envelope.kind == acceptsKind
    }

    func handle(_ payload: SilentPushPayloadType) async {
        handledPayloads.append(payload)
    }
}

// MARK: - Test double: always-accept handler

final class CatchAllHandler: SilentPushHandlerProtocol {
    private(set) var callCount = 0
    func canHandle(_ payload: SilentPushPayloadType) -> Bool { true }
    func handle(_ payload: SilentPushPayloadType) async { callCount += 1 }
}

// MARK: - Tests

final class SilentPushRouterTests: XCTestCase {

    private var router: SilentPushRouter!

    override func setUp() async throws {
        router = SilentPushRouter()
    }

    // MARK: - route(userInfo:)

    func test_routeUserInfo_returnsFalse_forNonSilentPush() async {
        let userInfo: [AnyHashable: Any] = ["kind": "sync"]   // no aps
        let routed = await router.route(userInfo: userInfo)
        XCTAssertFalse(routed)
    }

    func test_routeUserInfo_routesToMatchingHandler() async {
        let handler = SpyPushHandler(acceptsKind: "sms")
        await router.register(handler)

        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "kind": "sms",
            "messageId": "msg-1"
        ]
        let routed = await router.route(userInfo: userInfo)
        XCTAssertTrue(routed)
        XCTAssertEqual(handler.handledPayloads.count, 1)
    }

    // MARK: - route(_:) — typed payload

    func test_route_returnsFalse_whenNoHandlersRegistered() async {
        let envelope = SilentPushEnvelope(messageId: "m1", kind: "sync")
        let routed = await router.route(.cacheInvalidate(envelope))
        XCTAssertFalse(routed)
    }

    func test_route_returnsFalse_whenNoHandlerMatches() async {
        let handler = SpyPushHandler(acceptsKind: "sms")
        await router.register(handler)

        let envelope = SilentPushEnvelope(messageId: "m2", kind: "inventory")
        let routed = await router.route(.inventoryUpdate(envelope))
        XCTAssertFalse(routed)
        XCTAssertTrue(handler.handledPayloads.isEmpty)
    }

    func test_route_returnsTrue_whenHandlerMatches() async {
        let handler = SpyPushHandler(acceptsKind: "ticket")
        await router.register(handler)

        let envelope = SilentPushEnvelope(messageId: "m3", kind: "ticket", entityId: "t99")
        let routed = await router.route(.dataRefresh(envelope))
        XCTAssertTrue(routed)
        XCTAssertEqual(handler.handledPayloads.count, 1)
        XCTAssertEqual(handler.handledPayloads.first?.envelope.entityId, "t99")
    }

    // MARK: - First-match semantics

    func test_route_stopsAtFirstMatchingHandler() async {
        let first  = CatchAllHandler()
        let second = CatchAllHandler()
        await router.register(first)
        await router.register(second)

        let envelope = SilentPushEnvelope(messageId: "m4", kind: "sync")
        await router.route(.cacheInvalidate(envelope))

        XCTAssertEqual(first.callCount, 1)
        XCTAssertEqual(second.callCount, 0, "Second handler must not be called after first matched")
    }

    // MARK: - Fallback

    func test_route_invokesFallback_whenNoHandlerMatches() async {
        var fallbackPayload: SilentPushPayloadType?
        await router.setFallback { p in fallbackPayload = p }

        let envelope = SilentPushEnvelope(messageId: "m5", kind: "unknown_kind")
        await router.route(.unknown(kind: "unknown_kind", envelope: envelope))

        XCTAssertNotNil(fallbackPayload)
    }

    func test_route_doesNotInvokeFallback_whenHandlerMatches() async {
        var fallbackCalled = false
        await router.setFallback { _ in fallbackCalled = true }
        let handler = CatchAllHandler()
        await router.register(handler)

        let envelope = SilentPushEnvelope(messageId: "m6", kind: "sms")
        await router.route(.smsMessage(envelope))
        XCTAssertFalse(fallbackCalled)
    }

    // MARK: - Expired payload

    func test_route_dropsExpiredPayload() async {
        let handler = CatchAllHandler()
        await router.register(handler)

        let past = Date().addingTimeInterval(-3600)
        let envelope = SilentPushEnvelope(
            messageId: "m7",
            kind: "sms",
            expiresAt: past,
            receivedAt: Date()
        )
        let routed = await router.route(.smsMessage(envelope))
        XCTAssertFalse(routed)
        XCTAssertEqual(handler.callCount, 0)
    }

    // MARK: - resetHandlers

    func test_resetHandlers_removesAllHandlers() async {
        let handler = CatchAllHandler()
        await router.register(handler)
        await router.resetHandlers()

        let envelope = SilentPushEnvelope(messageId: "m8", kind: "sync")
        let routed = await router.route(.cacheInvalidate(envelope))
        XCTAssertFalse(routed)
        XCTAssertEqual(handler.callCount, 0)
    }

    // MARK: - Multiple handlers different kinds

    func test_route_dispatchesToCorrectHandler_withMultipleRegistered() async {
        let ticketHandler = SpyPushHandler(acceptsKind: "ticket")
        let smsHandler    = SpyPushHandler(acceptsKind: "sms")
        await router.register(ticketHandler)
        await router.register(smsHandler)

        let smsEnvelope = SilentPushEnvelope(messageId: "s1", kind: "sms")
        await router.route(.smsMessage(smsEnvelope))

        XCTAssertEqual(smsHandler.handledPayloads.count, 1)
        XCTAssertEqual(ticketHandler.handledPayloads.count, 0)
    }
}
