package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.util.FcmTokenRefresher
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * §21.5 — Periodic 7-day FCM token refresh worker.
 *
 * Firebase rotates device tokens infrequently, but tokens can expire silently on
 * devices that go offline for extended periods. This worker proactively calls
 * [FcmTokenRefresher.refreshIfStale] every 7 days so the server always holds a
 * valid token even when [FirebaseMessagingService.onNewToken] hasn't fired recently.
 *
 * The worker is a no-op when the user is not logged in (token registration
 * is guarded inside [FcmTokenRefresher]).
 *
 * Constraints:
 *   • [NetworkType.CONNECTED] — registration requires a live server call.
 *   • [setRequiresBatteryNotLow] — token refresh is non-urgent; defer if critical battery.
 *
 * Scheduling:
 *   Call [schedule] once from Application.onCreate(). [ExistingPeriodicWorkPolicy.KEEP]
 *   prevents duplicate jobs on repeated app launches.
 */
@HiltWorker
class TokenRefreshWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val fcmTokenRefresher: FcmTokenRefresher,
    private val authPreferences: AuthPreferences,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "TokenRefreshWorker started (attempt ${runAttemptCount + 1})")
        if (!authPreferences.isLoggedIn) {
            Log.d(TAG, "Not logged in — skipping token refresh")
            return Result.success()
        }
        return try {
            fcmTokenRefresher.refreshIfStale()
            Log.d(TAG, "Token refresh completed")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Token refresh failed [${e.javaClass.simpleName}]: ${e.message}")
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    companion object {
        private const val TAG = "TokenRefreshWorker"
        private const val WORK_NAME = "bizarre_crm_token_refresh"

        /**
         * Schedule the 7-day periodic FCM token refresh.
         *
         * §21.5 — Unique work name prevents stacking.
         * Exponential backoff (1h base) handles transient network failures gracefully
         * without hammering FCM or the CRM server.
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()

            val request = PeriodicWorkRequestBuilder<TokenRefreshWorker>(7, TimeUnit.DAYS)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.HOURS)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
            Log.d(TAG, "Token refresh scheduled (7d)")
        }
    }
}
