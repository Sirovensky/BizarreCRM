package com.bizarreelectronics.crm.util

/**
 * LocaleAwareFormatters — §27.3
 *
 * Locale-aware formatting for dates, times, numbers, currency, and first-day-of-week.
 * All functions derive the active locale from [java.util.Locale.getDefault] (which
 * reflects the per-app language chosen via [LanguageManager] / [LocaleManager]).
 *
 * Timezone and currency overrides stored in [AppPreferences] are respected:
 *   - [appTimezone] → reads [AppPreferences.timezoneOverride], falls back to [ZoneId.systemDefault].
 *   - [currencyFormatter] → reads [AppPreferences.currencyOverride], falls back to locale default.
 *
 * These are object-level helpers (no DI required) so they can be called from anywhere
 * (composables, ViewModels, utility functions).  Callers that need the AppPreferences
 * values must pass them in explicitly — this keeps the object testable without Hilt.
 *
 * Usage:
 * ```kotlin
 * // Date (respects active locale + timezone override)
 * val label = LocaleAwareFormatters.formatDate(epochMs, appPreferences.timezoneOverride)
 *
 * // Currency (respects active locale + currency override)
 * val price = LocaleAwareFormatters.formatCurrency(amountCents, appPreferences.currencyOverride)
 *
 * // Number
 * val qty = LocaleAwareFormatters.formatNumber(42)
 *
 * // First day of week
 * val firstDay = LocaleAwareFormatters.firstDayOfWeek()
 * ```
 */

import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Calendar
import java.util.Currency
import java.util.Locale

object LocaleAwareFormatters {

    // ------------------------------------------------------------------
    // Timezone
    // ------------------------------------------------------------------

    /**
     * Returns the effective [ZoneId] to use for display.
     *
     * Precedence:
     *   1. [zoneIdOverride] if non-null and parseable (e.g. "America/New_York")
     *   2. [ZoneId.systemDefault] — device timezone
     *
     * The override string comes from [AppPreferences.timezoneOverride].
     */
    fun effectiveZoneId(zoneIdOverride: String?): ZoneId {
        if (!zoneIdOverride.isNullOrBlank()) {
            runCatching { return ZoneId.of(zoneIdOverride) }
        }
        return ZoneId.systemDefault()
    }

    // ------------------------------------------------------------------
    // Date / time formatting  (§27.3)
    // ------------------------------------------------------------------

    /**
     * Format [epochMs] as a medium-length date in the active locale with the
     * effective timezone.
     *
     * e.g. "Apr 16, 2026" (en-US), "16 abr 2026" (es-MX), "16 avr. 2026" (fr-CA)
     *
     * @param epochMs            Epoch milliseconds.
     * @param timezoneOverride   From [AppPreferences.timezoneOverride]; null = device default.
     */
    fun formatDate(epochMs: Long, timezoneOverride: String? = null): String {
        if (epochMs <= 0L) return ""
        val zone = effectiveZoneId(timezoneOverride)
        val locale = Locale.getDefault()
        val formatter = DateTimeFormatter
            .ofLocalizedDate(FormatStyle.MEDIUM)
            .withLocale(locale)
            .withZone(zone)
        return formatter.format(Instant.ofEpochMilli(epochMs))
    }

    /**
     * Format [epochMs] as a short date+time in the active locale.
     *
     * e.g. "Apr 16, 2026, 9:17 PM" (en-US)
     *
     * @param epochMs            Epoch milliseconds.
     * @param timezoneOverride   From [AppPreferences.timezoneOverride]; null = device default.
     */
    fun formatDateTime(epochMs: Long, timezoneOverride: String? = null): String {
        if (epochMs <= 0L) return ""
        val zone = effectiveZoneId(timezoneOverride)
        val locale = Locale.getDefault()
        val formatter = DateTimeFormatter
            .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(locale)
            .withZone(zone)
        return formatter.format(Instant.ofEpochMilli(epochMs))
    }

    /**
     * Format [epochMs] as a time-only string in the active locale.
     *
     * e.g. "9:17 PM" (en-US), "21:17" (fr)
     *
     * @param epochMs            Epoch milliseconds.
     * @param timezoneOverride   From [AppPreferences.timezoneOverride]; null = device default.
     */
    fun formatTime(epochMs: Long, timezoneOverride: String? = null): String {
        if (epochMs <= 0L) return ""
        val zone = effectiveZoneId(timezoneOverride)
        val locale = Locale.getDefault()
        val formatter = DateTimeFormatter
            .ofLocalizedTime(FormatStyle.SHORT)
            .withLocale(locale)
            .withZone(zone)
        return formatter.format(Instant.ofEpochMilli(epochMs))
    }

    // ------------------------------------------------------------------
    // Number formatting  (§27.3)
    // ------------------------------------------------------------------

    /**
     * Format an integer [value] using the active locale's grouping separators.
     *
     * e.g. 1234567 → "1,234,567" (en-US), "1 234 567" (fr)
     */
    fun formatNumber(value: Long): String =
        NumberFormat.getNumberInstance(Locale.getDefault()).format(value)

    /**
     * Format a decimal [value] using the active locale.
     *
     * e.g. 3.14 → "3.14" (en-US), "3,14" (de)
     */
    fun formatDecimal(value: Double, minFractionDigits: Int = 2, maxFractionDigits: Int = 2): String {
        val fmt = NumberFormat.getNumberInstance(Locale.getDefault())
        fmt.minimumFractionDigits = minFractionDigits
        fmt.maximumFractionDigits = maxFractionDigits
        return fmt.format(value)
    }

    // ------------------------------------------------------------------
    // Currency formatting  (§27.3)
    // ------------------------------------------------------------------

    /**
     * Format [amountCents] (Long cents) as a currency string in the active locale.
     *
     * Precedence for the currency symbol:
     *   1. [currencyCodeOverride] if non-null and a valid ISO-4217 code.
     *   2. The currency associated with the active locale.
     *
     * e.g. 1234 cents:
     *   en-US, no override → "$12.34"
     *   es-MX, no override → "$12.34" (MXN sign)
     *   en-US, override="EUR" → "€12.34"
     *
     * @param amountCents        Integer cents (100 = $1.00).
     * @param currencyCodeOverride From [AppPreferences.currencyOverride]; null = locale default.
     */
    fun formatCurrency(amountCents: Long, currencyCodeOverride: String? = null): String {
        val locale = Locale.getDefault()
        val fmt = NumberFormat.getCurrencyInstance(locale)
        if (!currencyCodeOverride.isNullOrBlank()) {
            runCatching {
                fmt.currency = Currency.getInstance(currencyCodeOverride)
            }
        }
        return fmt.format(amountCents / 100.0)
    }

    /**
     * Convenience overload for Double dollars.
     *
     * Prefer the Long-cents overload ([formatCurrency(Long, String?)]) in new
     * code to avoid IEEE-754 drift.
     */
    fun formatCurrencyDollars(amount: Double, currencyCodeOverride: String? = null): String =
        formatCurrency((amount * 100).toLong(), currencyCodeOverride)

    // ------------------------------------------------------------------
    // First day of week  (§27.3)
    // ------------------------------------------------------------------

    /**
     * Returns the first day of the week for the active locale as a [DayOfWeek].
     *
     * e.g. en-US → SUNDAY, fr-FR → MONDAY, en-GB → MONDAY
     *
     * Uses the JDK [Calendar] API which is locale-aware.  The result should be
     * used by any calendar / week-view component to set its column headers.
     */
    fun firstDayOfWeek(): DayOfWeek {
        val cal = Calendar.getInstance(Locale.getDefault())
        // Calendar.SUNDAY=1 … Calendar.SATURDAY=7
        // DayOfWeek.MONDAY=1 … DayOfWeek.SUNDAY=7  (ISO-8601)
        val calDay = cal.firstDayOfWeek
        // Convert: Calendar 1=SUN,2=MON,…7=SAT → ISO SUNDAY=7,MON=1,…SAT=6
        return when (calDay) {
            Calendar.MONDAY    -> DayOfWeek.MONDAY
            Calendar.TUESDAY   -> DayOfWeek.TUESDAY
            Calendar.WEDNESDAY -> DayOfWeek.WEDNESDAY
            Calendar.THURSDAY  -> DayOfWeek.THURSDAY
            Calendar.FRIDAY    -> DayOfWeek.FRIDAY
            Calendar.SATURDAY  -> DayOfWeek.SATURDAY
            else               -> DayOfWeek.SUNDAY  // Calendar.SUNDAY (default)
        }
    }

    /**
     * Returns the display name for [dayOfWeek] in the active locale.
     *
     * e.g. DayOfWeek.MONDAY → "Monday" (en), "lunes" (es), "lundi" (fr)
     *
     * [style] defaults to FULL; pass [TextStyle.SHORT] for abbreviated headers.
     */
    fun dayOfWeekDisplayName(dayOfWeek: DayOfWeek, style: TextStyle = TextStyle.FULL): String =
        dayOfWeek.getDisplayName(style, Locale.getDefault())
}
