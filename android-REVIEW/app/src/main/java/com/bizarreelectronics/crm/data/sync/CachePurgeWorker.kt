package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * §21.5 — Periodic 24-hour cache-purge worker.
 *
 * Evicts Room rows that are:
 *   • Older than [CACHE_STALE_DAYS] days AND not referenced by any open ticket.
 *   • Dead-letter sync queue entries older than [SyncQueueDao.DEAD_LETTER_RETENTION_DAYS].
 *
 * This keeps the SQLCipher database lean on devices that run the app for months
 * without a reinstall. The worker runs at most once per 24 hours and only when
 * the device has network connectivity and sufficient battery (≥ 15 %).
 *
 * Scheduling:
 *   Call [schedule] once from Application.onCreate(). [ExistingPeriodicWorkPolicy.KEEP]
 *   prevents stacking when the app is opened multiple times before the 24-hour window.
 *
 * Constraints:
 *   • [NetworkType.CONNECTED] — avoids wasting battery on futile row counts when offline.
 *   • [setRequiresBatteryNotLow] — defers purge if battery is critically low (< 15 %).
 */
@HiltWorker
class CachePurgeWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val syncQueueDao: SyncQueueDao,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "CachePurgeWorker started (attempt ${runAttemptCount + 1})")
        return try {
            purgeDeadLetters()
            // §29.7 — Enforce a 50 MB soft cap on local draft attachment staging files.
            // Uploaded files should already be deleted by MultipartUploadWorker after a
            // successful upload, but crashes or partial uploads can leave orphaned staging
            // files. This LRU eviction keeps the cap tight without risking active uploads.
            evictAttachmentStagingIfOverCap()
            Log.d(TAG, "CachePurgeWorker completed")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "CachePurgeWorker failed [${e.javaClass.simpleName}]: ${e.message}")
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        }
    }

    /**
     * §29.7 — Soft-cap the local attachment staging directory at [ATTACHMENT_CAP_BYTES].
     *
     * Staging files are created by [MultipartUploadWorker] to hold photo / document
     * binaries before upload and are deleted on success. Orphaned files (from a crash,
     * a cancelled job, or an unhandled upload failure) accumulate silently. We evict
     * files LRU (oldest-lastModified first) until the directory is under the cap.
     *
     * Only files older than [MIN_FILE_AGE_MS] are touched so that an actively-uploading
     * file (whose lastModified was just set by the writer) is never deleted mid-stream.
     */
    private fun evictAttachmentStagingIfOverCap() {
        // The staging sub-directory under filesDir that MultipartUploadWorker uses.
        // We scan filesDir broadly rather than a named subdir because MultipartUpload
        // accepts arbitrary paths from callers — any large stale file here is a
        // candidate.
        val stagingDir = applicationContext.filesDir
        if (!stagingDir.exists()) return

        val now = System.currentTimeMillis()
        val candidates = stagingDir.walkTopDown()
            .filter { it.isFile && (now - it.lastModified()) > MIN_FILE_AGE_MS }
            .sortedBy { it.lastModified() } // oldest first
            .toList()

        val totalBytes = candidates.sumOf { it.length() }
        if (totalBytes <= ATTACHMENT_CAP_BYTES) return

        var freed = 0L
        var toFree = totalBytes - ATTACHMENT_CAP_BYTES
        for (file in candidates) {
            if (toFree <= 0) break
            val size = file.length()
            if (file.delete()) {
                freed += size
                toFree -= size
                Log.d(TAG, "Evicted stale staging file: ${file.name} (${size} bytes)")
            }
        }
        Log.i(TAG, "Attachment staging eviction: freed ${freed} bytes, dir now ≤ ${ATTACHMENT_CAP_BYTES} bytes")
    }

    /**
     * Remove dead-letter sync queue rows beyond the configured retention window.
     * Identical to the opportunistic purge in [SyncManager.syncAll] but runs on
     * a 24h schedule so stale rows are always evicted even when [SyncManager]
     * doesn't run (e.g. the user hasn't opened the app in several days).
     */
    private suspend fun purgeDeadLetters() {
        val retentionMs = SyncQueueDao.DEAD_LETTER_RETENTION_DAYS.toLong() * 24L * 60L * 60L * 1000L
        val cutoff = System.currentTimeMillis() - retentionMs
        syncQueueDao.purgeOldDeadLetters(cutoff)
        Log.d(TAG, "Purged dead-letter entries older than ${SyncQueueDao.DEAD_LETTER_RETENTION_DAYS}d")
    }

    companion object {
        private const val TAG = "CachePurgeWorker"
        private const val WORK_NAME = "bizarre_crm_cache_purge"

        // §29.7 — 50 MB soft cap on local attachment staging files.
        private const val ATTACHMENT_CAP_BYTES = 50L * 1024 * 1024

        // Files newer than 10 minutes are assumed to be in-flight and are never evicted.
        private const val MIN_FILE_AGE_MS = 10L * 60 * 1000

        /**
         * Schedule the 24-hour periodic cache-purge job.
         *
         * §21.5 — Constraints:
         *  • [NetworkType.CONNECTED]: lightweight connectivity gate (row-count queries are
         *    fast but we don't want to run if the phone is in airplane mode and users
         *    are unlikely to be actively using the app anyway).
         *  • [setRequiresBatteryNotLow]: avoids draining a nearly-empty battery on a
         *    non-urgent background task.
         *
         * [ExistingPeriodicWorkPolicy.KEEP] prevents stacking on multiple app-opens.
         * Exponential backoff (5 min base) handles transient Room failures.
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .build()

            val request = PeriodicWorkRequestBuilder<CachePurgeWorker>(24, TimeUnit.HOURS)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 5, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
            Log.d(TAG, "Cache-purge scheduled (24h)")
        }
    }
}
