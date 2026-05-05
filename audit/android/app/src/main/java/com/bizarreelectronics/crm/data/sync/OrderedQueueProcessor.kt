package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Plan §20.4 L2112 — FIFO + dependency-aware queue processor.
 *
 * ## Ordering guarantees
 *
 * Entries are dispatched in `created_at ASC` order (FIFO) with one constraint:
 * an entry whose `depends_on_queue_id` points to a parent whose `status` is NOT
 * yet `completed` is held back until the parent completes. This allows callers
 * to express causal chains such as:
 *
 *   ticket-create → note-add (depends on ticket-create completing first)
 *
 * ## How to use
 *
 * Call [nextReady] to claim the next dispatchable entry. After dispatch succeeds,
 * mark it `completed` via [SyncQueueDao.updateStatus]. After a retryable failure,
 * call [SyncQueueDao.incrementRetry] + `updateStatus("pending", error)` or
 * `markDeadLetter` if the retry budget is exhausted.
 *
 * [drainAll] runs the full drain loop used by [SyncWorker] and delegates actual
 * dispatch to a caller-supplied [SyncManager.dispatchSyncEntry]-equivalent lambda
 * so the loop logic stays decoupled from entity-level dispatch logic.
 */
@Singleton
class OrderedQueueProcessor @Inject constructor(
    private val syncQueueDao: SyncQueueDao,
) {

    /**
     * Returns the oldest pending entry whose dependency is satisfied (or has no
     * dependency), or `null` when the queue is empty / all remaining entries are
     * blocked on unfinished parents.
     *
     * Delegates directly to [SyncQueueDao.nextReady] which executes the optimised
     * LEFT JOIN query — O(log n) with the composite index.
     */
    suspend fun nextReady(): SyncQueueEntity? = syncQueueDao.nextReady()

    /**
     * Drain the ready subset of the queue, dispatching each entry via [dispatch].
     *
     * Each entry is processed in isolation: a failure on one entry does not abort
     * subsequent entries (R8 isolation pattern from SyncManager). Exponential
     * backoff is handled at the WorkManager scheduling layer; here we only
     * increment the retry counter and update the status so the next tick
     * reconsiders the entry.
     *
     * @param dispatch suspend lambda that performs the actual HTTP call. Should
     *   throw on failure (any Throwable is caught here).
     * @param onEntryCompleted called after each successful dispatch, with the
     *   completed entry. Use to apply server-response upserts to canonical tables.
     */
    suspend fun drainAll(
        dispatch: suspend (SyncQueueEntity) -> Unit,
        onEntryCompleted: suspend (SyncQueueEntity) -> Unit = {},
    ) {
        var processedCount = 0
        while (true) {
            val entry = nextReady() ?: break

            try {
                syncQueueDao.updateStatus(entry.id, "syncing", null)
                dispatch(entry)
                syncQueueDao.updateStatus(entry.id, "completed", null)
                onEntryCompleted(entry)
                processedCount++
            } catch (e: Exception) {
                syncQueueDao.incrementRetry(entry.id)
                val newRetryCount = entry.retries + 1
                if (newRetryCount >= SyncQueueDao.MAX_RETRIES) {
                    Log.w(
                        TAG,
                        "Dead-lettering entry ${entry.id} (${entry.entityType}/${entry.operation}) " +
                            "after $newRetryCount retries [${e.javaClass.simpleName}]: ${e.message}",
                    )
                    syncQueueDao.markDeadLetter(entry.id, e.message)
                } else {
                    Log.d(
                        TAG,
                        "Retrying entry ${entry.id} (${entry.entityType}/${entry.operation}) " +
                            "attempt $newRetryCount/${SyncQueueDao.MAX_RETRIES}: ${e.message}",
                    )
                    syncQueueDao.updateStatus(entry.id, "pending", e.message)
                }
                // Continue draining — other independent entries may still be ready.
            }
        }

        if (processedCount > 0) {
            syncQueueDao.deleteCompleted()
            Log.d(TAG, "drainAll: dispatched $processedCount entries")
        }
    }

    companion object {
        private const val TAG = "OrderedQueueProcessor"
    }
}
