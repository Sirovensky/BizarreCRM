package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.util.DeviceTokenManager
import com.google.firebase.messaging.FirebaseMessaging
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.tasks.await
import java.util.concurrent.TimeUnit

/**
 * §73.9 — One-time WorkManager worker that retries a failed FCM token
 * registration with exponential backoff.
 *
 * ## Problem
 * [DeviceTokenManager.register] previously set [AppPreferences.fcmTokenRegistered]
 * to `false` on failure and relied entirely on the next foreground cycle
 * ([FcmTokenRefresher.refreshIfStale]) to retry. If the user stays foregrounded
 * without navigating away — or if the server is unreachable for an extended window —
 * registration could remain failed indefinitely within that session.
 *
 * ## Solution
 * On each failed [DeviceTokenManager.register] call a one-time work request is
 * enqueued with [ExistingWorkPolicy.REPLACE] so only one retry chain is ever active.
 * WorkManager exponential backoff delivers attempts at:
 *
 *   1 min → 2 min → 4 min → 8 min → 16 min → 32 min → 64 min (≈ 1h) →
 *   128 min (≈ 2h) → 256 min (≈ 4h) → 360 min cap (6h max)
 *
 * WorkManager caps [BackoffPolicy.EXPONENTIAL] at 5 hours (18 000 s). After
 * [MAX_ATTEMPTS] the worker returns [Result.failure] and stops retrying. The
 * normal foreground cycle ([FcmTokenRefresher]) still acts as a safety net.
 *
 * ## Retry counter
 * [AppPreferences.fcmRetryAttemptCount] tracks how many backoff attempts have
 * been made in the current failure run. It is reset to 0 on every successful
 * registration so the UI (and logs) can surface retry depth to support staff.
 *
 * ## Manual re-register
 * [NotificationSettingsViewModel.reRegisterPushToken] already exists and
 * calls [DeviceTokenManager.registerIfNeeded]. After this change that call
 * also cancels any pending retry work and kicks off a fresh immediate attempt,
 * so the manual button still works as a one-tap escape hatch independent of
 * the backoff schedule.
 */
@HiltWorker
class FcmTokenRetryWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val appPreferences: AppPreferences,
    private val authPreferences: AuthPreferences,
    private val deviceTokenManager: DeviceTokenManager,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val attempt = runAttemptCount + 1
        Log.d(TAG, "FcmTokenRetryWorker attempt $attempt / $MAX_ATTEMPTS")

        if (!authPreferences.isLoggedIn) {
            // User logged out while retry was pending — abandon cleanly.
            Log.d(TAG, "Not logged in; abandoning FCM retry chain")
            appPreferences.fcmRetryAttemptCount = 0
            return Result.success()
        }

        if (appPreferences.fcmTokenRegistered) {
            // Another path (foreground cycle / manual re-register) succeeded first.
            Log.d(TAG, "Token already registered; cancelling retry chain")
            appPreferences.fcmRetryAttemptCount = 0
            return Result.success()
        }

        return try {
            val token = FirebaseMessaging.getInstance().token.await()
            val ok = deviceTokenManager.register(token)
            if (ok) {
                // DeviceTokenManager.register already resets fcmRetryAttemptCount.
                Log.i(TAG, "FCM token retry succeeded on attempt $attempt")
                Result.success()
            } else {
                handleFailure(attempt)
            }
        } catch (e: Exception) {
            Log.w(TAG, "FcmTokenRetryWorker exception on attempt $attempt: ${e.message}")
            handleFailure(attempt)
        }
    }

    private fun handleFailure(attempt: Int): Result {
        appPreferences.fcmRetryAttemptCount = attempt
        return if (attempt >= MAX_ATTEMPTS) {
            Log.w(TAG, "FCM token registration exhausted $MAX_ATTEMPTS attempts — giving up; foreground cycle will retry")
            Result.failure()
        } else {
            Log.d(TAG, "Retrying FCM token registration (attempt $attempt / $MAX_ATTEMPTS)")
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "FcmTokenRetryWorker"

        /**
         * Unique work name.  [ExistingWorkPolicy.REPLACE] ensures only one retry
         * chain is active at any time.
         */
        const val WORK_NAME = "bizarre_crm_fcm_token_retry"

        /**
         * Maximum retry attempts before the worker gives up.  The foreground cycle
         * ([FcmTokenRefresher.refreshIfStale]) remains active as a safety net beyond
         * this point — it runs on every ON_START for the 24-h staleness window.
         */
        private const val MAX_ATTEMPTS = 7

        /**
         * Enqueue a one-time retry work request with exponential backoff.
         *
         * Calling this when a retry is already pending replaces the existing work
         * ([ExistingWorkPolicy.REPLACE]) so a manual re-register or a second rapid
         * failure doesn't stack multiple chains.
         *
         * Requires [NetworkType.CONNECTED] — there is no point attempting token
         * registration without a network connection.
         *
         * @param context Application context.
         */
        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            // Base backoff 1 minute, exponential.  WorkManager caps at ~5 h per
            // Android platform rules.  MAX_ATTEMPTS gates the total retry count so
            // the chain terminates rather than running indefinitely.
            val request = OneTimeWorkRequestBuilder<FcmTokenRetryWorker>()
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    1L,
                    TimeUnit.MINUTES,
                )
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request,
            )
            Log.d(TAG, "FCM token retry work enqueued (ExistingWorkPolicy.REPLACE)")
        }

        /**
         * Cancel any pending retry work.
         *
         * Called by [NotificationSettingsViewModel.reRegisterPushToken] before
         * triggering a manual immediate re-registration so the backoff chain does
         * not interfere with the manual attempt.
         *
         * @param context Application context.
         */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d(TAG, "FCM token retry work cancelled (manual re-register triggered)")
        }
    }
}
