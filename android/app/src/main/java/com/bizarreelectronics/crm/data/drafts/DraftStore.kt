package com.bizarreelectronics.crm.data.drafts

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §1.7 line 239 — transient form-draft store.
 *
 * Responsible for persisting in-progress form data (ticket creation, customer
 * editing, invoice drafts) so a background kill or OEM task-manager eviction
 * does not silently discard unsaved user work.
 *
 * ## Design intent
 * This store is intentionally write-through by default: callers write through to
 * DataStore / Room on every field change so there is normally nothing to flush.
 * [flushPending] exists as a backstop for any call-site that buffers writes for
 * performance reasons. When the store is fully write-through, [flushPending] is a
 * documented no-op.
 *
 * ## OEM-kill invariant (plan §1.6 line 240)
 * OEM task-killers can destroy the process without calling onDestroy. [flushPending]
 * is called from the ProcessLifecycleOwner ON_STOP observer in BizarreCrmApp —
 * the last reliable lifecycle signal before the process may be killed.
 *
 * ## Current state
 * No buffered-write subsystem exists yet. [flushPending] is a documented no-op
 * pending the full draft subsystem (plan §1.6 lines 260-266). The method is wired
 * now so the call-site in BizarreCrmApp does not need to change when buffering is
 * introduced.
 */
@Singleton
class DraftStore @Inject constructor() {

    /**
     * Flushes any pending (buffered) draft writes to their backing store.
     *
     * When the store is fully write-through (current state), this is a no-op.
     * When buffering is introduced, this method must commit any in-memory
     * pending writes inside a transaction on [Dispatchers.IO].
     *
     * Idempotent — safe to call multiple times with no side effects when there is
     * nothing pending.
     */
    suspend fun flushPending() {
        withContext(Dispatchers.IO) {
            // No buffered-write subsystem yet — this is intentionally a no-op.
            // When buffering is introduced:
            //   db.beginTransaction()
            //   try { flush pending writes; db.setTransactionSuccessful() }
            //   finally { db.endTransaction() }
            Timber.v("DraftStore.flushPending: no pending writes (write-through store)")
        }
    }
}
