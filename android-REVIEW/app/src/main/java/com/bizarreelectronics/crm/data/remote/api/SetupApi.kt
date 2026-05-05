package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.SetupCompleteResponse
import com.bizarreelectronics.crm.data.remote.dto.SetupProgressRequest
import com.bizarreelectronics.crm.data.remote.dto.SetupProgressResponse
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST

/**
 * §2.10 [plan:L343] — Retrofit interface for the setup wizard progress endpoints.
 *
 * All three methods are unauthenticated (server accepts calls before any user
 * account exists). 404 on [getProgress] or [postProgress] means the server is
 * running an older build that does not expose these endpoints; callers MUST
 * handle 404 gracefully by using local-only DataStore persistence.
 *
 * Server contract (packages/server/src/routes/setup.routes.ts — TBD):
 *   GET  /api/v1/setup/progress         → SetupProgressResponse
 *   POST /api/v1/setup/progress         → ApiResponse<Unit>
 *   POST /api/v1/setup/complete         → SetupCompleteResponse
 */
interface SetupApi {

    /**
     * Resume a previously-started wizard session.
     *
     * Returns which steps are already saved and the server's recommended
     * resume point ([SetupProgressResponse.resumeAtStep], 0-based).
     *
     * 404 → server does not support wizard progress; ViewModel falls back
     * to local DataStore.
     */
    @GET("setup/progress")
    suspend fun getProgress(): ApiResponse<SetupProgressResponse>

    /**
     * Persist a single step's data on the server.
     *
     * [body.stepIndex] is 0-based. [body.data] is the step-specific key/value
     * map documented in each step composable's KDoc. Idempotent — re-posting
     * the same step index overwrites the previous record.
     *
     * 404 → server does not support wizard progress; ViewModel stores locally.
     */
    @POST("setup/progress")
    suspend fun postProgress(@Body body: SetupProgressRequest): ApiResponse<Unit>

    /**
     * Signal that all required steps are complete and the server should
     * finalise the tenant setup (seed statuses, tax classes, payment methods
     * collected during the wizard).
     *
     * On success the server may return an [SetupCompleteResponse.accessToken]
     * so the user is auto-logged-in without a separate POST /auth/login call.
     *
     * 409 → setup was already completed; treat as success and navigate to
     * dashboard.
     */
    @POST("setup/complete")
    suspend fun completeSetup(): ApiResponse<SetupCompleteResponse>

    /**
     * §3.14 L582 — Insert demo sample data (5 customers, 10 tickets, 3 invoices).
     *
     * Endpoint: `POST /onboarding/sample-data`
     *
     * Idempotent — if sample data is already loaded, the server returns the
     * current state rather than duplicating rows.
     *
     * 404 → server does not yet support sample data; caller treats as no-op.
     */
    @POST("onboarding/sample-data")
    suspend fun loadSampleData(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /**
     * §3.14 L582 — Remove all demo sample data inserted by [loadSampleData].
     *
     * Endpoint: `DELETE /onboarding/sample-data`
     *
     * 404 → no sample data loaded or endpoint not supported; caller treats as no-op.
     */
    @DELETE("onboarding/sample-data")
    suspend fun clearSampleData(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /**
     * §3.14 L582 — Check whether sample data is currently loaded.
     *
     * Endpoint: `GET /onboarding/state`
     *
     * Expected shape: `{ "sample_data_loaded": true, "sample_data_counts": { ... } }`
     * 404 → server does not support onboarding state; caller treats as not loaded.
     */
    @GET("onboarding/state")
    suspend fun getOnboardingState(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
