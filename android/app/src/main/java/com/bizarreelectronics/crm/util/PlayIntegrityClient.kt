package com.bizarreelectronics.crm.util

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.IntegrityTokenResponse
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.tasks.await
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * L2532 — Play Integrity API client.
 *
 * Requests a signed attestation token from the Play Integrity API and returns
 * it to the server via [com.bizarreelectronics.crm.data.remote.api.IntegrityApi]
 * for server-side verification.
 *
 * ## When to call
 * - After a successful authentication (to bind the device's integrity state to
 *   the session).
 * - Before high-value operations flagged as suspicious (e.g. a refund > $500,
 *   or a login from a new device).
 *
 * ## Non-GMS devices
 * On devices without Google Mobile Services the [IntegrityManagerFactory]
 * call throws [com.google.android.gms.common.GooglePlayServicesNotAvailableException]
 * or [java.lang.IllegalStateException].  [requestToken] catches these and
 * returns `null` rather than crashing.  Callers treat a `null` result as a
 * warning-only outcome unless the tenant policy is `strict: true` (see
 * [IntegrityVerdict.strict]).
 *
 * ## Thread safety
 * [requestToken] is a suspend function backed by [kotlinx.coroutines.tasks.await]
 * on a [com.google.android.gms.tasks.Task].  It is safe to call from any
 * coroutine context; it does NOT need to run on the main thread.
 */
@Singleton
class PlayIntegrityClient @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    private companion object {
        private const val TAG = "PlayIntegrityClient"
        // Cloud project number — required by IntegrityTokenRequest.
        // 0 = not configured; replace with your Google Cloud project number in production.
        private const val CLOUD_PROJECT_NUMBER = 0L
    }

    /**
     * Requests a Play Integrity token bound to [nonce].
     *
     * The [nonce] must be a URL-safe Base64-encoded string of at least 16 bytes,
     * generated server-side and embedded in the API response that triggered the
     * integrity check.  It is bound into the token's payload so the server can
     * confirm this specific request was attested.
     *
     * @param nonce Server-supplied nonce (URL-safe Base64, ≥ 16 bytes).
     * @return     The [IntegrityTokenResponse] on success, or `null` on non-GMS
     *             devices or when the Play Integrity API is unavailable.
     */
    suspend fun requestToken(nonce: String): IntegrityTokenResponse? {
        return try {
            val manager = IntegrityManagerFactory.create(context)
            val request = IntegrityTokenRequest.builder()
                .setNonce(nonce)
                .apply {
                    if (CLOUD_PROJECT_NUMBER != 0L) {
                        setCloudProjectNumber(CLOUD_PROJECT_NUMBER)
                    }
                }
                .build()
            val response = manager.requestIntegrityToken(request).await()
            Timber.tag(TAG).d("Play Integrity token acquired (nonce=%s)", nonce.take(8))
            response
        } catch (e: Exception) {
            // Non-GMS device, Play Services unavailable, or API quota exceeded.
            // Log as a warning — this is non-blocking unless tenant policy is strict.
            Timber.tag(TAG).w(e, "Play Integrity token request failed — non-blocking")
            null
        }
    }

    /**
     * Convenience helper: returns the raw token string from a successful
     * [requestToken] call, or `null` if the request failed.
     *
     * @param nonce Server-supplied nonce.
     * @return     Encoded integrity token string, or `null`.
     */
    suspend fun requestTokenString(nonce: String): String? =
        requestToken(nonce)?.token()
}

/**
 * Server-side verdict returned by
 * [com.bizarreelectronics.crm.data.remote.api.IntegrityApi.verifyToken].
 *
 * @property passed  True when the server verified the token and all checks passed.
 * @property strict  True when the tenant policy requires integrity — failure blocks the action.
 * @property reason  Human-readable explanation for a failed verdict (debug only).
 */
data class IntegrityVerdict(
    val passed: Boolean,
    val strict: Boolean = false,
    val reason: String? = null,
)
