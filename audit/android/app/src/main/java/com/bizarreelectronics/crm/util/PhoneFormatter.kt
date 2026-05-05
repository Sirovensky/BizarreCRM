package com.bizarreelectronics.crm.util

/**
 * Canonical phone formatter for display and normalization (CROSS7 / item 3).
 *
 * libphonenumber is NOT in the project's build.gradle (confirmed absent).
 * This is a regex-based stub that handles US numbers correctly.
 *
 * [format] — applies display formatting on save:
 *   US 10-digit → "(NNN) NNN-NNNN"
 *   US 11-digit (1XXXXXXXXXX) → strips leading 1 then same
 *   Other → returned unchanged (non-US international, partial numbers)
 *
 * [normalize] — strips formatting to bare local digits (10 for US).
 *
 * Usage:
 *   PhoneFormatter.format("5555551234")         → "(555) 555-1234"
 *   PhoneFormatter.format("+15555551234", "US") → "(555) 555-1234"
 *   PhoneFormatter.normalize("+1 (555) 555-1234") → "5555551234"
 */
object PhoneFormatter {

    /**
     * Format [phone] for display. [regionCode] is reserved for future
     * libphonenumber integration; currently only "US" formatting is applied.
     */
    fun format(phone: String?, regionCode: String = "US"): String {
        if (phone.isNullOrBlank()) return ""
        val digits = phone.replace(Regex("[^0-9]"), "")
        return when {
            digits.length == 10 ->
                "(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}"
            digits.length == 11 && digits.startsWith("1") ->
                "(${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}"
            else -> phone // non-US or partial — leave untouched
        }
    }

    /**
     * Normalize [phone] to bare digits (US local 10-digit where possible).
     * Strips country code "1" prefix when the result would be 11 digits.
     */
    fun normalize(phone: String?): String {
        if (phone.isNullOrBlank()) return ""
        val digits = phone.replace(Regex("[^0-9]"), "")
        return if (digits.length == 11 && digits.startsWith("1")) digits.substring(1) else digits
    }
}
