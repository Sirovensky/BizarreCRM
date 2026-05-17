package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.bizarreelectronics.crm.data.repository.SmsRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.CancellationException

/**
 * WorkManager worker that fires a scheduled SMS when the system wakes it up.
 *
 * Used as 404-fallback for POST /sms/send?send_at=<iso>.
 * Input data keys: "to", "message", "trigger_time_ms".
 */
@HiltWorker
class ScheduledSmsWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val smsRepository: SmsRepository,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val to = inputData.getString("to") ?: return Result.failure()
        val message = inputData.getString("message") ?: return Result.failure()
        return try {
            smsRepository.sendMessage(to, message)
            Log.d(TAG, "Scheduled SMS sent to $to")
            Result.success()
        } catch (e: CancellationException) {
            // BUGHUNT-2026-05-17: re-throw cancellation so WorkManager-driven
            // stop doesn't keep retrying — Result.retry() on a cancelled
            // coroutine reschedules a worker the user no longer wants.
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Scheduled SMS failed for $to: ${e.message}")
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "ScheduledSmsWorker"
    }
}
