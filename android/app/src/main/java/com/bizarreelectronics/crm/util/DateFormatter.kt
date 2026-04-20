package com.bizarreelectronics.crm.util

import android.text.format.DateUtils
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * DateFormatter — single source of truth for every user-facing date render.
 *
 * CROSS46: The app previously had three competing formats — dashboard's
 * "Thursday, April 16" (no year), appointments' "Thursday, Apr 16, 2026"
 * (year included, abbreviated month), and settings' raw "2026-04-16 21:17:57".
 * This object defines exactly two canonical renderings:
 *
 *   - [formatAbsolute] → "April 16, 2026"  (LLLL d, yyyy, locale default)
 *   - [formatRelative] → "2 hours ago" / "just now" / "in 5 min" / "3 days ago"
 *
 * Both functions accept `Long` (epoch-ms) for new call sites. String-based
 * overloads (`formatDate`, `formatDateTime`, `formatRelative(String?)`) are
 * preserved for existing callers that hand in ISO strings from the server.
 */
object DateFormatter {
    private val isoParser = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val isoParserT = DateTimeFormatter.ISO_LOCAL_DATE_TIME // handles "2026-04-04T17:30:00"

    // CROSS46 canonical formats.
    private val absoluteFormat: DateTimeFormatter
        get() = DateTimeFormatter.ofPattern("LLLL d, yyyy", Locale.getDefault())

    // Legacy formats (kept for string-based callers / detail screens).
    private val displayDate = DateTimeFormatter.ofPattern("MMM d, yyyy")
    private val displayDateTime = DateTimeFormatter.ofPattern("MMM d, h:mm a")
    private val displayTime = DateTimeFormatter.ofPattern("h:mm a")

    private fun parseDateTime(iso: String): LocalDateTime {
        // Try space-separated first (server default), then T-separated (ISO standard).
        return try {
            LocalDateTime.parse(iso, isoParser)
        } catch (_: Exception) {
            LocalDateTime.parse(iso.take(19), isoParserT)
        }
    }

    // ---------------------------------------------------------------------
    // CROSS46 — canonical Long (epoch-ms) API. Prefer these for new code.
    // ---------------------------------------------------------------------

    /**
     * Absolute format: "April 16, 2026".
     *
     * Pattern `LLLL d, yyyy` with locale default. Used wherever a specific
     * date must be displayed (dashboard header line, appointment detail,
     * backup timestamp, etc.).
     */
    fun formatAbsolute(timestampMs: Long): String {
        if (timestampMs <= 0L) return ""
        return Instant.ofEpochMilli(timestampMs)
            .atZone(ZoneId.systemDefault())
            .toLocalDateTime()
            .format(absoluteFormat)
    }

    /**
     * Relative format: "just now", "5 minutes ago", "3 days ago", "in 2 hours".
     *
     * Delegates to [DateUtils.getRelativeTimeSpanString] which handles locale,
     * future timestamps, and sensible thresholds (minute / hour / day / etc.).
     */
    fun formatRelative(timestampMs: Long): String {
        if (timestampMs <= 0L) return ""
        return DateUtils.getRelativeTimeSpanString(
            timestampMs,
            System.currentTimeMillis(),
            DateUtils.MINUTE_IN_MILLIS,
            DateUtils.FORMAT_ABBREV_RELATIVE,
        ).toString()
    }

    /**
     * Time-of-day companion to [formatAbsolute] — "9:17 PM".
     *
     * Call together when both date and time must render on separate lines
     * (e.g. Settings "Last backup: April 16, 2026 at 9:17 PM").
     */
    fun formatTimeOfDay(timestampMs: Long): String {
        if (timestampMs <= 0L) return ""
        return Instant.ofEpochMilli(timestampMs)
            .atZone(ZoneId.systemDefault())
            .toLocalDateTime()
            .format(displayTime)
    }

    // ---------------------------------------------------------------------
    // Legacy string (ISO) API — preserved for existing call sites.
    // ---------------------------------------------------------------------

    fun formatDate(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            parseDateTime(iso).format(displayDate)
        } catch (_: Exception) {
            try {
                LocalDate.parse(iso.take(10)).format(displayDate)
            } catch (_: Exception) {
                iso
            }
        }
    }

    fun formatDateTime(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            parseDateTime(iso).format(displayDateTime)
        } catch (_: Exception) {
            iso
        }
    }

    /**
     * Absolute (canonical) renderer for ISO strings. Routes through
     * [formatAbsolute] so string-based callers get the same "April 16, 2026"
     * output as Long-based ones.
     */
    fun formatAbsolute(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            parseDateTime(iso).format(absoluteFormat)
        } catch (_: Exception) {
            try {
                LocalDate.parse(iso.take(10)).format(absoluteFormat)
            } catch (_: Exception) {
                iso
            }
        }
    }

    fun formatRelative(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            val dt = parseDateTime(iso)
            val now = LocalDateTime.now()
            val minutes = ChronoUnit.MINUTES.between(dt, now)
            val hours = ChronoUnit.HOURS.between(dt, now)
            val days = ChronoUnit.DAYS.between(dt, now)

            when {
                minutes < 1 -> "just now"
                minutes < 60 -> "${minutes}m ago"
                hours < 24 -> "${hours}h ago"
                days < 7 -> "${days}d ago"
                else -> dt.format(displayDate)
            }
        } catch (_: Exception) {
            iso
        }
    }
}
