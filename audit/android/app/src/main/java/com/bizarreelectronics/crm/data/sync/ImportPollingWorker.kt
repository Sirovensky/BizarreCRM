package com.bizarreelectronics.crm.data.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.bizarreelectronics.crm.data.remote.api.ImportApi
import com.bizarreelectronics.crm.ui.screens.importdata.ImportSource
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.delay
import retrofit2.HttpException
import java.util.concurrent.TimeUnit

/**
 * §50 — WorkManager background poller for API-key import jobs
 * (RepairDesk / RepairShopr / MyRepairApp).
 *
 * Enqueued by [DataImportViewModel] immediately after the server accepts a
 * start request. This ensures the user gets a completion notification even if
 * they navigate away from the import screen or the process is killed by the OS.
 *
 * The worker polls the appropriate status endpoint every [POLL_INTERVAL_MS]
 * until the job reports DONE or ERROR, then fires a local notification via
 * the `IMPORT_PROGRESS` channel.
 *
 * A foreground notification is shown during polling so the worker is not
 * killed by Doze. The ongoing notification is replaced by a completion
 * (or error) notification when the job finishes.
 *
 * Unique work name is keyed on the source so only one poller runs per source
 * at a time. [ExistingWorkPolicy.REPLACE] ensures a new import supersedes any
 * stale poller from a previous session.
 */
@HiltWorker
class ImportPollingWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted workerParams: WorkerParameters,
    private val importApi: ImportApi,
) : CoroutineWorker(context, workerParams) {

    override suspend fun getForegroundInfo(): ForegroundInfo =
        buildForegroundInfo("Import in progress…", indeterminate = true)

    override suspend fun doWork(): Result {
        val sourceName = inputData.getString(KEY_SOURCE) ?: return Result.failure()
        val source = runCatching { ImportSource.valueOf(sourceName) }.getOrNull()
            ?: return Result.failure()

        Log.i(TAG, "ImportPollingWorker started for source=$sourceName")

        setForeground(buildForegroundInfo("Importing from ${source.label}…", indeterminate = true))

        var consecutiveErrors = 0

        while (true) {
            delay(POLL_INTERVAL_MS)
            try {
                val response = when (source) {
                    ImportSource.REPAIR_DESK -> importApi.getRepairDeskStatus()
                    ImportSource.SHOPR       -> importApi.getRepairShoprStatus()
                    ImportSource.MRA         -> importApi.getMraStatus()
                    ImportSource.GENERIC_CSV -> {
                        // CSV imports are synchronous — no background polling needed.
                        Log.i(TAG, "GENERIC_CSV source — nothing to poll, exiting worker")
                        return Result.success()
                    }
                }
                consecutiveErrors = 0

                val data = response.data as? Map<*, *> ?: continue
                val isActive = (data["is_active"] as? Boolean) ?: false
                val overall = data["overall"] as? Map<*, *>

                val imported = (overall?.get("imported") as? Number)?.toInt() ?: 0
                val errors   = (overall?.get("errors") as? Number)?.toInt() ?: 0
                val total    = (overall?.get("total_records") as? Number)?.toInt() ?: 0

                @Suppress("UNCHECKED_CAST")
                val runs = data["runs"] as? List<Map<*, *>> ?: emptyList()
                val allDone = runs.isNotEmpty() && runs.all { r ->
                    val st = r["status"] as? String ?: ""
                    st == "completed" || st == "failed" || st == "cancelled"
                }
                val anyFailed = runs.any { r -> r["status"] == "failed" }

                if (!isActive && allDone) {
                    val title = if (anyFailed) "Import finished with errors" else "Import complete"
                    val text = "$imported imported · $errors errors · $total total"
                    notifyCompletion(title, text, isError = anyFailed)
                    Log.i(TAG, "ImportPollingWorker done: source=$sourceName $text")
                    return Result.success()
                }

                // Update foreground notification with progress
                val fraction = if (total > 0) "$imported / $total" else "…"
                setForeground(buildForegroundInfo(
                    "Importing from ${source.label}: $fraction",
                    indeterminate = total == 0,
                    progress = if (total > 0) imported * 100 / total else 0,
                    maxProgress = 100,
                ))

            } catch (e: HttpException) {
                if (e.code() == 404) {
                    Log.w(TAG, "Import status endpoint returned 404 — aborting poller")
                    return Result.failure()
                }
                consecutiveErrors++
                Log.w(TAG, "HTTP ${e.code()} polling import status (errors=$consecutiveErrors)")
                if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                    notifyCompletion("Import status unknown", "Could not reach server — check import history.", isError = true)
                    return Result.failure()
                }
            } catch (e: Exception) {
                consecutiveErrors++
                Log.w(TAG, "Error polling import status: ${e.message} (errors=$consecutiveErrors)")
                if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                    notifyCompletion("Import status unknown", "Network error — check import history.", isError = true)
                    return Result.failure()
                }
            }
        }
    }

    private fun buildForegroundInfo(
        text: String,
        indeterminate: Boolean,
        progress: Int = 0,
        maxProgress: Int = 0,
    ): ForegroundInfo {
        ensureChannel()
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Data Import")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setProgress(maxProgress, progress, indeterminate)
            .build()
        return ForegroundInfo(NOTIF_ID_PROGRESS, notification)
    }

    private fun notifyCompletion(title: String, text: String, isError: Boolean) {
        ensureChannel()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(if (isError) android.R.drawable.stat_notify_error else android.R.drawable.stat_sys_upload_done)
            .setAutoCancel(true)
            .build()
        nm.cancel(NOTIF_ID_PROGRESS)
        nm.notify(NOTIF_ID_DONE, notification)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Import Progress",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "Shown while a data import is running in the background."
                    },
                )
            }
        }
    }

    companion object {
        private const val TAG = "ImportPollingWorker"
        private const val CHANNEL_ID = "IMPORT_PROGRESS"
        private const val NOTIF_ID_PROGRESS = 9010
        private const val NOTIF_ID_DONE = 9011

        const val KEY_SOURCE = "import_source"

        private const val POLL_INTERVAL_MS = 5_000L
        private const val MAX_CONSECUTIVE_ERRORS = 5

        /**
         * Enqueue the poller for the given source.
         * [ExistingWorkPolicy.REPLACE] cancels any stale poller from a previous session.
         */
        fun enqueue(context: Context, sourceName: String) {
            val request = OneTimeWorkRequestBuilder<ImportPollingWorker>()
                .setInputData(workDataOf(KEY_SOURCE to sourceName))
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "import_polling_$sourceName",
                ExistingWorkPolicy.REPLACE,
                request,
            )
            Log.i(TAG, "ImportPollingWorker enqueued for source=$sourceName")
        }
    }
}
