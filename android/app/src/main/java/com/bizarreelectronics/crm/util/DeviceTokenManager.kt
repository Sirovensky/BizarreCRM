package com.bizarreelectronics.crm.util

import android.content.Context
import android.os.Build
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.sync.FcmTokenRetryWorker
import com.google.firebase.messaging.FirebaseMessaging
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §13.2 — Centralised FCM device-token lifecycle manager.
 *
 * Owns three responsibilities:
 *
 *  1. [register] — POST auth/device-token with the full 5-field payload
 *     { token, platform, model, os_version, app_version }.  Called from:
 *       - [FcmService.onNewToken] (Firebase rotation)
 *       - [FcmTokenRefresher.refreshIfStale] (24-hour staleness gate)
 *       - [BizarreCrmApp] on [AuthPreferences.isLoggedInFlow] true-transition
 *         (first login after a cold start where the FCM token is already stale)
 *
 *  2. [registerIfNeeded] — fetches the current Firebase token and calls
 *     [register] only when [AppPreferences.fcmTokenRegistered] is false or the
 *     token has not been registered with the server for this session.  Safe to
 *     call on any dispatcher; switches to IO internally.
 *
 *  3. [unregister] — calls `FirebaseMessaging.getInstance().deleteToken()` and
 *     then DELETE auth/device-token?token=<t> so the server stops routing pushes
 *     to a device whose session has ended.  Uses [runCatching] so a network or
 *     Firebase failure never blocks the logout flow.
 *
 * ## Security
 * The raw FCM token is never logged at INFO or above.  DEBUG logs include only
 * token length.
 */
@Singleton
class DeviceTokenManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appPreferences: AppPreferences,
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
) {

    /**
     * Build the full 5-field registration payload that the server expects.
     *
     * Fields:
     *   token       — FCM registration token (sensitive; never logged raw)
     *   platform    — always "android"
     *   model       — e.g. "Pixel 7" via Build.MODEL
     *   os_version  — Android OS version string, e.g. "14" (SDK 34)
     *   app_version — BuildConfig.VERSION_NAME, e.g. "1.2.3"
     */
    private fun buildPayload(token: String): Map<String, String> = mapOf(
        "token" to token,
        "platform" to "android",
        "model" to Build.MODEL,
        "os_version" to Build.VERSION.RELEASE,
        "app_version" to BuildConfig.VERSION_NAME,
    )

    /**
     * Register [token] with the server using the full 5-field payload.
     *
     * On success, persists the token to [AppPreferences.fcmToken] and marks
     * [AppPreferences.fcmTokenRegistered] = true so the 24-hour staleness gate
     * in [FcmTokenRefresher] does not redundantly re-register.
     *
     * Must be called from a coroutine; is IO-dispatched internally.
     *
     * @return true if registration succeeded, false on any error.
     */
    suspend fun register(token: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            authApi.registerDeviceToken(buildPayload(token))
            appPreferences.fcmToken = token
            appPreferences.fcmTokenRegistered = true
            appPreferences.lastFcmTokenRefreshAtMs = System.currentTimeMillis()
            // §73.9 — reset retry counter on success so diagnostics row shows 0.
            appPreferences.fcmRetryAttemptCount = 0
            // Cancel any pending retry work — registration succeeded.
            FcmTokenRetryWorker.cancel(context)
            if (BuildConfig.DEBUG) {
                Timber.d("DeviceTokenManager: token registered (len=%d)", token.length)
            }
            true
        }.onFailure { e ->
            // Non-fatal — server unreachable or auth expired.
            Timber.w(e, "DeviceTokenManager: register failed, scheduling exponential-backoff retry")
            appPreferences.fcmTokenRegistered = false
            // §73.9 — enqueue a WorkManager one-time retry with exponential backoff
            // (1 min base, max 7 attempts).  ExistingWorkPolicy.REPLACE means
            // multiple rapid failures do not stack parallel chains.
            FcmTokenRetryWorker.enqueue(context)
        }.getOrDefault(false)
    }

    /**
     * Fetch the current FCM token from Firebase and register with the server
     * only if [AppPreferences.fcmTokenRegistered] is false (i.e. the server
     * does not yet have a fresh token for this device).
     *
     * Called by [BizarreCrmApp] on login-state transition (true) so a user who
     * logs in after a token rotation that fired while they were logged out gets
     * re-registered immediately without waiting for the 24-hour gate.
     *
     * No-op when the user is not logged in.
     */
    suspend fun registerIfNeeded() {
        if (!authPreferences.isLoggedIn) return
        if (appPreferences.fcmTokenRegistered) return

        withContext(Dispatchers.IO) {
            runCatching {
                val token = FirebaseMessaging.getInstance().token.await()
                register(token)
            }.onFailure { e ->
                Timber.w(e, "DeviceTokenManager: registerIfNeeded Firebase fetch failed")
            }
        }
    }

    /**
     * Unregister this device from push notifications.
     *
     * Sequence:
     *  1. Read the last-known FCM token from [AppPreferences.fcmToken].
     *  2. Call `FirebaseMessaging.getInstance().deleteToken()` so Firebase
     *     stops issuing messages to this installation.
     *  3. Send DELETE auth/device-token?token=<t> so the server removes its
     *     record and stops routing pushes.
     *  4. Clear [AppPreferences.fcmToken] and reset [AppPreferences.fcmTokenRegistered].
     *
     * Uses [runCatching] on every step so a network or Firebase failure never
     * blocks the logout flow. Any error is logged at WARN level only.
     *
     * Must be called from a coroutine; switches to IO internally.
     */
    suspend fun unregister() = withContext(Dispatchers.IO) {
        val token = appPreferences.fcmToken

        // Step 1: tell Firebase to rotate/invalidate this token on the client side.
        runCatching {
            FirebaseMessaging.getInstance().deleteToken().await()
            if (BuildConfig.DEBUG) {
                Timber.d("DeviceTokenManager: Firebase token deleted")
            }
        }.onFailure { e ->
            Timber.w(e, "DeviceTokenManager: Firebase deleteToken failed (non-fatal)")
        }

        // Step 2: tell the server to drop its record.
        if (!token.isNullOrBlank()) {
            runCatching {
                authApi.deleteDeviceToken(token)
                if (BuildConfig.DEBUG) {
                    Timber.d("DeviceTokenManager: server-side token deleted (len=%d)", token.length)
                }
            }.onFailure { e ->
                Timber.w(e, "DeviceTokenManager: server deleteDeviceToken failed (non-fatal)")
            }
        }

        // Step 3: clear local state regardless of network outcome.
        appPreferences.fcmToken = null
        appPreferences.fcmTokenRegistered = false
    }
}
