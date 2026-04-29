package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Plan §20.3 L2110 — WorkManager worker that orchestrates the full sync cycle.
 *
 * ## Scheduling modes
 *
 * | Mode        | Trigger                             | Period     | Expedited |
 * |-------------|-------------------------------------|------------|-----------|
 * | Periodic    | [schedule] called on app open       | 15 min     | No        |
 * | One-time    | [syncNow] (e.g. pull-to-refresh)    | Immediate  | Yes (when quota available) |
 *
 * Both modes require [NetworkType.CONNECTED]. The expedited one-time request uses
 * [OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST] so it still runs when the
 * expedited quota is exhausted (degraded to normal priority, not dropped).
 *
 * ## Drain order
 *
 * The worker calls [SyncManager.syncAll] which calls [SyncManager.flushQueue].
 * [OrderedQueueProcessor] is used inside [SyncManager.flushQueue] to respect
 * FIFO + dependency ordering (plan §20.4 L2112).
 *
 * ## Backoff
 *
 * WorkManager exponential backoff is set to 1 min base. Per-entry retry logic
 * (up to [SyncQueueDao.MAX_RETRIES] = 5 attempts) lives inside [OrderedQueueProcessor].
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val syncManager: SyncManager,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "Starting sync (attempt ${runAttemptCount + 1})...")
        return try {
            syncManager.syncAll()
            Log.d(TAG, "Sync completed successfully")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed [${e.javaClass.simpleName}]: ${e.message}")
            if (runAttemptCount < MAX_WORKER_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    companion object {
        private const val TAG = "SyncWorker"
        private const val WORK_NAME_PERIODIC = "bizarre_crm_periodic_sync"
        private const val WORK_NAME_ONE_TIME = "sync_now"

        /** WorkManager retries before giving up on the worker itself (not queue entries). */
        private const val MAX_WORKER_ATTEMPTS = 3

        /**
         * Schedule the 15-minute periodic background sync.
         *
         * Plan §20.3 L2110 — [NetworkType.CONNECTED] ensures the worker never runs
         * when offline. [setRequiresBatteryNotLow] defers the background sync when
         * the battery is critically low (< 15 %) — on-demand syncs triggered by
         * user action ([syncNow]) are NOT battery-gated so the UI stays responsive.
         * [ExistingPeriodicWorkPolicy.KEEP] prevents stacking if called multiple times
         * (e.g. on every Activity resume and onStop).
         *
         * §21.5 — Unique work name [WORK_NAME_PERIODIC] coalesces duplicate schedules.
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()

            val request = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME_PERIODIC,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
            Log.d(TAG, "Periodic sync scheduled (15 min, battery-not-low constrained)")
        }

        /**
         * Trigger an immediate one-time sync.
         *
         * Plan §20.3 L2110 — The request is marked expedited so it runs at the
         * front of WorkManager's queue when the app is in the foreground.
         * [OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST] ensures it still
         * runs (at normal priority) when the system expedited quota is exhausted,
         * rather than being silently dropped.
         *
         * AUDIT-AND-022: [ExistingWorkPolicy.KEEP] prevents rapid back-to-back calls
         * (e.g. pull-to-refresh) from stacking duplicate workers.
         */
        fun syncNow(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(constraints)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME_ONE_TIME,
                ExistingWorkPolicy.KEEP,
                request,
            )
            Log.d(TAG, "One-time expedited sync enqueued")
        }
    }
}
