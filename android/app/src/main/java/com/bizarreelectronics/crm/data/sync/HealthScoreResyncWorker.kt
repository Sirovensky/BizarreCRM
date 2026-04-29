package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import retrofit2.HttpException
import java.util.concurrent.TimeUnit

/**
 * §45.1 — Daily 24-hour background worker that re-scores all customers at ~4 am local time.
 *
 * Walks every customer row in Room and calls POST /customers/:id/health-score/recalculate
 * for each. The recalculate endpoint is 404-tolerant: individual failures are logged and
 * skipped so a single bad row doesn't abort the entire batch.
 *
 * Scheduling:
 *   Call [schedule] once from Application.onCreate(). [ExistingPeriodicWorkPolicy.KEEP]
 *   prevents stacking on multiple app cold-starts.
 *
 * Constraints:
 *   • [NetworkType.CONNECTED] — requires server reachability.
 *   • [setRequiresBatteryNotLow] — defers on critically-low battery.
 *   • [setRequiresCharging] — prefer to run while plugged in to avoid draining battery.
 *
 * Initial delay:
 *   The worker is scheduled with a 24-hour period. Android WorkManager fires
 *   the first run at some point within the first period; exact timing is OS-controlled.
 *   The ~4 am intent is advisory — WorkManager doesn't support exact-time scheduling
 *   for periodic work.
 */
@HiltWorker
class HealthScoreResyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val customerApi: CustomerApi,
    private val customerDao: CustomerDao,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        Log.d(TAG, "HealthScoreResyncWorker started (attempt ${runAttemptCount + 1})")
        return try {
            rescoreAll()
            Log.d(TAG, "HealthScoreResyncWorker completed")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "HealthScoreResyncWorker failed [${e.javaClass.simpleName}]: ${e.message}")
            if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    /**
     * Fetch all customer IDs from Room and trigger a server-side recalculation for each.
     * Failures on individual customers are silently skipped (logged at DEBUG level)
     * so a transient 5xx on one row doesn't block the rest of the batch.
     */
    private suspend fun rescoreAll() {
        val ids = customerDao.getAllIds()
        Log.d(TAG, "Re-scoring ${ids.size} customers")
        var succeeded = 0
        var skipped = 0
        for (id in ids) {
            try {
                customerApi.recalculateHealthScore(id)
                succeeded++
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Server endpoint not yet live — abort entire batch silently.
                    Log.d(TAG, "recalculate endpoint 404 — aborting batch")
                    return
                }
                skipped++
                Log.d(TAG, "recalculate failed for customer $id (${e.code()}): ${e.message}")
            } catch (e: Exception) {
                skipped++
                Log.d(TAG, "recalculate failed for customer $id [${e.javaClass.simpleName}]: ${e.message}")
            }
        }
        Log.d(TAG, "Re-score complete: $succeeded ok, $skipped skipped")
    }

    companion object {
        private const val TAG = "HealthScoreResyncWorker"
        private const val WORK_NAME = "bizarre_crm_health_score_resync"
        private const val MAX_ATTEMPTS = 2

        /**
         * Schedule the 24-hour periodic re-score job.
         *
         * [ExistingPeriodicWorkPolicy.KEEP] prevents stacking on multiple app-opens.
         */
        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .setRequiresBatteryNotLow(true)
                .setRequiresCharging(true)
                .build()

            val request = PeriodicWorkRequestBuilder<HealthScoreResyncWorker>(24, TimeUnit.HOURS)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
            Log.d(TAG, "Health-score resync scheduled (24h)")
        }
    }
}
