package com.bizarreelectronics.crm.util

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * L2532 / LOGIN-MOCK-256 — Play Integrity API client.
 *
 * Acquires a signed attestation token for high-risk login events (new-device
 * sign-in, suspicious auth patterns). The token is forwarded to the CRM server
 * as the `X-Integrity-Token` header on `POST /auth/login` for cloud-hosted
 * tenants; self-hosted installs are explicitly ungated (see [requestTokenString]).
 *
 * ## Non-GMS devices
 * On devices without Google Play Services (e.g. Huawei, Amazon Fire), the
 * `IntegrityManagerFactory` call throws `IllegalStateException` ("not supported").
 * This is caught and silently returns `null` so the login flow is never blocked.
 *
 * ## Nonce contract
 * The nonce must be at least 16 bytes, base64url-encoded (no padding). The caller
 * is responsible for generating a per-request nonce with sufficient entropy.
 * [buildNonce] is a convenience helper that uses [java.security.SecureRandom].
 *
 * ## Caching
 * Tokens are **not** cached — the Play Integrity API enforces its own server-side
 * limits. Each high-risk event should trigger a fresh request.
 */
@Singleton
class PlayIntegrityClient @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    companion object {
        private const val TAG = "PlayIntegrityClient"

        /**
         * Generates a cryptographically random, base64url-encoded nonce.
         *
         * The Play Integrity API requires a minimum of 16 bytes of entropy.
         * We use 24 bytes (192 bits) to provide a comfortable margin and encode
         * with URL-safe base64 without padding as required by the API spec.
         */
        fun buildNonce(): String {
            val bytes = ByteArray(24)
            java.security.SecureRandom().nextBytes(bytes)
            return android.util.Base64.encodeToString(
                bytes,
                android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP,
            )
        }
    }

    /**
     * Requests a Play Integrity attestation token.
     *
     * Suspends until the token is available or the request fails.
     *
     * @param nonce A per-request nonce; use [buildNonce] unless you have a
     *   server-issued nonce for replay prevention.
     * @return The encoded token string, or `null` if:
     *   - Play Services is unavailable (non-GMS device).
     *   - The request fails for any reason (network, quota, API error).
     *   Never throws — callers must not block the login flow on a `null` result.
     */
    suspend fun requestTokenString(nonce: String): String? {
        Timber.d("%s: requesting integrity token (nonce prefix=%s)", TAG, nonce.take(8))
        return try {
            val manager = IntegrityManagerFactory.create(context)
            val tokenResponse = suspendCancellableCoroutine<com.google.android.play.core.integrity.IntegrityTokenResponse> { cont ->
                val task = manager.requestIntegrityToken(
                    IntegrityTokenRequest.builder()
                        .setNonce(nonce)
                        .build()
                )
                task.addOnSuccessListener { response ->
                    if (cont.isActive) cont.resume(response)
                }
                task.addOnFailureListener { exception ->
                    if (cont.isActive) cont.resumeWithException(exception)
                }
                cont.invokeOnCancellation {
                    // Tasks from Play Core are not cancellable, but we avoid
                    // resuming the continuation after cancellation via the
                    // isActive guards above.
                }
            }
            val token = tokenResponse.token()
            Timber.d("%s: token acquired (length=%d)", TAG, token.length)
            token
        } catch (e: IllegalStateException) {
            // Play Services unavailable — Huawei, Amazon Fire, or non-GMS ROM.
            // This is not an error from the app's perspective; fall through silently.
            Timber.d("%s: Play Integrity not available on this device (%s)", TAG, e.message)
            null
        } catch (e: Exception) {
            // Network failure, quota exceeded, or any other transient error.
            // Log at warn — these are unexpected but must not block login.
            Timber.w(e, "%s: requestIntegrityToken failed — proceeding without attestation", TAG)
            null
        }
    }
}

data class IntegrityVerdict(
    val passed: Boolean,
    val strict: Boolean = false,
    val reason: String? = null,
)
