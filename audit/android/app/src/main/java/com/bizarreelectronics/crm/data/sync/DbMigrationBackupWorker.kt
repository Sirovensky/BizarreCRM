package com.bizarreelectronics.crm.data.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.*
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

/**
 * Out-of-band WorkManager worker for "heavy" database migrations.
 *
 * ## Purpose (ActionPlan Line 218)
 *
 * Some future schema migrations will need to back-fill millions of rows,
 * re-encode binary blobs, or rebuild large indices. Running those operations
 * on the main thread (or even inside Room's background thread during DB open)
 * blocks the UI for seconds and risks an ANR. This worker offloads such work
 * to an expedited WorkManager job that:
 *
 *  1. Shows a persistent foreground notification on the `MIGRATION_PROGRESS`
 *     channel so the user knows the app is busy — not frozen.
 *  2. Uses [OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST] as the
 *     fallback so the migration still runs even when the device is out of
 *     WorkManager expedited quota.
 *  3. Accepts a [KEY_FROM_VERSION] / [KEY_TO_VERSION] input pair so the
 *     worker knows which migration to run.
 *
 * ## Current state
 *
 * No migration in [com.bizarreelectronics.crm.data.local.db.MigrationRegistry.ALL_ENTRIES]
 * has `heavy = true` yet. The worker body logs a stub message. When the first
 * heavy migration is added, implement its logic in [doWork] and set `heavy = true`
 * on its [com.bizarreelectronics.crm.data.local.db.MigrationRegistry.Entry].
 *
 * ## Invocation
 *
 * [DatabaseModule] checks [com.bizarreelectronics.crm.data.local.db.MigrationRegistry.isHeavy]
 * after room opens. If any pending migration is flagged heavy, it enqueues this
 * worker via [enqueue].
 *
 * @constructor Hilt-injected via [@AssistedInject] as required by [@HiltWorker].
 */
@HiltWorker
class DbMigrationBackupWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted workerParams: WorkerParameters,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val fromVersion = inputData.getInt(KEY_FROM_VERSION, -1)
        val toVersion = inputData.getInt(KEY_TO_VERSION, -1)

        Log.i(TAG, "DbMigrationBackupWorker started for migration $fromVersion → $toVersion")

        setForeground(buildForegroundInfo(fromVersion, toVersion))

        return try {
            // --- Stub implementation ---
            // No heavy migration exists yet. When the first heavy migration is
            // added:
            //   1. Match on (fromVersion, toVersion).
            //   2. Open the DB directly (not via Room — Room is not open yet).
            //   3. Execute the heavy SQL in batches, updating progress via
            //      setForeground() between batches.
            //   4. Insert the AppliedMigrationEntity row via the DAO once done.
            Log.i(TAG, "Heavy migration $fromVersion → $toVersion: stub — no-op (no heavy migration registered yet)")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Heavy migration $fromVersion → $toVersion failed: ${e.message}", e)
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        }
    }

    private fun buildForegroundInfo(from: Int, to: Int): ForegroundInfo {
        ensureNotificationChannel()
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Database upgrade in progress")
            .setContentText("Upgrading database schema ($from → $to). Please wait…")
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setOngoing(true)
            .setProgress(0, 0, /* indeterminate = */ true)
            .build()
        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Database Migration",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while a database schema upgrade is running."
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "DbMigrationBackupWorker"
        private const val CHANNEL_ID = "MIGRATION_PROGRESS"
        private const val NOTIFICATION_ID = 9001

        const val KEY_FROM_VERSION = "from_version"
        const val KEY_TO_VERSION = "to_version"

        private const val WORK_NAME_PREFIX = "db_migration_heavy"

        /**
         * Enqueue a one-time expedited migration job for the given (from, to)
         * step. Unique work keyed on the version pair prevents duplicate jobs.
         */
        fun enqueue(context: Context, fromVersion: Int, toVersion: Int) {
            val input = workDataOf(
                KEY_FROM_VERSION to fromVersion,
                KEY_TO_VERSION to toVersion,
            )
            val request = OneTimeWorkRequestBuilder<DbMigrationBackupWorker>()
                .setInputData(input)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "$WORK_NAME_PREFIX-$fromVersion-$toVersion",
                ExistingWorkPolicy.KEEP,
                request,
            )
            Log.i(TAG, "Enqueued expedited heavy migration job $fromVersion → $toVersion")
        }
    }
}
