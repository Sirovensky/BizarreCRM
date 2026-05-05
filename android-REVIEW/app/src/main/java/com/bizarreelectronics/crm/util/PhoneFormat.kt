package com.bizarreelectronics.crm.util

/**
 * Canonical phone DISPLAY helper (CROSS8 / CROSS13).
 *
 * Adopted per MEMORY rule + CROSS7's on-write format:
 *   `+1 (XXX)-XXX-XXXX`  — parens, dashes, leading +1 for US numbers.
 *
 * Accepts any of:
 *   - raw digits      ("5555551234")
 *   - E.164           ("+15555551234")
 *   - partly-formatted ("(555) 555-1234", "555-555-1234", "+1 (555)-555-1234")
 *
 * Returns the canonical `+1 (XXX)-XXX-XXXX` form when exactly 10 digits remain
 * after stripping (or 11 starting with `1`). For anything else — blanks,
 * <10-digit stubs, international numbers (>11 digits / non-US country code) —
 * returns the raw input untouched so non-US callers aren't mangled.
 *
 * Single source of truth for phone DISPLAY everywhere. Do not inline phone
 * formatting in screen files — import and call [formatPhoneDisplay].
 *
 * For phone INPUT (as-you-type formatting while the user edits a field) see
 * the customer create screen's own VisualTransformation (CROSS7) which emits
 * the same format progressively.
 */
fun formatPhoneDisplay(phone: String?): String {
    if (phone.isNullOrBlank()) return ""
    val digits = phone.replace(Regex("[^0-9]"), "")
    return when {
        digits.length == 10 ->
            "+1 (${digits.substring(0, 3)})-${digits.substring(3, 6)}-${digits.substring(6)}"
        digits.length == 11 && digits.startsWith("1") ->
            "+1 (${digits.substring(1, 4)})-${digits.substring(4, 7)}-${digits.substring(7)}"
        // <10 digits, or international (>11 digits / non-US country code):
        // leave the user's input alone rather than guess a US format.
        else -> phone
    }
}
