package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.InventoryDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §20.9 — LRU-style oldest-entity cache eviction.
 *
 * ## Purpose
 *
 * Room is a local cache of server data. Without a cap it grows unbounded —
 * a shop with 10,000 tickets eventually exhausts the device's SQLite budget
 * and causes degraded query performance. [runEviction] trims each entity table
 * to its configured cap by deleting the oldest rows *that are safe to remove*.
 *
 * ## Safety invariant
 *
 * **Never evict a row with a pending or in-progress sync_queue entry.**
 * Evicting a row while a create/update is in-flight would silently lose the
 * user's offline work. The DAO queries enforce this via a LEFT JOIN guard:
 * only rows that have NO matching `pending | syncing` queue entry are deleted.
 * Rows with `locally_modified = 1` are excluded as an extra safety net.
 *
 * ## Caps (§20.9)
 *
 * | Entity     | Cap    | Rationale                                               |
 * |------------|--------|---------------------------------------------------------|
 * | tickets    | 10,000 | Typical shop has < 5k; 10k leaves ample headroom        |
 * | customers  | 20,000 | Customer lists are large; keep more than tickets        |
 * | inventory  |  5,000 | Catalog is bounded; 5k is generous for most shops       |
 *
 * ## When called
 *
 * [runEviction] is called opportunistically by [SyncManager.syncAll] after a
 * full refresh pass so the eviction targets stale data that was just replaced
 * by fresh server rows. It is not called per-write (too frequent) or on a
 * fixed schedule (simpler to piggyback the sync tick).
 *
 * ## Photo / attachment cache
 *
 * Coil disk cache is tuned to 100 MB via [EncryptedCoilCache] (§20.9 item 1).
 * File-level eviction is handled by Coil's own LRU eviction; this class does
 * not touch the image cache. On-device photo blobs (if any) are managed by
 * the camera / attachment pipeline separately.
 */
@Singleton
class CacheEvictor @Inject constructor(
    private val ticketDao: TicketDao,
    private val customerDao: CustomerDao,
    private val inventoryDao: InventoryDao,
) {

    /**
     * Run one eviction pass. Idempotent — if counts are under cap, the DAO
     * DELETE queries target zero rows (LIMIT 0 is a no-op in SQLite).
     *
     * Must be called from a coroutine. Switches to [Dispatchers.IO] internally.
     */
    suspend fun runEviction() = withContext(Dispatchers.IO) {
        evictEntity(
            name = "tickets",
            cap = CAP_TICKETS,
            count = { ticketDao.countAll() },
            evict = { excess -> ticketDao.evictOldest(excess) },
        )
        evictEntity(
            name = "customers",
            cap = CAP_CUSTOMERS,
            count = { customerDao.countAll() },
            evict = { excess -> customerDao.evictOldest(excess) },
        )
        evictEntity(
            name = "inventory",
            cap = CAP_INVENTORY,
            count = { inventoryDao.countAll() },
            evict = { excess -> inventoryDao.evictOldest(excess) },
        )
    }

    private suspend fun evictEntity(
        name: String,
        cap: Int,
        count: suspend () -> Int,
        evict: suspend (excess: Int) -> Unit,
    ) {
        val current = count()
        val excess = current - cap
        if (excess <= 0) {
            Log.v(TAG, "$name: $current rows ≤ cap $cap — no eviction needed")
            return
        }
        Log.d(TAG, "$name: $current rows > cap $cap — evicting $excess oldest safe rows")
        try {
            evict(excess)
            Log.d(TAG, "$name: eviction complete (≤$excess rows removed, pending rows protected)")
        } catch (e: Exception) {
            Log.e(TAG, "$name: eviction failed [${e.javaClass.simpleName}]: ${e.message}")
            // Non-fatal — the cache is slightly over cap. It will be evicted on
            // the next sync pass. Do NOT rethrow: a failed eviction must not
            // abort the rest of the sync pass.
        }
    }

    companion object {
        private const val TAG = "CacheEvictor"

        /**
         * §20.9 — Maximum number of ticket rows kept in Room at once.
         * Oldest-by-updated_at rows beyond this count are eligible for eviction.
         */
        const val CAP_TICKETS = 10_000

        /**
         * §20.9 — Maximum number of customer rows kept in Room at once.
         */
        const val CAP_CUSTOMERS = 20_000

        /**
         * §20.9 — Maximum number of inventory item rows kept in Room at once.
         */
        const val CAP_INVENTORY = 5_000
    }
}
