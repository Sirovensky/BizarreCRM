package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Provides stable, collision-free identifiers for entities created while the device is
 * offline. Two concerns are handled separately:
 *
 * 1. **Temporary primary keys** — monotonically decreasing negative Longs. Keeping them in
 *    negative space lets [SyncManager] detect temp rows (`entityId < 0`) and reconcile
 *    them to the server-assigned id once the row is flushed. A per-device counter is used
 *    instead of `-System.currentTimeMillis()` to avoid collisions when two rows are
 *    created inside the same millisecond.
 *
 * 2. **Human-visible offline references** (e.g. a ticket's `orderId`) — a monotonically
 *    increasing positive counter formatted as `OFFLINE-YYYY-MM-DD-NNNN` (date-stamped,
 *    zero-padded to 4 digits). These are displayed in the UI until the server confirms
 *    the real `orderId` via the sync reconciliation step. §20.6 L2137.
 *
 * 3. **Idempotency keys** — random UUIDs passed alongside create requests so the server
 *    can dedupe retried POSTs. Per AP5.
 *
 * All state lives in a dedicated SharedPreferences file so this component can be wiped
 * independently of the rest of the app if the caller ever needs to reset offline state.
 */
@Singleton
class OfflineIdGenerator @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("offline_id_generator", Context.MODE_PRIVATE)

    /**
     * Returns the next temporary primary key for a newly-created offline entity. The
     * value is guaranteed to be negative and strictly less than any previously-issued
     * temp id from this device, so Room `PRIMARY KEY` collisions are impossible even
     * when the user creates many entities in rapid succession.
     */
    @Synchronized
    fun nextTempId(): Long {
        val current = prefs.getLong(KEY_TEMP_ID_COUNTER, INITIAL_TEMP_ID)
        val next = current - 1L
        prefs.edit().putLong(KEY_TEMP_ID_COUNTER, next).apply()
        return next
    }

    /**
     * Returns the next offline reference string for UI display (e.g. an order id on a
     * pending ticket). Format: `OFFLINE-YYYY-MM-DD-NNNN` where NNNN is a zero-padded
     * per-device monotonic counter. §20.6 L2137.
     *
     * Callers are expected to replace this value once sync reconciles to the real
     * server-assigned reference. The date portion is the local date at creation time
     * so the user can quickly identify which day an offline record was created.
     */
    @Synchronized
    fun nextOfflineReference(prefix: String = "OFFLINE"): String {
        val current = prefs.getLong(KEY_OFFLINE_REF_COUNTER, 0L)
        val next = current + 1L
        prefs.edit().putLong(KEY_OFFLINE_REF_COUNTER, next).apply()
        val date = LocalDate.now().format(DATE_FORMATTER)
        return "$prefix-$date-${next.toString().padStart(4, '0')}"
    }

    /**
     * Returns a fresh idempotency key. The server dedupes create requests by this value
     * so retries of the same logical create do not insert duplicate rows (AP5).
     */
    fun newIdempotencyKey(): String = UUID.randomUUID().toString()

    companion object {
        private const val KEY_TEMP_ID_COUNTER = "temp_id_counter"
        private const val KEY_OFFLINE_REF_COUNTER = "offline_ref_counter"

        // Start just below zero so the very first assignment becomes -1. Staying in
        // negative space preserves SyncManager's "entityId < 0 means temp" contract.
        private const val INITIAL_TEMP_ID = 0L

        /** ISO-8601 date formatter for human-readable offline references. */
        private val DATE_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    }
}
