package com.bizarreelectronics.crm.util

import android.text.format.DateUtils
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.time.temporal.WeekFields
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
 *
 * §27.3 — Timezone and locale awareness:
 *   - [effectiveZoneId] respects [timezoneOverride] (from AppPreferences) so
 *     dates/times are rendered in the user's chosen zone, not necessarily the
 *     device zone.
 *   - [firstDayOfWeek] returns the locale-appropriate first day of the week so
 *     calendar views (week/month) align correctly for each locale.
 *   - [formatAbsolute] uses a locale-aware pattern via [FormatStyle.LONG] when
 *     [useLocaleFormatStyle] is true (default). Raw "LLLL d, yyyy" is kept for
 *     legacy string callers.
 */
object DateFormatter {
    private val isoParser = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val isoParserT = DateTimeFormatter.ISO_LOCAL_DATE_TIME // handles "2026-04-04T17:30:00"

    /**
     * Optional timezone override (ZoneId string, e.g. "America/New_York").
     * Null means use [ZoneId.systemDefault()].
     * Set from [AppPreferences.timezoneOverride] at app start.
     */
    @Volatile
    var timezoneOverride: String? = null

    /**
     * The effective ZoneId for all date/time formatting.
     * Respects [timezoneOverride] if set; falls back to [ZoneId.systemDefault()].
     */
    val effectiveZoneId: ZoneId
        get() = timezoneOverride
            ?.let { runCatching { ZoneId.of(it) }.getOrNull() }
            ?: ZoneId.systemDefault()

    /**
     * Returns the locale-appropriate first day of the week (§27.3).
     * Uses [WeekFields.of(Locale.getDefault())] so Sunday-first (en-US),
     * Monday-first (fr-CA, es-MX), etc. are all handled automatically.
     *
     * Calendar views should prefer this over hardcoded [DayOfWeek.SUNDAY].
     */
    val firstDayOfWeek: DayOfWeek
        get() = WeekFields.of(Locale.getDefault()).firstDayOfWeek

    // CROSS46 canonical formats.
    private val absoluteFormat: DateTimeFormatter
        get() = DateTimeFormatter.ofPattern("LLLL d, yyyy", Locale.getDefault())

    // Locale-aware medium date format (e.g. "Apr 16, 2026" in en-US, "16 avr. 2026" in fr-CA).
    private val localizedDateFormat: DateTimeFormatter
        get() = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault())

    // Locale-aware time format (12h for en-US/es, 24h for fr-CA, etc.).
    private val localizedTimeFormat: DateTimeFormatter
        get() = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault())

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
     * Locale-aware medium date — "Apr 16, 2026" (en-US), "16 avr. 2026" (fr-CA), etc.
     * Uses [FormatStyle.MEDIUM] with the active locale and [effectiveZoneId].
     *
     * §27.3: Prefer this over [formatAbsolute] for new call sites where the
     * locale-appropriate month abbreviation is acceptable.
     */
    fun formatLocalized(timestampMs: Long): String {
        if (timestampMs <= 0L) return ""
        return Instant.ofEpochMilli(timestampMs)
            .atZone(effectiveZoneId)
            .toLocalDateTime()
            .format(localizedDateFormat)
    }

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
            .atZone(effectiveZoneId) // §27.3: respects timezoneOverride
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
            .atZone(effectiveZoneId) // §27.3: respects timezoneOverride
            .toLocalDateTime()
            .format(localizedTimeFormat) // §27.3: locale-aware 12h/24h
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
