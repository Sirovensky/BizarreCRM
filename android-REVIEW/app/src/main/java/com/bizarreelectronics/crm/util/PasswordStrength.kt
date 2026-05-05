package com.bizarreelectronics.crm.util

/**
 * Pure-JVM password strength evaluator.
 *
 * No Android dependencies — safe for unit tests on the JVM host without Robolectric.
 *
 * Rules checked:
 *   MIN_LENGTH   — at least 8 characters
 *   HAS_LOWER    — at least one lowercase letter
 *   HAS_UPPER    — at least one uppercase letter
 *   HAS_DIGIT    — at least one digit
 *   HAS_SYMBOL   — at least one non-alphanumeric character
 *   NOT_COMMON   — not a member of the embedded common-password list
 *
 * Strength tiers (number of passing rules, 0–6):
 *   NONE       — empty password
 *   WEAK       — 1–2 rules pass (typically just MIN_LENGTH alone)
 *   FAIR       — 3 rules pass
 *   STRONG     — 4–5 rules pass
 *   VERY_STRONG — all 6 rules pass
 *
 * Expansion path for NOT_COMMON: the current list is the top 50 breached passwords
 * (small APK footprint). Replace COMMON_PASSWORDS with a resource-loaded list at
 * startup to scale to 1000 entries without increasing binary size.
 */
object PasswordStrength {

    enum class Rule {
        MIN_LENGTH,
        HAS_LOWER,
        HAS_UPPER,
        HAS_DIGIT,
        HAS_SYMBOL,
        NOT_COMMON,
    }

    enum class Level {
        NONE,
        WEAK,
        FAIR,
        STRONG,
        VERY_STRONG,
    }

    data class Result(
        val level: Level,
        val ruleChecks: Map<Rule, Boolean>,
    )

    /**
     * Top-50 most breached passwords (SecLists common-passwords subset).
     * Checked case-insensitively. Expand this list at runtime via resource
     * injection for stricter enforcement without increasing APK binary size.
     */
    private val COMMON_PASSWORDS: Set<String> = setOf(
        "password", "123456", "12345678", "1234567890", "qwerty", "abc123",
        "monkey", "1234567", "letmein", "trustno1", "dragon", "baseball",
        "iloveyou", "master", "sunshine", "ashley", "bailey", "passw0rd",
        "shadow", "123123", "654321", "superman", "qazwsx", "michael",
        "football", "password1", "password123", "123456789", "000000",
        "111111", "222222", "333333", "444444", "555555", "666666", "777777",
        "888888", "999999", "121212", "696969", "1234", "12345", "123",
        "qwertyuiop", "login", "welcome", "solo", "princess", "admin",
        "admin123",
    )

    /**
     * Evaluates [password] against all rules and returns a [Result].
     *
     * The input string is never mutated. All checks operate on the
     * original reference via read-only standard library functions.
     */
    fun evaluate(password: String): Result {
        if (password.isEmpty()) {
            return Result(
                level = Level.NONE,
                ruleChecks = Rule.values().associateWith { false },
            )
        }

        val checks: Map<Rule, Boolean> = mapOf(
            Rule.MIN_LENGTH to (password.length >= 8),
            Rule.HAS_LOWER  to password.any { it.isLowerCase() },
            Rule.HAS_UPPER  to password.any { it.isUpperCase() },
            Rule.HAS_DIGIT  to password.any { it.isDigit() },
            Rule.HAS_SYMBOL to password.any { !it.isLetterOrDigit() },
            Rule.NOT_COMMON to !COMMON_PASSWORDS.contains(password.lowercase()),
        )

        val passing = checks.values.count { it }

        val level = when {
            passing == 6            -> Level.VERY_STRONG
            passing in 4..5         -> Level.STRONG
            passing == 3            -> Level.FAIR
            else                    -> Level.WEAK
        }

        return Result(level = level, ruleChecks = checks)
    }
}
