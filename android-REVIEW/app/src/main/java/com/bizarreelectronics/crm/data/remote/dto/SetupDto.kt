package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

// ─── §2.10 [plan:L343] — Setup wizard progress DTOs ────────────────────────
//
// Server contract:
//   POST /setup/progress  { step_index: Int, data: Map<String,Any> }
//   GET  /setup/progress  → SetupProgressResponse
//   POST /setup/complete  { } → SetupCompleteResponse
//
// 404 from either endpoint means the server predates the wizard endpoints; the
// ViewModel falls back to local-only progress stored in DataStore / SharedPrefs.

/**
 * §2.10 — Request body for POST /setup/progress.
 *
 * [stepIndex] is 0-based (step 1 = index 0, step 13 = index 12).
 * [data] holds the key/value payload collected by the step composable.
 * Shape of [data] is step-specific; see each Step composable's KDoc for
 * the exact keys sent to the server.
 */
data class SetupProgressRequest(
    @SerializedName("step_index") val stepIndex: Int,
    @SerializedName("data")       val data: Map<String, @JvmSuppressWildcards Any>,
)

/**
 * §2.10 — Response from GET /setup/progress.
 *
 * [completedSteps] contains the 0-based indices of steps already saved.
 * [stepData] is the server-echoed data map keyed by step index string.
 * [resumeAtStep] is the server's suggestion for which step to open (0-based).
 */
data class SetupProgressResponse(
    @SerializedName("completed_steps") val completedSteps: List<Int>,
    @SerializedName("step_data")       val stepData: Map<String, @JvmSuppressWildcards Any>?,
    @SerializedName("resume_at_step")  val resumeAtStep: Int = 0,
)

/**
 * §2.10 — Response from POST /setup/complete.
 *
 * [accessToken] and [refreshToken] may be issued by the server on completion
 * so the user does not need to log in separately (mirrors SetupResponse §2.7).
 * [message] is a human-readable confirmation.
 */
data class SetupCompleteResponse(
    @SerializedName("access_token")  val accessToken: String?  = null,
    @SerializedName("refresh_token") val refreshToken: String? = null,
    @SerializedName("message")       val message: String?      = null,
)
