package com.bizarreelectronics.crm.util

/**
 * §28.6 / §32.6 — PII redactor for log strings.
 *
 * The existing [RedactingHttpLogger] strips Authorization headers + query
 * params from OkHttp logs, but in-app Log calls (breadcrumb labels,
 * error-banner strings, crumbs written into the [CrashReporter] file)
 * routinely embed customer PII by accident — phone numbers, emails,
 * bearer tokens, IMEIs, card numbers. This object centralises the regex
 * sweep so every emitter can run a single [redact] call before logging.
 *
 * Philosophy: always prefer mis-redacting a non-PII string over leaking
 * a real value. The regexes err on the side of over-matching — e.g. any
 * 15-digit run is replaced with `[IMEI]` even if it happens to be a part
 * SKU or a serial, because redacting a SKU is harmless but leaking an
 * IMEI into a support log is not.
 */
object LogRedactor {

    // --- Patterns in application order (most specific first) ---------------

    // Bearer tokens: "Bearer abc..." or "Authorization: Bearer abc..."
    private val BEARER = Regex("""(?i)(bearer\s+)[A-Za-z0-9._\-]+""")

    // JWT-ish three-section tokens with two dots.
    private val JWT = Regex("""\b[A-Za-z0-9_\-]{12,}\.[A-Za-z0-9_\-]{12,}\.[A-Za-z0-9_\-]{12,}\b""")

    // IMEI: exactly 15 digits in a row. Must run BEFORE [CARD] so a 15-digit
    // IMEI isn't shadowed by the card regex (Amex cards happen to be 15
    // digits too — but a bare 15-digit token in a log is overwhelmingly an
    // IMEI, and masking an Amex as IMEI still protects the user).
    private val IMEI = Regex("""(?<!\d)\d{15}(?!\d)""")

    // Credit card numbers: 13-19 digits with at least one separator to avoid
    // over-matching long SKUs / reference numbers. Masked to last 4.
    private val CARD = Regex("""\b(?:\d{4}[ -]){3}\d{1,7}\b""")

    // US-style SSN: NNN-NN-NNNN (also catches NNNNNNNNN).
    private val SSN = Regex("""\b\d{3}-\d{2}-\d{4}\b|\b\d{9}\b""")

    // E.164 / US phone — 10-11 digits with optional + / parens / dashes
    // inside the body. No leading whitespace class so the match starts at
    // the digits themselves and doesn't swallow the preceding space.
    private val PHONE = Regex("""\+?1?\(?\d{3}\)?[\s\-\.]?\d{3}[\s\-\.]?\d{4}""")

    // Email: simple RFC-ish shape.
    private val EMAIL = Regex("""[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}""")

    /**
     * Redacts PII patterns. The input is returned unchanged if it is blank.
     *
     * Patterns are applied in the order above so higher-specificity matches
     * (e.g. Bearer tokens, IMEIs) don't get shadowed by lower-specificity
     * ones (e.g. phone numbers).
     */
    fun redact(input: String): String {
        if (input.isBlank()) return input
        return input
            .replace(BEARER, "$1[REDACTED]")
            .replace(JWT, "[JWT]")
            // IMEI before CARD because both can match 15 digits. A 15-digit
            // bare token is overwhelmingly an IMEI in repair-shop logs.
            .replace(IMEI, "[IMEI]")
            .replace(CARD) { m -> "****-****-****-" + m.value.filter { it.isDigit() }.takeLast(4) }
            .replace(SSN, "[SSN]")
            .replace(PHONE, "[PHONE]")
            .replace(EMAIL, "[EMAIL]")
    }
}
