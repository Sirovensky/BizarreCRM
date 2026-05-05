package com.bizarreelectronics.crm.util

import android.util.Log
import timber.log.Timber
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentLinkedDeque
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantLock
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.concurrent.withLock

/**
 * §32.4 — Timber tree for release builds.
 *
 * Behaviour:
 *  - Only Error and Warn lines are recorded (Debug / Info / Verbose are dropped).
 *  - Each line is passed through [LogRedactor] so PII (phone, email, bearer
 *    token, IMEI, card number, SSN) is stripped before any storage.
 *  - An in-memory ring buffer holds the last [MAX_ENTRIES] entries; this is
 *    the data source for Settings → Diagnostics → View logs.
 *  - The ring is flushed to [logDir]/<date>.log on demand via [flushToDisk] so
 *    that the Settings share-logs button can hand the file to a share sheet.
 *  - A separate disk rotation ensures no more than [MAX_LOG_FILES] daily files
 *    are kept.
 *
 * Sovereignty: this tree never POSTs anywhere. Log data leaves the device only
 * when the user explicitly taps "Share logs" (see Settings → Diagnostics).
 *
 * Thread-safety: the ring buffer is a [ConcurrentLinkedDeque] guarded by an
 * [AtomicInteger] size counter. [flushToDisk] acquires [flushLock] to prevent
 * concurrent file writes. Both are safe to call from any thread.
 */
@Singleton
class ReleaseTree @Inject constructor() : Timber.Tree() {

    data class LogEntry(
        val timestamp: Long,
        val priority: Int,
        val tag: String?,
        val message: String,
    ) {
        fun format(): String {
            val ts = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date(timestamp))
            val level = when (priority) {
                Log.ERROR -> "E"
                Log.WARN  -> "W"
                else      -> "?"
            }
            val tagPart = if (tag.isNullOrBlank()) "" else "/$tag"
            return "$ts $level$tagPart: $message"
        }
    }

    // ------------------------------------------------------------------
    // In-memory ring buffer (§32.4: "last 500 entries")
    // ------------------------------------------------------------------

    private val ring = ConcurrentLinkedDeque<LogEntry>()
    private val size = AtomicInteger(0)

    // ------------------------------------------------------------------
    // Timber.Tree contract
    // ------------------------------------------------------------------

    override fun isLoggable(tag: String?, priority: Int): Boolean =
        priority >= Log.WARN           // Error + Warn only

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        if (!isLoggable(tag, priority)) return

        // Assemble message + optional exception summary, then redact.
        val raw = if (t != null) {
            val sw = StringWriter()
            t.printStackTrace(PrintWriter(sw))
            "$message\n${sw.toString().take(MAX_STACKTRACE_CHARS)}"
        } else {
            message
        }
        val safe = LogRedactor.redact(raw)

        val entry = LogEntry(
            timestamp = System.currentTimeMillis(),
            priority  = priority,
            tag       = tag,
            message   = safe,
        )
        ring.addLast(entry)
        val current = size.incrementAndGet()
        if (current > MAX_ENTRIES) {
            ring.pollFirst()
            size.decrementAndGet()
        }
    }

    // ------------------------------------------------------------------
    // Snapshot / disk flush (called by Settings → Diagnostics)
    // ------------------------------------------------------------------

    /**
     * Returns a snapshot of the in-memory ring, oldest entry first.
     * Safe to call from any thread.
     */
    fun snapshot(): List<LogEntry> = ring.toList()

    /**
     * Writes the current ring buffer to [dir]/release-<date>.log, rotating
     * old files if more than [MAX_LOG_FILES] exist.
     *
     * Returns the [File] written, or null if there was nothing to write or the
     * directory could not be created.
     */
    fun flushToDisk(dir: File): File? = flushLock.withLock {
        val entries = snapshot()
        if (entries.isEmpty()) return null

        dir.mkdirs()
        if (!dir.isDirectory) return null

        val date = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        val file = File(dir, "release-$date.log")
        // Append to today's file so multiple flush calls in the same day accumulate.
        file.appendText(entries.joinToString("\n") { it.format() } + "\n")

        // Rotate: keep newest MAX_LOG_FILES daily files.
        dir.listFiles()
            ?.sortedByDescending { it.lastModified() }
            ?.drop(MAX_LOG_FILES)
            ?.forEach { runCatching { it.delete() } }

        file
    }

    private val flushLock = ReentrantLock()

    companion object {
        const val MAX_ENTRIES = 500
        private const val MAX_LOG_FILES = 7
        private const val MAX_STACKTRACE_CHARS = 2_000
        const val LOG_DIR_NAME = "diagnostics-logs"
    }
}
