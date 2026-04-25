package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

// NOTE: AuthApi is kept as a constructor param for legacy callers / tests
// that inject FcmTokenRefresher directly. New registration logic delegates to
// DeviceTokenManager which sends the full 5-field payload.

/**
 * §1.7 line 238 — push-token refresh helper, invoked on every ON_START/ON_RESUME
 * to ensure the FCM registration token the server holds is not stale.
 *
 * ## Why periodic refresh
 * Firebase rotates FCM tokens silently (e.g. factory-reset, token revocation, app
 * update, or the 12-month automatic expiry). [FirebaseMessagingService.onNewToken]
 * fires on rotation, but there is a gap between token issue and the next cold-start
 * if the service was not running. [refreshIfStale] closes that gap by actively
 * re-fetching and re-registering once per 24-hour window.
 *
 * ## Idempotency
 * The 24-hour guard ([REFRESH_INTERVAL_MS]) means multiple rapid foreground/background
 * cycles do not result in repeated server calls. If the POST fails, the pref is not
 * updated so the next foreground cycle retries automatically.
 *
 * ## Security note
 * The raw FCM token is never logged at INFO or above. DEBUG-only logs are length-only.
 */
@Singleton
class FcmTokenRefresher @Inject constructor(
    private val appPreferences: AppPreferences,
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
    private val deviceTokenManager: DeviceTokenManager,
) {

    /**
     * Checks whether the FCM token was last refreshed more than [REFRESH_INTERVAL_MS]
     * ago and, if so, fetches the current token from Firebase and posts it to the
     * server via [AuthApi.registerDeviceToken].
     *
     * No-op when:
     *  - The user is not logged in (no token to register against).
     *  - The last refresh was within the 24-hour window.
     *
     * Must be called from a coroutine context (suspends for Firebase token fetch +
     * the network POST). Safe to call on any dispatcher — switches to IO internally.
     */
    suspend fun refreshIfStale() {
        if (!authPreferences.isLoggedIn) return

        val lastRefreshMs = appPreferences.lastFcmTokenRefreshAtMs
        val nowMs = System.currentTimeMillis()
        // Skip if within the 24-hour window AND already registered.
        // Always re-register if fcmTokenRegistered = false (e.g. after a token
        // rotation that fired while the user was logged out).
        if (appPreferences.fcmTokenRegistered && nowMs - lastRefreshMs < REFRESH_INTERVAL_MS) return

        withContext(Dispatchers.IO) {
            runCatching {
                val token = FirebaseMessaging.getInstance().token.await()
                if (BuildConfig.DEBUG) {
                    Timber.d("FcmTokenRefresher: fetched token (len=%d)", token.length)
                }
                // §13.2 — delegate to DeviceTokenManager which sends the full
                // 5-field payload and updates fcmToken + fcmTokenRegistered +
                // lastFcmTokenRefreshAtMs on success.
                val ok = deviceTokenManager.register(token)
                if (ok) {
                    Timber.i("FcmTokenRefresher: token refreshed and registered with server")
                }
            }.onFailure { e ->
                // Non-fatal — the existing token remains valid; retry next cycle.
                Timber.w(e, "FcmTokenRefresher: refresh failed, will retry on next foreground")
            }
        }
    }

    companion object {
        /** Refresh at most once every 24 hours. */
        private const val REFRESH_INTERVAL_MS = 24L * 60L * 60_000L
    }
}
