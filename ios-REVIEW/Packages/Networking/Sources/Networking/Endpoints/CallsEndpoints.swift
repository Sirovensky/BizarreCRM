import Foundation

/// §42 — Voice & Calls DTOs + APIClient wrappers.
///
/// Server routes live in `packages/server/src/routes/voice.routes.ts`:
///   - `GET  /api/v1/voice/calls`           — paginated call log (admin sees all; techs see own)
///   - `GET  /api/v1/voice/calls/:id`        — single call detail
///   - `GET  /api/v1/voice/calls/:id/recording` — stream audio (redirect or local)
///
/// Voicemail endpoints do NOT exist on the server yet (no `voicemail.routes.ts`).
/// Calls to `listVoicemails`, `markVoicemailHeard`, and `getCallTranscript` will
/// receive a 404. View-model consumers MUST soft-absorb 404 → show empty list +
/// "Coming soon" banner. This file intentionally keeps the endpoint layer
/// thin and 404-transparent — the view-models own the degraded-UX path.
///
/// Server envelope: `{ success: true, data: { calls: [...], pagination: {...} } }`
/// for list calls; `{ success: true, data: <row> }` for single-item endpoints.
/// Snake-case CodingKeys are declared on every model so that callers don't
/// rely on automatic key conversion (the shared decoder uses `.convertFromSnakeCase`
/// but explicit keys prevent silent mismatches after server renames).

// MARK: - Call Log

/// A single row from the `call_logs` table. Direction is `"inbound"` or `"outbound"`.
public struct CallLogEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// `"inbound"` or `"outbound"`.
    public let direction: String
    /// The customer-facing phone number (conv_phone = normalized, no country code).
    public let phoneNumber: String
    /// FK to `customers` if the call was matched server-side.
    public let customerId: Int64?
    /// Denormalized display name (first + last from `users` or matched customer).
    public let customerName: String?
    /// ISO-8601 timestamp when the call started.
    public let startedAt: String?
    /// Duration in seconds; `nil` while the call is in progress or if never recorded.
    public let durationSeconds: Int?
    /// URL to the audio recording (may be a `/uploads/...` local path or a provider URL).
    public let recordingUrl: String?
    /// Transcription text if auto-transcription ran.
    public let transcriptText: String?

    public init(
        id: Int64,
        direction: String,
        phoneNumber: String,
        customerId: Int64? = nil,
        customerName: String? = nil,
        startedAt: String? = nil,
        durationSeconds: Int? = nil,
        recordingUrl: String? = nil,
        transcriptText: String? = nil
    ) {
        self.id = id
        self.direction = direction
        self.phoneNumber = phoneNumber
        self.customerId = customerId
        self.customerName = customerName
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.recordingUrl = recordingUrl
        self.transcriptText = transcriptText
    }

    public var isInbound: Bool { direction == "inbound" }

    enum CodingKeys: String, CodingKey {
        case id
        case direction
        case phoneNumber     = "conv_phone"
        case customerId      = "customer_id"
        case customerName    = "user_name"
        case startedAt       = "created_at"
        case durationSeconds = "duration_secs"
        case recordingUrl    = "recording_url"
        case transcriptText  = "transcription"
    }
}

/// Server wraps the list in `{ calls: [...], pagination: {...} }` under `data`.
struct CallLogListPayload: Decodable, Sendable {
    let calls: [CallLogEntry]
}

// MARK: - Voicemail

/// Voicemail entry. Server-side endpoint is DEFERRED — these will 404.
/// Consumers soft-absorb per the §42 contract documented above.
public struct VoicemailEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let phoneNumber: String
    public let customerName: String?
    /// ISO-8601 timestamp.
    public let receivedAt: String?
    public let durationSeconds: Int?
    /// URL to the audio file (provider or local uploads path).
    public let audioUrl: String?
    /// Transcription if available.
    public let transcriptText: String?
    /// `false` = new/unheard; `true` = already listened to.
    public let heard: Bool

    public init(
        id: Int64,
        phoneNumber: String,
        customerName: String? = nil,
        receivedAt: String? = nil,
        durationSeconds: Int? = nil,
        audioUrl: String? = nil,
        transcriptText: String? = nil,
        heard: Bool = false
    ) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.customerName = customerName
        self.receivedAt = receivedAt
        self.durationSeconds = durationSeconds
        self.audioUrl = audioUrl
        self.transcriptText = transcriptText
        self.heard = heard
    }

    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber     = "phone_number"
        case customerName    = "customer_name"
        case receivedAt      = "received_at"
        case durationSeconds = "duration_seconds"
        case audioUrl        = "audio_url"
        case transcriptText  = "transcript_text"
        case heard
    }
}

// MARK: - Empty ack helper (PATCH /heard)

private struct VoidAck: Decodable, Sendable {}

// MARK: - APIClient wrappers

public extension APIClient {

    /// Fetch paginated call log. `pageSize` maps to the server's `pagesize` query param.
    ///
    /// - Note: Returns an empty array on 404 (server feature not yet deployed).
    ///   View-model consumers should present a "Coming soon" banner instead of an error.
    func listCalls(pageSize: Int = 50) async throws -> [CallLogEntry] {
        let query = [URLQueryItem(name: "pagesize", value: "\(pageSize)")]
        let payload = try await get(
            "/api/v1/voice/calls",
            query: query,
            as: CallLogListPayload.self
        )
        return payload.calls
    }

    /// Fetch all voicemails. Server endpoint is DEFERRED — 404 expected.
    ///
    /// - Note: Returns an empty array on 404. Consumers should show "Coming soon".
    func listVoicemails() async throws -> [VoicemailEntry] {
        try await get("/api/v1/voicemails", as: [VoicemailEntry].self)
    }

    /// Mark a voicemail as heard (PATCH). Server endpoint is DEFERRED — 404 expected.
    func markVoicemailHeard(id: Int64) async throws {
        // PATCH with an empty body; server just acknowledges.
        _ = try await patch(
            "/api/v1/voicemails/\(id)/heard",
            body: VoiceEmptyBody(),
            as: VoidAck.self
        )
    }

    /// Fetch transcript text for a call. Server endpoint is DEFERRED — 404 expected.
    ///
    /// Returns `nil` when no transcript is available or the server 404s.
    func getCallTranscript(id: Int64) async throws -> String? {
        // The server stores transcription inline on the call_log row. We read
        // the single-call detail endpoint and pull `transcription` from it.
        let entry = try await get(
            "/api/v1/voice/calls/\(id)",
            as: CallLogEntry.self
        )
        return entry.transcriptText
    }
}

// MARK: - Helpers

// NOTE: `EmptyBody` is defined in NotificationsEndpoints.swift (module-level private).
// Swift sees all private types in the same target as file-scoped; use a distinct name.
private struct VoiceEmptyBody: Encodable, Sendable {}
