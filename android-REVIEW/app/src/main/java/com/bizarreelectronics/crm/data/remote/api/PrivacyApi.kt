package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.GET
import retrofit2.http.POST

/**
 * L2526 — GDPR / privacy API endpoints.
 *
 * All endpoints live under `/privacy/` and operate on the currently
 * authenticated user (resolved from the Bearer token on the server).
 *
 * ## 404 tolerance
 * These endpoints are new and may return 404 on older server deployments.
 * ViewModels using this API must map 404 to a "not supported" state and
 * surface a user-friendly message rather than crashing.
 *
 * ## Data export (async)
 * [exportMyData] returns a [ExportRequestResponse] carrying a [request_id].
 * The server processes the export asynchronously and either emails the result
 * or makes it available at a signed download URL.  The client does not poll
 * for completion — the user is notified via push or email.
 *
 * ## Account deletion (soft-delete)
 * [deleteMyAccount] triggers a server-side soft-delete of the user record and
 * immediately instructs the client to wipe local state (AppPreferences + auth).
 *
 * ## Consent status
 * [consentStatus] returns the timestamp at which the user accepted the current
 * privacy policy version and the version string itself.
 */
interface PrivacyApi {

    /**
     * POST /privacy/export-my-data
     *
     * Queues an async data-export job for the authenticated user.
     * Response carries a [request_id] for tracking; the actual data
     * arrives via email or a signed URL pushed through FCM.
     *
     * 404 → feature not yet deployed on this server; surface graceful fallback.
     */
    @POST("privacy/export-my-data")
    suspend fun exportMyData(): ApiResponse<ExportRequestResponse>

    /**
     * POST /privacy/delete-my-account
     *
     * Requests soft-deletion of the authenticated user's account.
     * After a successful response the client MUST:
     *   1. Clear [com.bizarreelectronics.crm.data.local.prefs.AppPreferences].
     *   2. Call [com.bizarreelectronics.crm.data.local.prefs.AuthPreferences.clear]
     *      with [com.bizarreelectronics.crm.data.local.prefs.AuthPreferences.ClearReason.UserLogout].
     *   3. Navigate to the login screen.
     *
     * 404 → feature not yet deployed; surface graceful fallback.
     */
    @POST("privacy/delete-my-account")
    suspend fun deleteMyAccount(): ApiResponse<DeleteAccountResponse>

    /**
     * GET /privacy/consent-status
     *
     * Returns the user's current consent record: the privacy policy version
     * they accepted and the timestamp of that acceptance.
     *
     * 404 → server does not track consent; [ConsentStatusResponse] defaults
     *   to `null` fields (caller renders "Not on record").
     */
    @GET("privacy/consent-status")
    suspend fun consentStatus(): ApiResponse<ConsentStatusResponse>
}

// ─── Response DTOs ────────────────────────────────────────────────────────────

/**
 * Response from [PrivacyApi.exportMyData].
 *
 * @property requestId Server-assigned ID for the async export job.
 */
data class ExportRequestResponse(
    @SerializedName("request_id")
    val requestId: String?,
)

/**
 * Response from [PrivacyApi.deleteMyAccount].
 *
 * @property message Human-readable confirmation message.
 * @property scheduledAt ISO-8601 timestamp when the server will permanently
 *   purge the record (grace period, e.g. 30 days). Null = immediate.
 */
data class DeleteAccountResponse(
    val message: String?,
    @SerializedName("scheduled_at")
    val scheduledAt: String? = null,
)

/**
 * Response from [PrivacyApi.consentStatus].
 *
 * @property consentedAt  ISO-8601 timestamp when the user accepted the policy.
 *   Null if no consent record exists.
 * @property policyVersion  Version string of the accepted policy (e.g. "2024-01").
 *   Null if no consent record exists.
 */
data class ConsentStatusResponse(
    @SerializedName("consented_at")
    val consentedAt: String? = null,
    @SerializedName("policy_version")
    val policyVersion: String? = null,
)
