package com.bizarreelectronics.crm.util

import java.text.NumberFormat
import java.util.Locale

// CROSS46: DateFormatter extracted to its own file (util/DateFormatter.kt)
// with Long-based canonical APIs (formatAbsolute / formatRelative) plus the
// legacy string overloads.

// PhoneFormatter extracted to PhoneFormatter.kt (item 3 / CROSS7).

object CurrencyFormatter {
    private val format = NumberFormat.getCurrencyInstance(Locale.US)

    fun format(amount: Double): String = format.format(amount)
    fun formatShort(amount: Double): String = "$${String.format("%.2f", amount)}"
}
