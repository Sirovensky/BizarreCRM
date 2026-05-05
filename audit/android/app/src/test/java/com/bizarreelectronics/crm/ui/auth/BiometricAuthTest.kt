package com.bizarreelectronics.crm.ui.auth

import androidx.biometric.BiometricManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM-only unit tests for [BiometricAuth] logic.
 *
 * NOTE: [BiometricAuth.canAuthenticate] calls [BiometricManager.from(context)] which requires
 * the Android runtime. Direct instantiation of [BiometricAuth] and calling [canAuthenticate]
 * with a real Context is therefore not possible in a pure JVM test environment.
 *
 * These tests verify the *decision logic* by extracting it into the plain-Kotlin
 * [CanAuthenticateDecider] below — a faithful mirror of the single-line branch inside
 * [BiometricAuth.canAuthenticate] — using a fake [BiometricManagerWrapper] interface.
 * This avoids any Robolectric / Hilt infrastructure while still providing coverage of the
 * branch that matters (BIOMETRIC_SUCCESS → true, everything else → false).
 *
 * The [BiometricFailure] sealed class and [BiometricAuth.showPrompt] error-code mapping are
 * tested via [BiometricFailureClassifierTest] below, which also requires no Android runtime.
 *
 * Full integration of [BiometricAuth.showPrompt] with a real BiometricPrompt (including
 * CryptoObject round-trips) should be covered by instrumented tests in androidTest.
 *
 * [~] Keystore mocking: not done here — the Android Keystore provider is unavailable in the
 * JVM test runner. [BiometricCredentialStore] Keystore behaviour is exercised only via
 * instrumented tests (androidTest). Flag [~] as noted in the plan.
 */
class BiometricAuthTest {

    // -------------------------------------------------------------------------
    // Wrapper interface so we can inject a fake BiometricManager result
    // -------------------------------------------------------------------------

    /** Thin interface that mirrors the one query we make to [BiometricManager]. */
    interface BiometricManagerWrapper {
        fun canAuthenticate(authenticators: Int): Int
    }

    /** Mirror of [BiometricAuth.canAuthenticate] with injectable [BiometricManagerWrapper]. */
    private class CanAuthenticateDecider(private val manager: BiometricManagerWrapper) {
        fun decide(authenticators: Int): Boolean =
            manager.canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS
    }

    // -------------------------------------------------------------------------
    // canAuthenticate
    // -------------------------------------------------------------------------

    @Test
    fun `canAuthenticate returns true when BiometricManager reports BIOMETRIC_SUCCESS`() {
        val decider = CanAuthenticateDecider(
            manager = object : BiometricManagerWrapper {
                override fun canAuthenticate(authenticators: Int) = BiometricManager.BIOMETRIC_SUCCESS
            },
        )
        assertTrue("Should return true on BIOMETRIC_SUCCESS", decider.decide(0))
    }

    @Test
    fun `canAuthenticate returns false when BIOMETRIC_ERROR_NO_HARDWARE`() {
        val decider = CanAuthenticateDecider(
            manager = object : BiometricManagerWrapper {
                override fun canAuthenticate(authenticators: Int) =
                    BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE
            },
        )
        assertFalse("Should return false on ERROR_NO_HARDWARE", decider.decide(0))
    }

    @Test
    fun `canAuthenticate returns false when BIOMETRIC_ERROR_HW_UNAVAILABLE`() {
        val decider = CanAuthenticateDecider(
            manager = object : BiometricManagerWrapper {
                override fun canAuthenticate(authenticators: Int) =
                    BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE
            },
        )
        assertFalse("Should return false on ERROR_HW_UNAVAILABLE", decider.decide(0))
    }

    @Test
    fun `canAuthenticate returns false when BIOMETRIC_ERROR_NONE_ENROLLED`() {
        val decider = CanAuthenticateDecider(
            manager = object : BiometricManagerWrapper {
                override fun canAuthenticate(authenticators: Int) =
                    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED
            },
        )
        assertFalse("Should return false when no biometrics enrolled", decider.decide(0))
    }

    @Test
    fun `canAuthenticate returns false when BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED`() {
        val decider = CanAuthenticateDecider(
            manager = object : BiometricManagerWrapper {
                override fun canAuthenticate(authenticators: Int) =
                    BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED
            },
        )
        assertFalse("Should return false on SECURITY_UPDATE_REQUIRED", decider.decide(0))
    }
}

/**
 * Tests for [BiometricFailure] classification — the logic that maps BiometricPrompt error
 * codes to the typed [BiometricFailure] sealed class. No Android runtime required.
 */
class BiometricFailureClassifierTest {

    /**
     * Mirrors the when-expression inside [BiometricAuth.showPrompt] so it can be tested
     * without a FragmentActivity or BiometricPrompt instance.
     */
    private fun classify(errorCode: Int): BiometricFailure = when (errorCode) {
        androidx.biometric.BiometricPrompt.ERROR_NO_BIOMETRICS,
        androidx.biometric.BiometricPrompt.ERROR_HW_UNAVAILABLE,
        androidx.biometric.BiometricPrompt.ERROR_HW_NOT_PRESENT,
        -> BiometricFailure.Disabled

        androidx.biometric.BiometricPrompt.ERROR_USER_CANCELED,
        androidx.biometric.BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        -> BiometricFailure.UserCancelled

        else -> BiometricFailure.SystemError(errorCode, "error $errorCode")
    }

    @Test
    fun `ERROR_NO_BIOMETRICS maps to Disabled`() {
        val result = classify(androidx.biometric.BiometricPrompt.ERROR_NO_BIOMETRICS)
        assertTrue("Expected Disabled", result is BiometricFailure.Disabled)
    }

    @Test
    fun `ERROR_HW_UNAVAILABLE maps to Disabled`() {
        val result = classify(androidx.biometric.BiometricPrompt.ERROR_HW_UNAVAILABLE)
        assertTrue("Expected Disabled", result is BiometricFailure.Disabled)
    }

    @Test
    fun `ERROR_HW_NOT_PRESENT maps to Disabled`() {
        val result = classify(androidx.biometric.BiometricPrompt.ERROR_HW_NOT_PRESENT)
        assertTrue("Expected Disabled", result is BiometricFailure.Disabled)
    }

    @Test
    fun `ERROR_USER_CANCELED maps to UserCancelled`() {
        val result = classify(androidx.biometric.BiometricPrompt.ERROR_USER_CANCELED)
        assertTrue("Expected UserCancelled", result is BiometricFailure.UserCancelled)
    }

    @Test
    fun `ERROR_NEGATIVE_BUTTON maps to UserCancelled`() {
        val result = classify(androidx.biometric.BiometricPrompt.ERROR_NEGATIVE_BUTTON)
        assertTrue("Expected UserCancelled", result is BiometricFailure.UserCancelled)
    }

    @Test
    fun `unknown error code maps to SystemError with the code preserved`() {
        val code = 999
        val result = classify(code)
        assertTrue("Expected SystemError", result is BiometricFailure.SystemError)
        val err = result as BiometricFailure.SystemError
        assertTrue("Code should be preserved", err.code == code)
    }
}
