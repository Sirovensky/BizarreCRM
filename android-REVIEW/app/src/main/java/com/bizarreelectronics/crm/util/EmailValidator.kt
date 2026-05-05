package com.bizarreelectronics.crm.util

/**
 * Pragmatic email-address validator.
 *
 * RFC 5321 allows more forms than a phone-in-the-field UX should accept
 * (quoted-local, IP-literal, 254-char totals, etc.). This helper trims the
 * input, rejects blanks, and applies the same "user@host.tld" shape the
 * repair-shop workflow expects. It is deliberately case-insensitive on both
 * the local part and the domain — the server accepts either.
 *
 * Shared between CustomerCreate, SignupScreen, and SMS reply-to so every
 * screen flags the same strings as bad.
 */
object EmailValidator {

    enum class Result {
        /** Empty / whitespace-only input. Show no error message (field not touched). */
        Empty,

        /** Passes the shape check. */
        Ok,

        /** Fails the shape check. */
        Malformed,
    }

    // Pragmatic ASCII email pattern:
    //   - local:   letters, digits, and the common specials (._%+-)
    //   - @ sep
    //   - domain:  letters/digits/hyphens, dot-separated, TLD ≥ 2 letters
    //
    // Case-folded before matching via the trim/lowercase chain in [validate].
    private val PATTERN = Regex("""^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$""")

    fun validate(raw: String?): Result {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return Result.Empty
        return if (PATTERN.matches(trimmed.lowercase())) Result.Ok else Result.Malformed
    }

    /** Convenience: true when the address is Ok. Empty counts as invalid. */
    fun isValid(raw: String?): Boolean = validate(raw) == Result.Ok
}
