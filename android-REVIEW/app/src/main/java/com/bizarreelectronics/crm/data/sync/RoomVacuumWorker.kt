package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * §29.7 — Weekly SQLite VACUUM to reclaim fragmented pages.
 *
 * SQLCipher (Room) does not auto-VACUUM; free pages accumulate as rows are
 * deleted during cache-purge, dead-letter eviction, and logout wipes. A weekly
 * VACUUM rewrites the database file end-to-end, reclaiming unused pages and
 * keeping the on-disk footprint near the logical data size.
 *
 * ## Why weekly?
 * VACUUM is an O(n) full-file rewrite and locks the database during the
 * operation (~0.3–1 s on a 20 MB DB on a Pixel 6a). Running it more often
 * wastes battery and I/O for marginal gains; less often lets fragmentation
 * accumulate. Weekly is the same cadence SQLite's own documentation recommends
 * for moderately active databases.
 *
 * ## Constraints
 * - [NetworkType.NOT_REQUIRED] — VACUUM is a local disk operation.
 * - [setRequiresBatteryNotLow] — avoids running on a draining battery.
 * - [setRequiresStorageNotLow] — defers when the device is near storage capacity.
 *
 * ## Scheduling
 * Call [schedule] once from [com.bizarreelectronics.crm.BizarreCrmApp.onCreate].
 * [ExistingPeriodicWorkPolicy.KEEP] prevents stacking on multiple app-opens.
 */
@HiltWorker
class RoomVacuumWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val db: BizarreDatabase,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "RoomVacuumWorker started (attempt ${runAttemptCount + 1})")
        return try {
            // VACUUM must be issued outside a Room transaction — call raw
            // SQL on the underlying SupportSQLiteDatabase.  Room ensures the
            // query runs on Dispatchers.IO via the CoroutineWorker dispatcher.
            db.openHelper.writableDatabase.execSQL("VACUUM")
            Log.i(TAG, "SQLite VACUUM completed successfully")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "RoomVacuumWorker failed [${e.javaClass.simpleName}]: ${e.message}")
            if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    companion object {
        private const val TAG = "RoomVacuumWorker"
        private const val WORK_NAME = "bizarre_crm_room_vacuum"

        /** Max WorkManager-level retries before giving up for this week's cycle. */
        private const val MAX_ATTEMPTS = 2

        /**
         * Schedule a weekly Room VACUUM.
         *
         * Idempotent: [ExistingPeriodicWorkPolicy.KEEP] preserves an already-
         * scheduled request across multiple [BizarreCrmApp.onCreate] calls.
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiresBatteryNotLow(true)
                .setRequiresStorageNotLow(true)
                .build()

            val request = PeriodicWorkRequestBuilder<RoomVacuumWorker>(7, TimeUnit.DAYS)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
            Log.d(TAG, "Room VACUUM scheduled (weekly, battery-not-low + storage-not-low constrained)")
        }
    }
}
