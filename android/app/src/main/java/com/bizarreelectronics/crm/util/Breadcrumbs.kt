package com.bizarreelectronics.crm.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentLinkedDeque
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §32.5 — in-memory breadcrumb ring buffer. Crash reports dump the last
 * N entries so the recovered log shows what the user was doing in the
 * 30 seconds before the throwable.
 *
 * Stays local to the process (no persistence, no network) — sovereignty
 * principle from §32.7. CrashReporter reads via [recent] inside the
 * uncaught-exception handler.
 *
 * Categories are free-form strings ("nav", "tap", "sync", "ws") so
 * caller code doesn't have to add an enum every time a new touch point
 * needs tracking.
 */
@Singleton
class Breadcrumbs @Inject constructor() {

    private data class Entry(val ts: Long, val category: String, val message: String)

    private val ring = ConcurrentLinkedDeque<Entry>()

    fun log(category: String, message: String) {
        if (message.isBlank()) return
        // Trim oldest if we're past the cap. ConcurrentLinkedDeque doesn't
        // have a fixed-size constructor so we cull on add.
        ring.addLast(Entry(System.currentTimeMillis(), category, message))
        while (ring.size > MAX_ENTRIES) {
            ring.pollFirst()
        }
    }

    /** Snapshot of recent breadcrumbs as plain-text lines, oldest first. */
    fun recent(): List<String> {
        val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
        return ring.map { e -> "${fmt.format(Date(e.ts))} [${e.category}] ${e.message}" }
    }

    fun clear() {
        ring.clear()
    }

    companion object {
        const val CAT_NAV = "nav"
        const val CAT_TAP = "tap"
        const val CAT_SYNC = "sync"
        const val CAT_PUSH = "push"
        const val CAT_AUTH = "auth"
        const val CAT_WS = "ws"
        private const val MAX_ENTRIES = 50
    }
}
