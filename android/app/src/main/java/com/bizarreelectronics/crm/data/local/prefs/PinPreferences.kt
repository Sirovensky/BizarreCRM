package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
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
 *  - [lockGraceMinutes]  — §2.5 slider value: 0 = immediate, 1/5/15 = N min,
 *                           [GRACE_NEVER] (Int.MAX_VALUE) = never mid-session.
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
     * §2.5 grace-window slider value.
     *
     * Supported values:
     *   0             — lock immediately on every resume
     *   1, 5, 15      — lock after N minutes of inactivity
     *   [GRACE_NEVER] — never lock mid-session (only on cold start)
     *
     * Default is 15 minutes.
     */
    val lockGraceMinutes: Int
        get() = prefs.getInt(KEY_LOCK_GRACE_MIN, DEFAULT_GRACE_MIN)

    /** Updates [lockGraceMinutes]. Accepted values: 0, 1, 5, 15, [GRACE_NEVER]. */
    fun setLockGraceMinutes(minutes: Int) {
        prefs.edit().putInt(KEY_LOCK_GRACE_MIN, minutes).apply()
    }

    /**
     * Emits [lockGraceMinutes] immediately and whenever it changes.
     * Backed by a [SharedPreferences.OnSharedPreferenceChangeListener] so callers
     * react in real time to pref writes from the Settings screen.
     */
    val lockGraceMinutesFlow: Flow<Int> = callbackFlow {
        trySend(lockGraceMinutes)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == KEY_LOCK_GRACE_MIN) trySend(lockGraceMinutes)
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        awaitClose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

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
     *   - either cold-start / lockNow() (lastUnlockAtMillis == 0), OR
     *   - the user has been away longer than [lockGraceMinutes].
     *
     * [lockGraceMinutes] semantics:
     *   [GRACE_NEVER]  — never lock mid-session (cold start still locks)
     *   0              — lock on every resume (< 1 000 ms treated as same session)
     *   1 / 5 / 15     — lock after N minutes background
     *
     * Also respects the legacy [lockTimeoutMinutes] if [lockGraceMinutes] has
     * not been set (i.e., prefs written by an older build).
     */
    fun shouldLock(now: Long = System.currentTimeMillis()): Boolean {
        if (!isPinSet) return false
        val last = lastUnlockAtMillis
        if (last == 0L) return true // cold start, fresh setup, or lockNow()

        val grace = lockGraceMinutes
        if (grace == GRACE_NEVER) return false
        if (grace == 0) return (now - last) >= 1_000L // allow sub-second same-session jitter
        val gracePeriodMs = grace * 60L * 1_000L
        return (now - last) > gracePeriodMs
    }

    /**
     * Forces an immediate lock by resetting [lastUnlockAtMillis] to 0.
     * The next call to [shouldLock] will return true (when a PIN is set),
     * causing MainActivity to show the PIN lock screen on resume.
     */
    fun lockNow() {
        lastUnlockAtMillis = 0L
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

    companion object {
        /**
         * Sentinel value for [lockGraceMinutes] meaning "never lock mid-session".
         * Cold-start (lastUnlockAtMillis == 0) still triggers a lock.
         */
        const val GRACE_NEVER: Int = Int.MAX_VALUE

        private const val KEY_IS_PIN_SET = "is_pin_set"
        private const val KEY_FAILED_ATTEMPTS = "failed_attempts"
        private const val KEY_LOCKOUT_UNTIL = "lockout_until"
        private const val KEY_LAST_UNLOCK = "last_unlock_at"
        private const val KEY_LOCK_TIMEOUT_MIN = "lock_timeout_min"
        private const val KEY_LOCK_GRACE_MIN = "lock_grace_min"
        private const val KEY_HARD_LOCKOUT = "hard_lockout"

        private const val DEFAULT_TIMEOUT_MIN = 5
        private const val DEFAULT_GRACE_MIN = 15        // §2.5 default: 15 minutes
        private const val LOCKOUT_3X_MS = 30_000L       // 30s after 3 misses
        private const val LOCKOUT_4X_MS = 60_000L       // 60s after 4 misses
        private const val LOCKOUT_5X_MS = 5 * 60_000L   // 5 min + hard-lock at 5
    }
}
