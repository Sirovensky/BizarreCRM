package com.bizarreelectronics.crm.service

import javax.inject.Inject
import javax.inject.Singleton

/**
 * §73.8 — In-memory ring buffer of the last 100 FCM pushes received on this
 * device. Persisted across FCM deliveries within a single app process lifetime.
 *
 * Not persisted to disk: a reboot / process restart clears the history. This is
 * intentional — the history is a short-lived audit aid, not a durable log. Full
 * audit history lives server-side. The 100-entry cap prevents unbounded memory
 * growth on devices that receive many pushes.
 *
 * Thread safety: all mutations are synchronised on [entries] so concurrent FCM
 * deliveries from the Firebase-managed thread pool do not race.
 *
 * Usage:
 *   Injected into [FcmService] which calls [record] for every non-silent push.
 *   [NotificationSettingsScreen] reads [snapshot] to render the Recent list.
 */
@Singleton
class NotificationHistoryStore @Inject constructor() {

    /** A single received push notification entry. */
    data class Entry(
        /** Epoch-ms when the push was received by [FcmService]. */
        val receivedAtMs: Long,
        /** FCM data payload `type` field (e.g. "ticket_assigned"). */
        val type: String,
        /** Notification title shown to the user, or "Bizarre CRM" if blank. */
        val title: String,
        /** Notification body, or empty string. */
        val body: String,
        /** Channel ID the notification was posted on. */
        val channelId: String,
        /** True if the notification was silenced by quiet hours / DND. */
        val silenced: Boolean,
    )

    private val entries = ArrayDeque<Entry>(CAPACITY + 1)

    /**
     * Record a received push in the ring buffer.
     *
     * If the buffer is already at capacity the oldest entry is dropped.
     * Safe to call from any thread.
     */
    fun record(entry: Entry) {
        synchronized(entries) {
            entries.addFirst(entry)
            if (entries.size > CAPACITY) entries.removeLast()
        }
    }

    /**
     * Return an immutable snapshot of all recorded entries, newest first.
     *
     * Safe to call from any thread; returns a copy so callers can iterate
     * without holding the lock.
     */
    fun snapshot(): List<Entry> = synchronized(entries) { entries.toList() }

    /** Remove all recorded entries. Called when the user taps "Clear history". */
    fun clear() = synchronized(entries) { entries.clear() }

    companion object {
        /** Maximum number of entries retained in the ring buffer (§73.8). */
        const val CAPACITY = 100
    }
}
