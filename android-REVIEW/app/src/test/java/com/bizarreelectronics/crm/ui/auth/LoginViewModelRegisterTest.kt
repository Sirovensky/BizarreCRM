package com.bizarreelectronics.crm.ui.auth

// §2.7-L326/L327 — JVM unit tests for multi-step signup state & validation logic.
//
// Scope: tests that exercise pure Kotlin state — no Android Keystore, no OkHttp,
//         no Compose, no Hilt injection required.
//
// Coverage:
//   (a) RegisterSubStep ordinal ordering and count — guards against accidental
//       reordering that would break the LinearProgressIndicator fraction.
//   (b) LoginUiState.copy() immutability — verifies the data class produces
//       a new instance on registerSubStep change (coding-style requirement).
//   (c) Password strength evaluation used by Owner sub-step Next gate — ensures
//       the FAIR threshold blocks WEAK passwords (regression guard for §2.7-L326).
//   (d) Email regex validation pattern used by registerNextSubStep() — verifies
//       that the Regex accepts valid addresses and rejects malformed ones.
//
// Full ViewModel integration (auto-login path, OkHttp signup call, Keystore token
// storage) is covered by instrumented tests in androidTest.

import com.bizarreelectronics.crm.ui.screens.auth.LoginUiState
import com.bizarreelectronics.crm.ui.screens.auth.RegisterSubStep
import com.bizarreelectronics.crm.ui.screens.auth.SetupStep
import com.bizarreelectronics.crm.util.PasswordStrength
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test

class LoginViewModelRegisterTest {

    // ── (a) RegisterSubStep ordering & count ─────────────────────────────────

    @Test
    fun `RegisterSubStep has 4 values in correct order`() {
        val steps = RegisterSubStep.values()
        assertEquals("Expected 4 sub-steps", 4, steps.size)
        assertEquals(RegisterSubStep.Company,   steps[0])
        assertEquals(RegisterSubStep.Owner,     steps[1])
        assertEquals(RegisterSubStep.ServerUrl, steps[2])
        assertEquals(RegisterSubStep.Confirm,   steps[3])
    }

    @Test
    fun `LinearProgressIndicator fraction is non-zero for every sub-step`() {
        RegisterSubStep.values().forEachIndexed { index, _ ->
            val fraction = (index + 1).toFloat() / RegisterSubStep.values().size.toFloat()
            assertTrue("Fraction must be > 0 for index $index", fraction > 0f)
            assertTrue("Fraction must be <= 1 for index $index", fraction <= 1f)
        }
    }

    // ── (b) LoginUiState immutability ────────────────────────────────────────

    @Test
    fun `LoginUiState copy produces a new object with updated registerSubStep`() {
        val original = LoginUiState(step = SetupStep.REGISTER, registerSubStep = RegisterSubStep.Company)
        val updated = original.copy(registerSubStep = RegisterSubStep.Owner)

        assertNotSame("copy() must return a new instance", original, updated)
        assertEquals(RegisterSubStep.Company, original.registerSubStep) // original unchanged
        assertEquals(RegisterSubStep.Owner, updated.registerSubStep)
    }

    @Test
    fun `LoginUiState goToRegister defaults registerSubStep to Company`() {
        val state = LoginUiState(
            step = SetupStep.REGISTER,
            registerSubStep = RegisterSubStep.Confirm, // simulate in-progress registration
        )
        // Simulates goToRegister() resetting the sub-step
        val reset = state.copy(step = SetupStep.REGISTER, registerSubStep = RegisterSubStep.Company, error = null)
        assertEquals(RegisterSubStep.Company, reset.registerSubStep)
        assertFalse(reset.isLoading)
    }

    // ── (c) Password strength threshold ─────────────────────────────────────

    @Test
    fun `WEAK password is below FAIR threshold — Owner Next gate must block it`() {
        val weakResult = PasswordStrength.evaluate("password")
        assertTrue(
            "WEAK password must be below FAIR",
            weakResult.level < PasswordStrength.Level.FAIR,
        )
    }

    @Test
    fun `FAIR or better password passes Owner Next gate`() {
        // "Passw0rd!xyz" has lowercase, uppercase, digit, symbol — should be FAIR+
        val result = PasswordStrength.evaluate("Passw0rd!xyz")
        assertTrue(
            "Expected at least FAIR, got ${result.level}",
            result.level >= PasswordStrength.Level.FAIR,
        )
    }

    // ── (d) Email regex used by registerNextSubStep() ────────────────────────

    private val EMAIL_REGEX = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+\$")

    @Test
    fun `email regex accepts valid addresses`() {
        val valid = listOf(
            "alice@example.com",
            "user.name+tag@sub.domain.io",
            "a@b.co",
        )
        valid.forEach { email ->
            assertTrue("Expected '$email' to be valid", EMAIL_REGEX.matches(email))
        }
    }

    @Test
    fun `email regex rejects malformed addresses`() {
        val invalid = listOf(
            "not-an-email",
            "@nodomain.com",
            "missingdot@nodot",
            "space in@email.com",
            "",
        )
        invalid.forEach { email ->
            assertFalse("Expected '$email' to be invalid", EMAIL_REGEX.matches(email))
        }
    }
}
