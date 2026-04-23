package com.bizarreelectronics.crm.util

import timber.log.Timber

/**
 * Timber Tree that scrubs sensitive keys from log messages before delegating
 * to the underlying DebugTree / release tree (ActionPlan §1 L228, §28 L64).
 *
 * Sensitive keys masked (mirrors RedactingHttpLogger + LogRedactor key lists):
 *   password, currentPassword, newPassword,
 *   access_token, accessToken,
 *   refresh_token, refreshToken,
 *   pin, currentPin, newPin,
 *   backup_code, backupCode,
 *   authorization, totp, secret, manualEntry, setup_token, setupToken,
 *   credit_card, card_number, cvv, ssn
 *
 * Masking rule: recognises two forms —
 *   JSON    : "key" : "value"  → value replaced with [MASK]
 *   Encoded : key=value        → value replaced with [MASK]
 * Both are handled case-insensitively in a single compiled alternation pass
 * so complexity is O(n) in message length.
 *
 * PII patterns (phone, email, bearer tokens, JWTs, IMEIs, card numbers,
 * SSNs) are delegated to [LogRedactor.redact] after the key-value sweep.
 *
 * Safe to chain in front of any [Timber.Tree] — this Tree never consumes
 * the log entry; it sanitises message + throwable.message and forwards to
 * [delegate].
 *
 * Thread-safety: [REDACT_PATTERN] is a compiled [Regex] (wraps an immutable
 * java.util.regex.Pattern). No mutable state is held. Multiple threads may
 * call [log] concurrently without synchronisation.
 */
class RedactorTree(private val delegate: Timber.Tree) : Timber.Tree() {

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val safeMessage = redact(message)
        val safeThrowable = t?.let { redactThrowable(it) }
        delegate.log(priority, tag, safeMessage, safeThrowable)
    }

    /**
     * Sanitises [input] by:
     *  1. Masking key=value and "key":"value" pairs for all [SENSITIVE_KEYS].
     *  2. Running [LogRedactor.redact] to strip bearer tokens, JWTs, IMEIs,
     *     card numbers, SSNs, phones, and emails.
     *
     * Returns [input] unchanged when blank.
     */
    internal fun redact(input: String): String {
        if (input.isBlank()) return input
        // Step 1: key-value masking (single alternation pass, O(n))
        val keyMasked = REDACT_PATTERN.replace(input) { match ->
            // group(1) is non-null for JSON form  : "key": "..."
            // group(3) is non-null for encoded form: key=...
            val jsonPrefix = match.groups[1]?.value
            val encPrefix = match.groups[3]?.value
            when {
                jsonPrefix != null -> "$jsonPrefix\"$MASK\""
                encPrefix != null  -> "$encPrefix$MASK"
                else               -> match.value   // should never happen
            }
        }
        // Step 2: structural PII sweep (tokens, phone, email, IMEI, cards, SSNs)
        return LogRedactor.redact(keyMasked)
    }

    /**
     * Returns a new [Throwable] whose [Throwable.message] is redacted.
     * The original stack trace is preserved; only the human-readable message
     * string is sanitised.
     */
    private fun redactThrowable(t: Throwable): Throwable {
        val originalMsg = t.message ?: return t
        val safeMsg = redact(originalMsg)
        if (safeMsg == originalMsg) return t    // nothing changed — reuse original
        return object : Throwable(safeMsg, t.cause) {
            init {
                stackTrace = t.stackTrace
                t.suppressed.forEach { addSuppressed(it) }
            }
        }
    }

    companion object {
        /** Keys whose values must never appear in log output. */
        val SENSITIVE_KEYS: List<String> = listOf(
            "currentPassword",
            "newPassword",
            "password",
            "access_token",
            "accessToken",
            "refresh_token",
            "refreshToken",
            "currentPin",
            "newPin",
            "pin",
            "backup_code",
            "backupCode",
            "authorization",
            "totp",
            "manualEntry",
            "setup_token",
            "setupToken",
            "secret",
            "credit_card",
            "card_number",
            "cvv",
            "ssn",
        )

        const val MASK = "***REDACTED***"

        /**
         * Single compiled alternation regex — one pass, O(n) in message length.
         *
         * Two capturing alternatives:
         *   Alt A (JSON)    : group 1 = `"key"\s*:\s*`, group 2 = value string
         *   Alt B (encoded) : group 3 = `key=`,         group 4 = value token
         *
         * Keys are sorted longest-first so longer keys (e.g. "currentPassword")
         * are tried before their shorter prefixes ("password").
         */
        private val REDACT_PATTERN: Regex = run {
            // Longest-first to prevent shorter-prefix short-circuits.
            val sortedKeys = SENSITIVE_KEYS.sortedByDescending { it.length }
            val alt = sortedKeys.joinToString("|") { Regex.escape(it) }
            // Alt A: ("key"\s*:\s*)"value"   — groups 1=prefix, 2=inner value
            // Alt B: (key=)token              — groups 3=prefix, 4=value token
            Regex("""(?i)("(?:$alt)"\s*:\s*)"([^"]*)"|(\b(?:$alt)=)([^&\s]*)""")
        }
    }
}
