package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

/**
 * §42 — Voice / Calls API.
 *
 * All endpoints tolerate 404 — caller shows "VoIP not configured on this server".
 *
 * Server bridges audio; Android never handles raw RTP. The app posts call-log
 * events and receives call state via FCM high-priority data messages.
 *
 * §42.4 voicemail endpoints are also declared here since they share the same
 * Retrofit instance and VoIP-not-configured guard.
 */
interface VoiceApi {

    /**
     * List call log entries (inbound + outbound + missed).
     *
     * GET /voice/calls?direction=inbound|outbound|missed&limit=50&cursor=...
     * Response: { items: [...], next_cursor }
     * 404 → empty list / VoIP not configured stub.
     */
    @GET("voice/calls")
    suspend fun listCalls(
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<CallLogListData>

    /**
     * Fetch a single call detail including recording URL and transcription.
     *
     * GET /voice/calls/:id
     * 404 → "Call not found" error state.
     */
    @GET("voice/calls/{id}")
    suspend fun getCall(@Path("id") id: Long): ApiResponse<CallLogEntry>

    /**
     * Initiate an outbound VoIP call (§42.2 L3117).
     *
     * POST /voice/call
     * Body: { to_number, customer_id? }
     * Response: { call_id, status }
     * 404 → "VoIP not configured on this server".
     * Role-gated: staff+ only (enforced server-side; checked client-side too).
     */
    @POST("voice/call")
    suspend fun initiateCall(@Body request: InitiateCallRequest): ApiResponse<CallSessionData>

    /**
     * Hang up an active call (§42.2 L3121).
     *
     * POST /voice/call/:id/hangup
     * 404 → tolerated silently; local UI dismisses regardless.
     */
    @POST("voice/call/{id}/hangup")
    suspend fun hangup(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Post a call-log entry synced from the device to the tenant (§42.2 L3121).
     *
     * POST /call-logs
     * Body: CallLogEntry subset.
     * 404 → tolerated; log stored locally and retried via SyncManager.
     */
    @POST("call-logs")
    suspend fun postCallLog(@Body request: Map<String, @JvmSuppressWildcards Any>): ApiResponse<Unit>

    /**
     * Fetch the transcription for a recorded call (§42.3 L3126 — server-side, stub).
     *
     * GET /voice/calls/:id/transcription
     * 404 → "Transcription not available".
     */
    @GET("voice/calls/{id}/transcription")
    suspend fun getTranscription(@Path("id") id: Long): ApiResponse<TranscriptionData>

    // ── §42.3 Recording compliance ────────────────────────────────────────────

    /**
     * Fetch the tenant's recording-consent config.
     *
     * GET /voice/recording-config
     * Response: { enabled, two_party_required, announcement_url? }
     * 404 → recording not configured; UI shows opt-out state.
     */
    @GET("voice/recording-config")
    suspend fun getRecordingConfig(): ApiResponse<RecordingConfigData>

    /**
     * Save the user's per-session recording consent decision.
     *
     * POST /voice/recording-consent
     * Body: { call_id, consented }
     */
    @POST("voice/recording-consent")
    suspend fun postRecordingConsent(
        @Body body: RecordingConsentRequest,
    ): ApiResponse<Unit>

    // ── §42.4 Voicemail ───────────────────────────────────────────────────────

    /**
     * List voicemail messages from the tenant VoIP provider.
     *
     * GET /voice/voicemails?status=new|all&limit=25
     * Response: { items: [...], next_cursor }
     * 404 → VoIP not configured.
     */
    @GET("voice/voicemails")
    suspend fun listVoicemails(
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<VoicemailListData>

    /**
     * Mark a voicemail as heard.
     *
     * POST /voice/voicemails/:id/heard
     * 404 → tolerated (already deleted on provider).
     */
    @POST("voice/voicemails/{id}/heard")
    suspend fun markVoicemailHeard(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Delete (archive) a voicemail.
     *
     * DELETE /voice/voicemails/:id
     * 404 → tolerated.
     */
    @DELETE("voice/voicemails/{id}")
    suspend fun deleteVoicemail(@Path("id") id: Long): ApiResponse<Unit>
}

// ── DTOs ─────────────────────────────────────────────────────────────────────

data class CallLogListData(
    val items: List<CallLogEntry>,
    val next_cursor: String?,
)

data class CallLogEntry(
    val id: Long,
    val direction: String,           // inbound | outbound | missed
    val status: String,              // completed | in_progress | failed | missed
    val from_number: String,
    val to_number: String,
    val customer_id: Long?,
    val customer_name: String?,
    val duration_seconds: Int,
    val started_at: String,
    val ended_at: String?,
    val recording_url: String?,      // null = no recording
    val has_transcription: Boolean,
)

data class InitiateCallRequest(
    val to_number: String,
    val customer_id: Long? = null,
)

data class CallSessionData(
    val call_id: Long,
    val status: String,              // ringing | in_progress
    val caller_id_name: String?,
)

data class TranscriptionData(
    val call_id: Long,
    val text: String,
    val language: String?,
    val confidence: Float?,
)

// §42.3 Recording compliance DTOs
data class RecordingConfigData(
    val enabled: Boolean,
    /** true = two-party-consent jurisdiction; app must play announcement. */
    val two_party_required: Boolean,
    /** URL of the pre-recorded consent announcement played to the remote party. */
    val announcement_url: String?,
)

data class RecordingConsentRequest(
    val call_id: Long,
    val consented: Boolean,
)

// §42.4 Voicemail DTOs
data class VoicemailListData(
    val items: List<VoicemailEntry>,
    val next_cursor: String?,
)

data class VoicemailEntry(
    val id: Long,
    val from_number: String,
    val customer_name: String?,
    val customer_id: Long?,
    val duration_seconds: Int,
    val received_at: String,
    val status: String,         // new | heard
    val transcription: String?, // server-side transcription if available
    val audio_url: String?,
)
