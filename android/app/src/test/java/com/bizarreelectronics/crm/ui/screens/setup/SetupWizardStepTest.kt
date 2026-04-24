package com.bizarreelectronics.crm.ui.screens.setup

// §2.10 [plan:L343] — JVM unit tests for SetupWizard step validation logic.
//
// Scope: pure Kotlin state only — no Android Keystore, no OkHttp, no Compose,
//        no Hilt injection required. Mirrors the pattern established by
//        LoginViewModelRegisterTest (ui/auth/).
//
// Coverage:
//   (a) SETUP_WIZARD_TOTAL_STEPS constant is 13.
//   (b) Step 0 (Welcome) — always valid.
//   (c) Step 1 (Business info) — validates shop_name, phone, timezone.
//   (d) Step 2 (Owner account) — validates username, email, password.
//   (e) Step 3 (Tax classes) — accepts "skipped" or "tax_classes" key.
//   (f) Step 4 (Payment methods) — accepts "skipped" or "payment_methods" key.
//   (g) Steps 5–12 — always valid (skippable).
//   (h) SetupWizardUiState.copy() immutability — data class contract.

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Test

class SetupWizardStepTest {

    // ── (a) Total steps constant ─────────────────────────────────────────────

    @Test
    fun `SETUP_WIZARD_TOTAL_STEPS is 13`() {
        assertEquals(13, SETUP_WIZARD_TOTAL_STEPS)
    }

    // ── (b) Step 0 — Welcome ─────────────────────────────────────────────────

    @Test
    fun `step 0 is always valid with empty data`() {
        assertNull(SetupStepValidator.validate(0, emptyMap()))
    }

    @Test
    fun `step 0 is valid with any arbitrary data`() {
        assertNull(SetupStepValidator.validate(0, mapOf("anything" to "value")))
    }

    // ── (c) Step 1 — Business info ───────────────────────────────────────────

    @Test
    fun `step 1 fails when shop_name is blank`() {
        val data = mapOf("shop_name" to "", "phone" to "416-555-0100", "timezone" to "America/Toronto", "shop_type" to "repair")
        assertNotNull(SetupStepValidator.validate(1, data))
    }

    @Test
    fun `step 1 fails when phone is blank`() {
        val data = mapOf("shop_name" to "Bizarre Electronics", "phone" to "", "timezone" to "America/Toronto")
        assertNotNull(SetupStepValidator.validate(1, data))
    }

    @Test
    fun `step 1 fails when timezone is blank`() {
        val data = mapOf("shop_name" to "Bizarre Electronics", "phone" to "416-555-0100", "timezone" to "")
        assertNotNull(SetupStepValidator.validate(1, data))
    }

    @Test
    fun `step 1 passes with all required fields`() {
        val data = mapOf(
            "shop_name" to "Bizarre Electronics",
            "phone"     to "416-555-0100",
            "timezone"  to "America/Toronto",
            "address"   to "123 Main St",
            "shop_type" to "repair",
        )
        assertNull(SetupStepValidator.validate(1, data))
    }

    // ── (d) Step 2 — Owner account ───────────────────────────────────────────

    @Test
    fun `step 2 fails when username is too short`() {
        val data = mapOf("username" to "ab", "email" to "admin@example.com", "password" to "password123")
        assertNotNull(SetupStepValidator.validate(2, data))
    }

    @Test
    fun `step 2 fails when email is malformed`() {
        val data = mapOf("username" to "admin", "email" to "notanemail", "password" to "password123")
        assertNotNull(SetupStepValidator.validate(2, data))
    }

    @Test
    fun `step 2 fails when password is too short`() {
        val data = mapOf("username" to "admin", "email" to "admin@example.com", "password" to "short")
        assertNotNull(SetupStepValidator.validate(2, data))
    }

    @Test
    fun `step 2 passes with valid username, email, and password`() {
        val data = mapOf(
            "username" to "adminuser",
            "email"    to "admin@bizarreelectronics.com",
            "password" to "SecurePass123!",
        )
        assertNull(SetupStepValidator.validate(2, data))
    }

    @Test
    fun `step 2 rejects email without domain`() {
        val data = mapOf("username" to "admin", "email" to "admin@nodot", "password" to "password123")
        assertNotNull(SetupStepValidator.validate(2, data))
    }

    // ── (e) Step 3 — Tax classes ─────────────────────────────────────────────

    @Test
    fun `step 3 passes when skipped`() {
        assertNull(SetupStepValidator.validate(3, mapOf("skipped" to "true")))
    }

    @Test
    fun `step 3 passes when tax_classes key present`() {
        assertNull(SetupStepValidator.validate(3, mapOf("tax_classes" to "default")))
    }

    @Test
    fun `step 3 fails with empty data`() {
        assertNotNull(SetupStepValidator.validate(3, emptyMap()))
    }

    // ── (f) Step 4 — Payment methods ─────────────────────────────────────────

    @Test
    fun `step 4 passes when skipped`() {
        assertNull(SetupStepValidator.validate(4, mapOf("skipped" to "true")))
    }

    @Test
    fun `step 4 passes when payment_methods key present`() {
        assertNull(SetupStepValidator.validate(4, mapOf("payment_methods" to "cash,card")))
    }

    @Test
    fun `step 4 fails with empty data`() {
        assertNotNull(SetupStepValidator.validate(4, emptyMap()))
    }

    // ── (g) Steps 5–12 — always valid (skippable) ────────────────────────────

    @Test
    fun `steps 5 through 12 are always valid regardless of data`() {
        for (step in 5..12) {
            assertNull(
                "Step $step should always be valid",
                SetupStepValidator.validate(step, emptyMap()),
            )
            assertNull(
                "Step $step should be valid with skipped=true",
                SetupStepValidator.validate(step, mapOf("skipped" to "true")),
            )
        }
    }

    // ── (h) SetupWizardUiState immutability ──────────────────────────────────

    @Test
    fun `SetupWizardUiState copy produces a new instance`() {
        val original = SetupWizardUiState(currentStep = 0)
        val updated  = original.copy(currentStep = 1)

        assertNotSame("copy() must return a new instance", original, updated)
        assertEquals(0, original.currentStep)
        assertEquals(1, updated.currentStep)
    }

    @Test
    fun `SetupWizardUiState stepData update is immutable`() {
        val original = SetupWizardUiState(stepData = mapOf(0 to mapOf("a" to "b")))
        val newData  = original.stepData + (1 to mapOf("c" to "d"))
        val updated  = original.copy(stepData = newData)

        // Original should not be mutated
        assertEquals(1, original.stepData.size)
        assertEquals(2, updated.stepData.size)
    }
}
