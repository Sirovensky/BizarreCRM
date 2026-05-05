package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.InventoryDao
import com.bizarreelectronics.crm.data.local.db.dao.InvoiceDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncStateEntity
import com.bizarreelectronics.crm.data.remote.api.DeltaTombstone
import com.bizarreelectronics.crm.data.remote.api.DeltaUpsert
import com.bizarreelectronics.crm.data.remote.api.SyncApi
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.data.repository.toEntity
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.google.gson.Gson
import java.time.Instant
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Plan §20.6 L2121-L2124 — Incremental delta-sync engine.
 *
 * ## How it works
 *
 * [sync] reads the last-known server cursor from [SyncStateDao] under key `"delta"`.
 * It then paginates through `GET /sync/delta?since=<ts>&cursor=<opaque>&limit=500`
 * until the server reports exhaustion. For each page:
 *
 *  - **Upserts** are applied to the corresponding Room table via entity-specific
 *    repository helpers.
 *  - **Tombstones** (deletes) are applied via entity-specific DAO `deleteById`.
 *
 * After all pages are consumed the [SyncStateEntity] for key `"delta"` is updated
 * with the new `last_updated_at` so the next run only fetches changes since now.
 *
 * ## Full-sync fallback
 *
 * A full-sync is triggered in two cases:
 *  1. The stored cursor is missing (first run, post-logout, etc.).
 *  2. The gap between `last_updated_at` and now exceeds [MAX_DELTA_GAP_DAYS].
 *     In this case the cursor is discarded and the full entity refreshes are
 *     delegated back to [SyncManager.syncAll].
 *
 * ## Scheduling
 *
 * [sync] is called from:
 *  - [SyncWorker] on every 15-min periodic tick (background).
 *  - The caller's 2-min foreground ticker (when the app is in the foreground).
 *  - WebSocket `delta:invalidate` nudge handler (on-demand).
 */
@Singleton
class DeltaSyncer @Inject constructor(
    private val syncApi: SyncApi,
    private val syncStateDao: SyncStateDao,
    private val ticketDao: TicketDao,
    private val customerDao: CustomerDao,
    private val inventoryDao: InventoryDao,
    private val invoiceDao: InvoiceDao,
    private val ticketRepository: TicketRepository,
    private val customerRepository: CustomerRepository,
    private val inventoryRepository: InventoryRepository,
    private val invoiceRepository: InvoiceRepository,
    private val networkMonitor: NetworkMonitor,
    private val gson: Gson,
) {

    /**
     * Run one full delta-sync pass.
     *
     * Returns [DeltaSyncResult.FullSyncRequired] when the gap is too wide or the
     * cursor is missing; returns [DeltaSyncResult.Ok] with the count of applied
     * changes on success.
     */
    suspend fun sync(): DeltaSyncResult {
        if (!networkMonitor.isCurrentlyOnline()) {
            Log.d(TAG, "Offline — skipping delta sync")
            return DeltaSyncResult.Skipped
        }

        val state = syncStateDao.get(ENTITY_KEY)
        val now = System.currentTimeMillis()

        // Determine if a full-sync fallback is needed.
        if (state == null || state.cursor == null) {
            Log.d(TAG, "No cursor stored — full-sync required")
            return DeltaSyncResult.FullSyncRequired("no cursor")
        }
        val gapDays = ChronoUnit.DAYS.between(
            Instant.ofEpochMilli(state.lastUpdatedAt),
            Instant.ofEpochMilli(now),
        )
        if (gapDays > MAX_DELTA_GAP_DAYS) {
            Log.w(TAG, "Delta gap $gapDays days exceeds max $MAX_DELTA_GAP_DAYS — full-sync required")
            // Discard stale cursor so next run starts fresh.
            syncStateDao.upsert(state.copy(cursor = null, serverExhaustedAt = null))
            return DeltaSyncResult.FullSyncRequired("gap=${gapDays}d")
        }

        val since = Instant.ofEpochMilli(state.lastUpdatedAt).toString()
        var cursor: String? = state.cursor
        var upsertCount = 0
        var tombstoneCount = 0

        try {
            var lastSince = since
            while (true) {
                val response = syncApi.getDelta(since = lastSince, cursor = cursor, limit = PAGE_SIZE)
                val page = response.data ?: break

                for (upsert in page.upserts) {
                    applyUpsert(upsert)
                    upsertCount++
                }
                for (tombstone in page.tombstones) {
                    applyTombstone(tombstone)
                    tombstoneCount++
                }

                // Advance cursor.
                cursor = page.cursor
                if (page.since != null) lastSince = page.since

                if (page.serverExhausted || cursor == null) break
            }

            // Persist new cursor + updated timestamp.
            val updated = (state).copy(
                cursor = cursor ?: state.cursor,
                lastUpdatedAt = now,
                serverExhaustedAt = if (cursor == null) now else null,
            )
            syncStateDao.upsert(updated)

            Log.d(TAG, "Delta sync complete: $upsertCount upserts, $tombstoneCount tombstones")
            return DeltaSyncResult.Ok(upsertCount + tombstoneCount)
        } catch (e: Exception) {
            Log.e(TAG, "Delta sync failed [${e.javaClass.simpleName}]: ${e.message}")
            throw e
        }
    }

    /**
     * Seed a fresh cursor after a full sync completes. Called by [SyncManager]
     * so subsequent runs use delta mode instead of full-page refresh.
     */
    suspend fun seedCursorAfterFullSync() {
        val now = System.currentTimeMillis()
        val existing = syncStateDao.get(ENTITY_KEY)
        syncStateDao.upsert(
            SyncStateEntity(
                entity = ENTITY_KEY,
                cursor = existing?.cursor ?: INITIAL_CURSOR_SENTINEL,
                lastUpdatedAt = now,
            )
        )
        Log.d(TAG, "Delta cursor seeded after full sync")
    }

    // ── entity-specific apply helpers ─────────────────────────────────────────

    private suspend fun applyUpsert(upsert: DeltaUpsert) {
        try {
            when (upsert.entityType) {
                "ticket" -> {
                    val dto = gson.fromJson(upsert.payload, com.bizarreelectronics.crm.data.remote.dto.TicketDetail::class.java)
                    ticketDao.upsert(dto.toEntity())
                }
                "customer" -> {
                    val dto = gson.fromJson(upsert.payload, com.bizarreelectronics.crm.data.remote.dto.CustomerDetail::class.java)
                    customerDao.upsert(dto.toEntity())
                }
                "inventory" -> {
                    val dto = gson.fromJson(upsert.payload, com.bizarreelectronics.crm.data.remote.dto.InventoryDetail::class.java)
                    inventoryDao.upsert(dto.toEntity())
                }
                "invoice" -> {
                    // Delta upserts for invoices arrive as InvoiceListItem payloads.
                    // InvoiceDetail.toEntity() is not yet available in the repository;
                    // InvoiceListItem.toEntity() is the canonical path (InvoiceRepository.kt L147).
                    val dto = gson.fromJson(upsert.payload, com.bizarreelectronics.crm.data.remote.dto.InvoiceListItem::class.java)
                    invoiceDao.upsert(dto.toEntity())
                }
                else -> Log.w(TAG, "Unknown entity type in delta upsert: '${upsert.entityType}' id=${upsert.id}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply delta upsert ${upsert.entityType}#${upsert.id}: ${e.message}")
            // Continue — one bad row must not abort the rest of the page.
        }
    }

    private suspend fun applyTombstone(tombstone: DeltaTombstone) {
        try {
            when (tombstone.entityType) {
                "ticket"    -> ticketDao.deleteById(tombstone.id)
                "customer"  -> customerDao.deleteById(tombstone.id)
                "inventory" -> inventoryDao.deleteById(tombstone.id)
                // NOTE: InvoiceDao.deleteById not yet present — invoice tombstones are
                // deferred until that method is added. Soft-deleted invoices are already
                // filtered out on the list endpoint; this path would only be needed for
                // hard deletes which the server does not currently emit.
                "invoice"   -> Log.d(TAG, "Invoice tombstone id=${tombstone.id} skipped — deleteById not yet on InvoiceDao")
                else -> Log.w(TAG, "Unknown entity type in tombstone: '${tombstone.entityType}' id=${tombstone.id}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply tombstone ${tombstone.entityType}#${tombstone.id}: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "DeltaSyncer"

        /** SyncState entity key used as the PK for the delta cursor row. */
        const val ENTITY_KEY = "delta"

        /** Items per delta page. Server-side cap is also 500. */
        private const val PAGE_SIZE = 500

        /**
         * If the stored `last_updated_at` is older than this many days, discard
         * the cursor and fall back to a full sync. Prevents accumulating a huge
         * backlog of changes that would overwhelm memory.
         */
        private const val MAX_DELTA_GAP_DAYS = 7L

        /**
         * Sentinel value stored when seeding after a full sync. The server interprets
         * this as "start from now" and returns an empty delta page, which is correct:
         * the full sync already fetched everything.
         */
        private const val INITIAL_CURSOR_SENTINEL = "fresh"
    }
}

/** Result of a [DeltaSyncer.sync] call. */
sealed class DeltaSyncResult {
    /** Delta sync ran and applied [changeCount] changes. */
    data class Ok(val changeCount: Int) : DeltaSyncResult()

    /** Device was offline — sync was not attempted. */
    data object Skipped : DeltaSyncResult()

    /** Gap too wide or no cursor — caller should run a full sync instead. */
    data class FullSyncRequired(val reason: String) : DeltaSyncResult()
}
