package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.util.IntegrityVerdict
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.POST

/**
 * L2534 — Play Integrity server-side verification endpoint.
 *
 * After [com.bizarreelectronics.crm.util.PlayIntegrityClient] acquires a
 * signed token from the Play Integrity API, the token is forwarded to the
 * CRM server for authoritative verification.  The server decodes the token
 * using the Google Play Integrity API (server library) and returns a verdict.
 *
 * ## 404 tolerance
 * This endpoint may return 404 on servers that have not yet deployed the
 * Play Integrity verification route.  Callers must treat 404 as a non-blocking
 * "not supported" state — the action proceeds unless the tenant policy is strict.
 *
 * ## Strict mode
 * When the tenant has [IntegrityVerdict.strict] = true, a failed or missing
 * integrity check blocks the action (e.g. high-value refund).  In all other
 * cases it is a warning only.
 */
interface IntegrityApi {

    /**
     * POST /integrity/verify
     *
     * Submits a Play Integrity token for server-side verification.
     *
     * @param request Contains the raw encoded [IntegrityTokenRequest.token] and
     *   the action identifier that triggered the check (for server-side audit).
     * @return [IntegrityVerdict] embedded in [ApiResponse].
     */
    @POST("integrity/verify")
    suspend fun verifyToken(
        @Body request: IntegrityVerifyRequest,
    ): ApiResponse<IntegrityVerdict>
}

/**
 * Request body for [IntegrityApi.verifyToken].
 *
 * @property token   The encoded Play Integrity token string from
 *   [com.google.android.play.core.integrity.IntegrityTokenResponse.token].
 * @property action  Identifier of the action that triggered the check, e.g.
 *   "auth_success", "high_value_refund".  Used for server-side audit logging.
 */
data class IntegrityVerifyRequest(
    @SerializedName("token")
    val token: String,
    @SerializedName("action")
    val action: String,
)
