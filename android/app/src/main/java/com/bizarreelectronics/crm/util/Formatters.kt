package com.bizarreelectronics.crm.util

import java.text.NumberFormat
import java.util.Locale

// CROSS46: DateFormatter extracted to its own file (util/DateFormatter.kt)
// with Long-based canonical APIs (formatAbsolute / formatRelative) plus the
// legacy string overloads.

object PhoneFormatter {
    fun format(phone: String?): String {
        if (phone.isNullOrBlank()) return ""
        val digits = phone.replace(Regex("[^0-9]"), "")
        return when {
            digits.length == 10 -> "(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}"
            digits.length == 11 && digits.startsWith("1") -> "(${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}"
            else -> phone
        }
    }

    fun normalize(phone: String?): String {
        if (phone.isNullOrBlank()) return ""
        val digits = phone.replace(Regex("[^0-9]"), "")
        return if (digits.length == 11 && digits.startsWith("1")) digits.substring(1) else digits
    }
}

object CurrencyFormatter {
    private val format = NumberFormat.getCurrencyInstance(Locale.US)

    fun format(amount: Double): String = format.format(amount)
    fun formatShort(amount: Double): String = "$${String.format("%.2f", amount)}"
}
