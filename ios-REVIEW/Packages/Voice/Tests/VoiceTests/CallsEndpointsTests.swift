import XCTest
@testable import Voice
import Networking

/// §42 — Decode fixtures for `CallLogEntry` and `VoicemailEntry`.
/// Tests exercise snake_case CodingKeys and optional-field handling.
final class CallsEndpointsTests: XCTestCase {

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - CallLogEntry decoding

    func test_callLogEntry_decodesFullInboundRow() throws {
        let json = """
        {
          "id": 1,
          "direction": "inbound",
          "conv_phone": "5551234567",
          "customer_id": 42,
          "user_name": "Alice Smith",
          "created_at": "2026-04-20T10:00:00Z",
          "duration_secs": 95,
          "recording_url": "https://api.twilio.com/recordings/abc.mp3",
          "transcription": "Hi, I need help with my order."
        }
        """
        let entry = try decode(CallLogEntry.self, from: json)
        XCTAssertEqual(entry.id, 1)
        XCTAssertEqual(entry.direction, "inbound")
        XCTAssertTrue(entry.isInbound)
        XCTAssertEqual(entry.phoneNumber, "5551234567")
        XCTAssertEqual(entry.customerId, 42)
        XCTAssertEqual(entry.customerName, "Alice Smith")
        XCTAssertEqual(entry.startedAt, "2026-04-20T10:00:00Z")
        XCTAssertEqual(entry.durationSeconds, 95)
        XCTAssertEqual(entry.recordingUrl, "https://api.twilio.com/recordings/abc.mp3")
        XCTAssertEqual(entry.transcriptText, "Hi, I need help with my order.")
    }

    func test_callLogEntry_decodesOutboundWithNilOptionals() throws {
        let json = """
        {
          "id": 2,
          "direction": "outbound",
          "conv_phone": "8005550100"
        }
        """
        let entry = try decode(CallLogEntry.self, from: json)
        XCTAssertEqual(entry.id, 2)
        XCTAssertEqual(entry.direction, "outbound")
        XCTAssertFalse(entry.isInbound)
        XCTAssertNil(entry.customerId)
        XCTAssertNil(entry.customerName)
        XCTAssertNil(entry.startedAt)
        XCTAssertNil(entry.durationSeconds)
        XCTAssertNil(entry.recordingUrl)
        XCTAssertNil(entry.transcriptText)
    }

    func test_callLogEntry_isInboundFalseForOutbound() throws {
        let json = """
        { "id": 3, "direction": "outbound", "conv_phone": "5559876543" }
        """
        let entry = try decode(CallLogEntry.self, from: json)
        XCTAssertFalse(entry.isInbound)
    }

    func test_callLogEntry_isInboundTrueForInbound() throws {
        let json = """
        { "id": 4, "direction": "inbound", "conv_phone": "5550001111" }
        """
        let entry = try decode(CallLogEntry.self, from: json)
        XCTAssertTrue(entry.isInbound)
    }

    func test_callLogEntry_decodesZeroDuration() throws {
        let json = """
        { "id": 5, "direction": "inbound", "conv_phone": "5550000000", "duration_secs": 0 }
        """
        let entry = try decode(CallLogEntry.self, from: json)
        XCTAssertEqual(entry.durationSeconds, 0)
    }

    // MARK: - VoicemailEntry decoding

    func test_voicemailEntry_decodesFullRow() throws {
        let json = """
        {
          "id": 10,
          "phone_number": "5557654321",
          "customer_name": "Bob Johnson",
          "received_at": "2026-04-20T09:00:00Z",
          "duration_seconds": 60,
          "audio_url": "https://api.twilio.com/voicemails/vm123.mp3",
          "transcript_text": "Please call me back.",
          "heard": false
        }
        """
        let vm = try decode(VoicemailEntry.self, from: json)
        XCTAssertEqual(vm.id, 10)
        XCTAssertEqual(vm.phoneNumber, "5557654321")
        XCTAssertEqual(vm.customerName, "Bob Johnson")
        XCTAssertEqual(vm.receivedAt, "2026-04-20T09:00:00Z")
        XCTAssertEqual(vm.durationSeconds, 60)
        XCTAssertEqual(vm.audioUrl, "https://api.twilio.com/voicemails/vm123.mp3")
        XCTAssertEqual(vm.transcriptText, "Please call me back.")
        XCTAssertFalse(vm.heard)
    }

    func test_voicemailEntry_decodesHeardTrue() throws {
        let json = """
        { "id": 11, "phone_number": "5550001234", "heard": true }
        """
        let vm = try decode(VoicemailEntry.self, from: json)
        XCTAssertTrue(vm.heard)
    }

    func test_voicemailEntry_optionalFieldsNilWhenAbsent() throws {
        let json = """
        { "id": 12, "phone_number": "5550009999", "heard": false }
        """
        let vm = try decode(VoicemailEntry.self, from: json)
        XCTAssertNil(vm.customerName)
        XCTAssertNil(vm.receivedAt)
        XCTAssertNil(vm.durationSeconds)
        XCTAssertNil(vm.audioUrl)
        XCTAssertNil(vm.transcriptText)
    }

    // MARK: - CallLogListPayload decoding (envelope inner)

    func test_callLogListPayload_decodesMultipleRows() throws {
        let json = """
        {
          "calls": [
            { "id": 1, "direction": "inbound",  "conv_phone": "5551111111" },
            { "id": 2, "direction": "outbound", "conv_phone": "5552222222" }
          ]
        }
        """
        // Mirror internal type via a public fixture struct
        struct ListPayload: Decodable {
            let calls: [CallLogEntry]
        }
        let payload = try decode(ListPayload.self, from: json)
        XCTAssertEqual(payload.calls.count, 2)
        XCTAssertEqual(payload.calls[0].id, 1)
        XCTAssertEqual(payload.calls[1].id, 2)
    }
}
