package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §2.5 PIN lock — thin facade over `AuthApi.verifyPin` / `AuthApi.changePin`
 * that layers on the local lockout bookkeeping in [PinPreferences].
 *
 * Verification is strictly server-side. We never store the PIN hash on the
 * device; the only local state is attempt counters so the UI can show
 * lockout timers and escalate to full re-auth after 5 misses.
 */
@Singleton
class PinRepository @Inject constructor(
    private val authApi: AuthApi,
    private val pinPrefs: PinPreferences,
) {

    sealed interface VerifyResult {
        /** PIN correct — the keypad should dismiss. */
        data object Success : VerifyResult

        /** Wrong PIN, still retries left. [remaining] = tries before hard-lock. */
        data class WrongPin(val remaining: Int) : VerifyResult

        /** Timed lockout after 3 / 4 wrong tries. Keypad frozen until [untilMillis]. */
        data class Lockout(val untilMillis: Long) : VerifyResult

        /**
         * 5+ wrong tries — user must sign out and log back in with password
         * (+ 2FA if enabled) before setting a new PIN.
         */
        data object HardLockout : VerifyResult

        /** Network / server failure. Does NOT increment the local attempt counter. */
        data class Error(val message: String) : VerifyResult
    }

    suspend fun verify(pin: String): VerifyResult {
        if (pinPrefs.hardLockout) return VerifyResult.HardLockout
        val now = System.currentTimeMillis()
        if (pinPrefs.isInLockout(now)) {
            return VerifyResult.Lockout(pinPrefs.lockoutUntilMillis)
        }
        val response = try {
            authApi.verifyPin(mapOf("pin" to pin))
        } catch (t: Throwable) {
            return VerifyResult.Error(t.message ?: "Network error")
        }
        if (!response.success) {
            return VerifyResult.Error(response.message ?: "Verification failed")
        }
        val verified = response.data?.get("verified") == true
        return if (verified) {
            pinPrefs.recordSuccess()
            VerifyResult.Success
        } else {
            val count = pinPrefs.recordFailure(now)
            when {
                pinPrefs.hardLockout -> VerifyResult.HardLockout
                pinPrefs.isInLockout() -> VerifyResult.Lockout(pinPrefs.lockoutUntilMillis)
                else -> VerifyResult.WrongPin(remaining = (MAX_ATTEMPTS - count).coerceAtLeast(0))
            }
        }
    }

    sealed interface ChangeResult {
        data object Success : ChangeResult
        data class Error(val message: String) : ChangeResult
    }

    /** First-time setup — `currentPin` omitted. */
    suspend fun setInitialPin(newPin: String): ChangeResult = change(null, newPin)

    suspend fun changePin(currentPin: String, newPin: String): ChangeResult =
        change(currentPin, newPin)

    private suspend fun change(currentPin: String?, newPin: String): ChangeResult {
        if (!isAcceptablePin(newPin)) {
            return ChangeResult.Error("Pick a PIN that isn't a common sequence.")
        }
        val body = buildMap {
            put("newPin", newPin)
            if (currentPin != null) put("currentPin", currentPin)
        }
        val response = try {
            authApi.changePin(body)
        } catch (t: Throwable) {
            return ChangeResult.Error(t.message ?: "Network error")
        }
        if (!response.success) {
            return ChangeResult.Error(response.message ?: "Change failed")
        }
        pinPrefs.isPinSet = true
        pinPrefs.recordSuccess()
        return ChangeResult.Success
    }

    /**
     * Tiny blocklist to steer users away from the most obvious 4-digit PINs.
     * Not a substitute for server-side entropy rules — the server still has
     * the final say.
     */
    private fun isAcceptablePin(pin: String): Boolean {
        if (pin.length !in 4..6) return false
        if (!pin.all { it.isDigit() }) return false
        if (pin in COMMON_PINS) return false
        // Reject all-same-digit (0000, 1111, …) and strict runs (1234, 4321).
        if (pin.toSet().size == 1) return false
        if (isMonotonicRun(pin)) return false
        return true
    }

    private fun isMonotonicRun(pin: String): Boolean {
        val asc = pin.zipWithNext().all { (a, b) -> b.code - a.code == 1 }
        val desc = pin.zipWithNext().all { (a, b) -> a.code - b.code == 1 }
        return asc || desc
    }

    private companion object {
        private const val MAX_ATTEMPTS = 5
        private val COMMON_PINS = setOf(
            "0000", "1111", "1234", "2222", "4321", "9999",
            "111111", "123456", "654321", "000000", "222222",
        )
    }
}
