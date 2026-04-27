package com.bizarreelectronics.crm.util

import java.text.NumberFormat
import java.util.Locale

// CROSS46: DateFormatter extracted to its own file (util/DateFormatter.kt)
// with Long-based canonical APIs (formatAbsolute / formatRelative) plus the
// legacy string overloads.

// PhoneFormatter extracted to PhoneFormatter.kt (item 3 / CROSS7).

/**
 * CurrencyFormatter — legacy fixed-US-locale formatter.
 *
 * §27.3 NOTE: New code should prefer [LocaleAwareFormatters.formatCurrency] which
 * respects the user's active locale and [AppPreferences.currencyOverride].
 *
 * [CurrencyFormatter] is retained for existing callers that do NOT have access to
 * AppPreferences (e.g. pure utility functions, tests) and expect a hard USD format.
 * Do not add new callers; migrate existing ones to [LocaleAwareFormatters] as you
 * touch the relevant screens.
 */
object CurrencyFormatter {
    // Kept as a fixed US locale to avoid breaking existing callers.
    // §27.3: prefer LocaleAwareFormatters.formatCurrency() for new code.
    private val format = NumberFormat.getCurrencyInstance(Locale.US)

    fun format(amount: Double): String = format.format(amount)
    fun formatShort(amount: Double): String = "$${String.format("%.2f", amount)}"
}
