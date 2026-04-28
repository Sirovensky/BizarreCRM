import XCTest
@testable import Notifications

final class SilentPushPayloadTypeTests: XCTestCase {

    // MARK: - Helpers

    private func makeUserInfo(
        kind: String,
        messageId: String? = "msg-001",
        entityId: String? = nil,
        scope: String? = nil,
        expiresAt: String? = nil,
        meta: [String: String]? = nil
    ) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["aps": ["content-available": 1], "kind": kind]
        if let messageId { info["messageId"] = messageId }
        if let entityId  { info["entityId"]  = entityId  }
        if let scope     { info["scope"]     = scope     }
        if let expiresAt { info["expiresAt"] = expiresAt }
        if let meta      { info["meta"]      = meta      }
        return info
    }

    // MARK: - decode: not a silent push

    func test_decode_returnsNil_whenContentAvailableMissing() {
        let userInfo: [AnyHashable: Any] = ["kind": "sync"]
        XCTAssertNil(SilentPushPayloadType.decode(from: userInfo))
    }

    func test_decode_returnsNil_whenApsAbsent() {
        XCTAssertNil(SilentPushPayloadType.decode(from: [:]))
    }

    func test_decode_returnsNil_whenContentAvailableIsZero() {
        let userInfo: [AnyHashable: Any] = ["aps": ["content-available": 0], "kind": "sync"]
        XCTAssertNil(SilentPushPayloadType.decode(from: userInfo))
    }

    // MARK: - decode: kind routing

    func test_decode_cacheInvalidate_forSyncKind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "sync"))
        guard case .cacheInvalidate = payload else {
            return XCTFail("Expected .cacheInvalidate, got \(String(describing: payload))")
        }
    }

    func test_decode_cacheInvalidate_forCacheInvalidateKind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "cacheInvalidate"))
        guard case .cacheInvalidate = payload else {
            return XCTFail("Expected .cacheInvalidate, got \(String(describing: payload))")
        }
    }

    func test_decode_dataRefresh_forTicketKind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "ticket"))
        guard case .dataRefresh = payload else {
            return XCTFail("Expected .dataRefresh, got \(String(describing: payload))")
        }
    }

    func test_decode_dataRefresh_forCustomerKind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "customer"))
        guard case .dataRefresh = payload else {
            return XCTFail("Expected .dataRefresh")
        }
    }

    func test_decode_dataRefresh_forInvoiceKind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "invoice"))
        guard case .dataRefresh = payload else {
            return XCTFail("Expected .dataRefresh")
        }
    }

    func test_decode_remoteCommand_kind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "remoteCommand"))
        guard case .remoteCommand = payload else {
            return XCTFail("Expected .remoteCommand")
        }
    }

    func test_decode_deadLetter_kinds() {
        for kind in ["deadletter", "deadLetter"] {
            let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: kind))
            guard case .deadLetter = payload else {
                return XCTFail("Expected .deadLetter for kind '\(kind)'")
            }
        }
    }

    func test_decode_smsMessage_kind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "sms"))
        guard case .smsMessage = payload else {
            return XCTFail("Expected .smsMessage")
        }
    }

    func test_decode_inventoryUpdate_kind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "inventory"))
        guard case .inventoryUpdate = payload else {
            return XCTFail("Expected .inventoryUpdate")
        }
    }

    func test_decode_appointmentUpdate_kind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "appointment"))
        guard case .appointmentUpdate = payload else {
            return XCTFail("Expected .appointmentUpdate")
        }
    }

    func test_decode_unknown_forUnrecognisedKind() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "futuristic"))
        guard case .unknown(let kind, _) = payload else {
            return XCTFail("Expected .unknown")
        }
        XCTAssertEqual(kind, "futuristic")
    }

    // MARK: - Envelope properties

    func test_envelope_messageId_usesServerSuppliedValue() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "sms", messageId: "abc-123"))!
        XCTAssertEqual(payload.envelope.messageId, "abc-123")
    }

    func test_envelope_messageId_synthesisedWhenAbsent() {
        var userInfo: [AnyHashable: Any] = ["aps": ["content-available": 1], "kind": "sms"]
        // No messageId key
        let payload = SilentPushPayloadType.decode(from: userInfo)!
        XCTAssertFalse(payload.envelope.messageId.isEmpty)
    }

    func test_envelope_entityId_parsedFromEntityId() {
        let payload = SilentPushPayloadType.decode(
            from: makeUserInfo(kind: "ticket", entityId: "ticket-42")
        )!
        XCTAssertEqual(payload.envelope.entityId, "ticket-42")
    }

    func test_envelope_entityId_parsedFromSnakeCaseAlias() {
        var userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "kind": "ticket",
            "entity_id": "ticket-99"
        ]
        let payload = SilentPushPayloadType.decode(from: userInfo)!
        XCTAssertEqual(payload.envelope.entityId, "ticket-99")
    }

    func test_envelope_meta_parsed() {
        let payload = SilentPushPayloadType.decode(
            from: makeUserInfo(kind: "sms", meta: ["thread": "t1"])
        )!
        XCTAssertEqual(payload.envelope.meta["thread"], "t1")
    }

    // MARK: - TTL / expiry

    func test_envelope_isExpired_false_forFutureDate() {
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let payload = SilentPushPayloadType.decode(
            from: makeUserInfo(kind: "sync", expiresAt: future)
        )!
        XCTAssertFalse(payload.envelope.isExpired)
    }

    func test_envelope_isExpired_true_forPastDate() {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        // We need to provide a receivedAt in the future relative to expiresAt
        // The simplest way: pass a past expiresAt and let receivedAt = now
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "kind": "sync",
            "messageId": "m1",
            "expiresAt": past
        ]
        let payload = SilentPushPayloadType.decode(from: userInfo)!
        XCTAssertTrue(payload.envelope.isExpired)
    }

    func test_envelope_isExpired_false_whenNoExpiry() {
        let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: "sync"))!
        XCTAssertFalse(payload.envelope.isExpired)
    }

    // MARK: - envelope accessor on each case

    func test_envelopeAccessor_returnsEnvelope_forAllCases() {
        let cases: [String] = [
            "sync", "ticket", "remoteCommand", "deadletter", "sms", "inventory", "appointment"
        ]
        for kind in cases {
            let payload = SilentPushPayloadType.decode(from: makeUserInfo(kind: kind))!
            XCTAssertEqual(payload.envelope.kind, kind)
        }
    }
}
