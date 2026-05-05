import Foundation

/// §42 — Voice & Calls convenience re-exports on `APIClient`.
///
/// All functional implementations live in
/// `Networking/Endpoints/CallsEndpoints.swift`. This file is the
/// **append-only** shim that exposes the voice surface at the
/// `APIClient` extension level for consumers that import `Networking`
/// without knowing about the `Endpoints/` subdirectory.
///
/// DO NOT add new logic here — add to `CallsEndpoints.swift` and
/// re-export below.
///
/// Routes confirmed against `packages/server/src/routes/voice.routes.ts`:
///   GET  /api/v1/voice/calls          — paginated call log
///   GET  /api/v1/voice/calls/:id      — single call detail (used by transcript fetch)
///   POST /api/v1/voice/call           — initiate click-to-call (not used from iOS; tel: URL instead)
///
/// Voicemail routes (`/api/v1/voicemails`) do NOT exist on the server yet.
/// `listVoicemails` and `markVoicemailHeard` will 404 until the server ships them.
/// View-models must absorb 404 → show "Coming soon" banner.

// All methods delegated to CallsEndpoints.swift extension on APIClient.
// This file intentionally contains no new symbols — it exists as an
// ownership anchor (ios/Packages/Networking/Sources/Networking/APIClient+Voice.swift)
// so §42 can append voice-specific convenience wrappers here without
// touching CallsEndpoints.swift which is shared infrastructure.

// MARK: - §42 voice convenience (append here for new voice-domain wrappers)

public extension APIClient {

    /// Fetch a single call detail row. Wraps `GET /api/v1/voice/calls/:id`.
    ///
    /// Returns `nil` on 404 (call not found or server feature not deployed).
    func fetchCallDetail(id: Int64) async throws -> CallLogEntry? {
        do {
            return try await get("/api/v1/voice/calls/\(id)", as: CallLogEntry.self)
        } catch let error as APITransportError {
            if case .httpStatus(404, _) = error { return nil }
            throw error
        }
    }

    /// Returns the recording stream URL for a call if one exists,
    /// by reading the `recording_url` field from the call detail row.
    ///
    /// Returns `nil` when the call has no recording or on 404.
    func fetchCallRecordingURL(callId: Int64) async throws -> URL? {
        guard let entry = try await fetchCallDetail(id: callId) else { return nil }
        guard let urlString = entry.recordingUrl else { return nil }
        return URL(string: urlString)
    }
}
