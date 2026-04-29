package com.bizarreelectronics.crm.util

import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

// CROSS46: DateFormatter extracted to its own file (util/DateFormatter.kt)
// with Long-based canonical APIs (formatAbsolute / formatRelative) plus the
// legacy string overloads.

// PhoneFormatter extracted to PhoneFormatter.kt (item 3 / CROSS7).

/**
 * Locale-aware currency formatting — ActionPlan §27.3.
 *
 * Formatting respects the active locale so decimal separators, grouping
 * separators, and currency symbol position are correct for the user's locale
 * (e.g. "1.234,56 €" in fr-CA vs "$1,234.56" in en-US).
 *
 * Currency symbol resolution order:
 *   1. Explicit [currencyCode] passed to [format] / [formatShort] (one-off override).
 *   2. [defaultCurrencyCode] set at app start from [AppPreferences.currencyOverride].
 *   3. Currency derived from [Locale.getDefault()] (OS locale default).
 *
 * Call [setDefaultCurrencyCode] from the Application / DI entry point after
 * reading [AppPreferences.currencyOverride].
 *
 * All functions are thread-safe: [NumberFormat] instances are created per-call
 * so there is no shared mutable state.
 */
object CurrencyFormatter {

    /**
     * Optional app-level currency override (ISO 4217 code, e.g. "USD", "CAD", "MXN").
     * Null = fall back to the locale default.
     * Set once at app start from [AppPreferences.currencyOverride].
     */
    @Volatile
    var defaultCurrencyCode: String? = null

    /**
     * Format [amount] using the active locale and the effective currency.
     *
     * @param amount       The monetary amount to format.
     * @param currencyCode Optional one-off ISO 4217 override. Null falls back to
     *                     [defaultCurrencyCode] then the locale default.
     */
    fun format(amount: Double, currencyCode: String? = null): String {
        val fmt = NumberFormat.getCurrencyInstance(Locale.getDefault())
        resolveCurrency(currencyCode)?.let { fmt.currency = it }
        return fmt.format(amount)
    }

    /**
     * Short format: always two decimal places, currency symbol prefix.
     * Uses the same locale/currency resolution as [format].
     *
     * Kept for legacy callers that want a compact representation without
     * grouping separators (e.g. inline price tags).
     */
    fun formatShort(amount: Double, currencyCode: String? = null): String {
        val fmt = NumberFormat.getCurrencyInstance(Locale.getDefault())
        resolveCurrency(currencyCode)?.let { fmt.currency = it }
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 2
        fmt.isGroupingUsed = false
        return fmt.format(amount)
    }

    /**
     * Returns just the currency symbol for the effective currency.
     * Useful for prefix/suffix display in input fields.
     */
    fun currencySymbol(currencyCode: String? = null): String {
        val locale = Locale.getDefault()
        val currency = resolveCurrency(currencyCode) ?: Currency.getInstance(locale)
        return currency.getSymbol(locale)
    }

    // ---------------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------------

    private fun resolveCurrency(explicit: String?): Currency? {
        val code = explicit ?: defaultCurrencyCode ?: return null
        return runCatching { Currency.getInstance(code) }.getOrNull()
    }
}
