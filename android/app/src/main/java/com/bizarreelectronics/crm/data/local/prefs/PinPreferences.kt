package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Metadata store for §2.5 PIN lock.
 *
 * The PIN itself is verified server-side via `POST /auth/verify-pin`. This
 * class only records:
 *
 *  - [isPinSet]          — whether the current user has completed PIN setup.
 *  - [failedAttempts]    — running count of wrong PINs since last success.
 *                           Reset to 0 on a successful verify.
 *  - [lockoutUntilMillis]— epoch millis; while System.currentTimeMillis() is
 *                           below this value, the keypad is frozen.
 *  - [lastUnlockAtMillis]— last successful unlock. Drives the "require PIN if
 *                           backgrounded more than N minutes" rule.
 *  - [lockTimeoutMinutes]— user preference: 0 = every resume, 1/5/15 = N min
 *                           background grace, -1 = never (only on cold start).
 *
 * Nothing here is safety-critical on its own — lockout times are advisory and
 * the server remains the source of truth on the PIN itself. The values live
 * in EncryptedSharedPreferences so a rooted device can't silently tweak the
 * attempt counter without at least breaking the AES key.
 */
@Singleton
class PinPreferences @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "pin_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    var isPinSet: Boolean
        get() = prefs.getBoolean(KEY_IS_PIN_SET, false)
        set(value) = prefs.edit().putBoolean(KEY_IS_PIN_SET, value).apply()

    var failedAttempts: Int
        get() = prefs.getInt(KEY_FAILED_ATTEMPTS, 0)
        set(value) = prefs.edit().putInt(KEY_FAILED_ATTEMPTS, value).apply()

    var lockoutUntilMillis: Long
        get() = prefs.getLong(KEY_LOCKOUT_UNTIL, 0L)
        set(value) = prefs.edit().putLong(KEY_LOCKOUT_UNTIL, value).apply()

    var lastUnlockAtMillis: Long
        get() = prefs.getLong(KEY_LAST_UNLOCK, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_UNLOCK, value).apply()

    /** -1 = never auto-lock (cold start only). 0 = every resume. 1/5/15 = min. */
    var lockTimeoutMinutes: Int
        get() = prefs.getInt(KEY_LOCK_TIMEOUT_MIN, DEFAULT_TIMEOUT_MIN)
        set(value) = prefs.edit().putInt(KEY_LOCK_TIMEOUT_MIN, value).apply()

    /**
     * Hard lockout: true when the user has burned through too many failed
     * attempts and must go through full re-auth (username + password) again.
     * The lock screen reads this to surface the "Sign out and re-login" CTA.
     */
    var hardLockout: Boolean
        get() = prefs.getBoolean(KEY_HARD_LOCKOUT, false)
        set(value) = prefs.edit().putBoolean(KEY_HARD_LOCKOUT, value).apply()

    fun isInLockout(now: Long = System.currentTimeMillis()): Boolean =
        lockoutUntilMillis > now

    fun lockoutRemainingMillis(now: Long = System.currentTimeMillis()): Long =
        (lockoutUntilMillis - now).coerceAtLeast(0L)

    /**
     * Called from MainActivity on resume to decide whether to show the lock
     * screen. Returns true when:
     *   - a PIN is configured, AND
     *   - either cold-start (lastUnlockAtMillis == 0), OR
     *   - the user has been away longer than [lockTimeoutMinutes].
     * Passing -1 for the timeout turns the background grace off entirely.
     */
    fun shouldLock(now: Long = System.currentTimeMillis()): Boolean {
        if (!isPinSet) return false
        val last = lastUnlockAtMillis
        if (last == 0L) return true // cold start or fresh setup
        val timeout = lockTimeoutMinutes
        if (timeout < 0) return false
        if (timeout == 0) return true
        val gracePeriodMs = timeout * 60L * 1000L
        return (now - last) > gracePeriodMs
    }

    fun recordSuccess() {
        prefs.edit()
            .putInt(KEY_FAILED_ATTEMPTS, 0)
            .putLong(KEY_LOCKOUT_UNTIL, 0L)
            .putBoolean(KEY_HARD_LOCKOUT, false)
            .putLong(KEY_LAST_UNLOCK, System.currentTimeMillis())
            .apply()
    }

    /**
     * Records a wrong-PIN attempt. Escalates into timed lockouts at 3/4
     * wrong, and a hard lockout requiring full re-auth at 5 wrong.
     * Returns the current attempt count after incrementing.
     */
    fun recordFailure(now: Long = System.currentTimeMillis()): Int {
        val next = failedAttempts + 1
        val editor = prefs.edit().putInt(KEY_FAILED_ATTEMPTS, next)
        when (next) {
            in 0..2 -> Unit
            3 -> editor.putLong(KEY_LOCKOUT_UNTIL, now + LOCKOUT_3X_MS)
            4 -> editor.putLong(KEY_LOCKOUT_UNTIL, now + LOCKOUT_4X_MS)
            else -> {
                editor.putBoolean(KEY_HARD_LOCKOUT, true)
                editor.putLong(KEY_LOCKOUT_UNTIL, now + LOCKOUT_5X_MS)
            }
        }
        editor.apply()
        return next
    }

    /** Clear on successful re-auth / PIN setup / logout. */
    fun reset() {
        prefs.edit().clear().apply()
    }

    private companion object {
        private const val KEY_IS_PIN_SET = "is_pin_set"
        private const val KEY_FAILED_ATTEMPTS = "failed_attempts"
        private const val KEY_LOCKOUT_UNTIL = "lockout_until"
        private const val KEY_LAST_UNLOCK = "last_unlock_at"
        private const val KEY_LOCK_TIMEOUT_MIN = "lock_timeout_min"
        private const val KEY_HARD_LOCKOUT = "hard_lockout"

        private const val DEFAULT_TIMEOUT_MIN = 5
        private const val LOCKOUT_3X_MS = 30_000L       // 30s after 3 misses
        private const val LOCKOUT_4X_MS = 60_000L       // 60s after 4 misses
        private const val LOCKOUT_5X_MS = 5 * 60_000L   // 5 min + hard-lock at 5
    }
}
