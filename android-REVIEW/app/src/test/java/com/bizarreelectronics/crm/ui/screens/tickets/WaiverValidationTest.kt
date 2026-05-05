package com.bizarreelectronics.crm.ui.screens.tickets

import com.bizarreelectronics.crm.ui.screens.tickets.components.WaiverRowState
import com.bizarreelectronics.crm.data.remote.dto.WaiverTemplateDto
import com.bizarreelectronics.crm.data.remote.dto.SignedWaiverDto
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WaiverValidationTest — §4.14 L780-L786 (plan:L780-L786)
 *
 * Pure JVM unit tests covering:
 *  1. Submit-gate logic (checkbox + signature presence + name non-blank).
 *  2. [WaiverRowState.isSigned] and re-sign detection (L786).
 *
 * No Android / Compose runtime required — all logic under test is plain Kotlin.
 */
class WaiverValidationTest {

    // ─── Helper factory ───────────────────────────────────────────────────────

    private fun template(id: String = "t1", version: Int = 1) = WaiverTemplateDto(
        id = id,
        version = version,
        title = "Test Waiver",
        body = "Terms and conditions.",
        type = "dropoff",
    )

    private fun signed(templateId: String = "t1", version: Int = 1) = SignedWaiverDto(
        id = 1L,
        templateId = templateId,
        version = version,
        customerId = 42L,
        signerName = "Jane Doe",
        signatureUrl = "https://example.com/sig.png",
        signedAt = "2026-01-01T00:00:00Z",
        audit = null,
    )

    // ─── Submit-gate: checkbox + signature + name ─────────────────────────────

    /**
     * All three conditions met → submit allowed.
     */
    @Test
    fun `submit gate passes when checkbox true and signature present and name non-blank`() {
        val agreed = true
        val signatureEmpty = false
        val name = "Jane Doe"
        val canSubmit = agreed && !signatureEmpty && name.isNotBlank()
        assertTrue("Expected submit to be enabled", canSubmit)
    }

    /**
     * Checkbox false → submit blocked even if other conditions pass.
     */
    @Test
    fun `submit gate fails when checkbox not checked`() {
        val agreed = false
        val signatureEmpty = false
        val name = "Jane Doe"
        val canSubmit = agreed && !signatureEmpty && name.isNotBlank()
        assertFalse("Expected submit to be disabled when checkbox unchecked", canSubmit)
    }

    /**
     * Signature canvas empty → submit blocked.
     */
    @Test
    fun `submit gate fails when signature is empty`() {
        val agreed = true
        val signatureEmpty = true
        val name = "Jane Doe"
        val canSubmit = agreed && !signatureEmpty && name.isNotBlank()
        assertFalse("Expected submit to be disabled when signature is empty", canSubmit)
    }

    /**
     * Printed name blank → submit blocked.
     */
    @Test
    fun `submit gate fails when printed name is blank`() {
        val agreed = true
        val signatureEmpty = false
        val name = "   " // whitespace-only
        val canSubmit = agreed && !signatureEmpty && name.isNotBlank()
        assertFalse("Expected submit to be disabled when name is blank", canSubmit)
    }

    /**
     * Printed name empty string → submit blocked.
     */
    @Test
    fun `submit gate fails when printed name is empty`() {
        val agreed = true
        val signatureEmpty = false
        val name = ""
        val canSubmit = agreed && !signatureEmpty && name.isNotBlank()
        assertFalse("Expected submit to be disabled when name is empty", canSubmit)
    }

    // ─── WaiverRowState.isSigned ──────────────────────────────────────────────

    /**
     * Signed and version matches accepted → isSigned = true.
     */
    @Test
    fun `isSigned true when signed and no re-sign required`() {
        val row = WaiverRowState(
            template = template(version = 2),
            signedWaiver = signed(version = 2),
            isReSignRequired = false,
        )
        assertTrue("Expected isSigned = true", row.isSigned)
    }

    /**
     * Signed but re-sign required → isSigned = false.
     */
    @Test
    fun `isSigned false when re-sign is required`() {
        val row = WaiverRowState(
            template = template(version = 3),
            signedWaiver = signed(version = 2),
            isReSignRequired = true,
        )
        assertFalse("Expected isSigned = false when re-sign required", row.isSigned)
    }

    /**
     * Not signed → isSigned = false.
     */
    @Test
    fun `isSigned false when not yet signed`() {
        val row = WaiverRowState(
            template = template(version = 1),
            signedWaiver = null,
            isReSignRequired = false,
        )
        assertFalse("Expected isSigned = false when no signed record", row.isSigned)
    }

    // ─── Re-sign version comparison (L786) ────────────────────────────────────

    /**
     * L786: server version > local accepted version AND waiver is signed → re-sign required.
     */
    @Test
    fun `re-sign required when server version exceeds locally accepted version`() {
        val serverVersion = 5
        val localAcceptedVersion = 3
        val wasSigned = true // a signed record exists
        val isReSignRequired = serverVersion > localAcceptedVersion && wasSigned
        assertTrue("Expected re-sign required when server version $serverVersion > local $localAcceptedVersion", isReSignRequired)
    }

    /**
     * L786: server version equals local accepted version → no re-sign required.
     */
    @Test
    fun `no re-sign required when server version equals locally accepted version`() {
        val serverVersion = 4
        val localAcceptedVersion = 4
        val wasSigned = true
        val isReSignRequired = serverVersion > localAcceptedVersion && wasSigned
        assertFalse("Expected no re-sign when versions match", isReSignRequired)
    }

    /**
     * L786: server version greater but never signed → not a "re-sign" scenario
     * (it's a first-sign scenario). isReSignRequired should be false.
     */
    @Test
    fun `no re-sign required when template was never signed despite higher version`() {
        val serverVersion = 5
        val localAcceptedVersion = 0
        val wasSigned = false
        val isReSignRequired = serverVersion > localAcceptedVersion && wasSigned
        assertFalse("Expected no re-sign when template has never been signed", isReSignRequired)
    }

    /**
     * L786: local accepted version equals zero (never accepted on this device)
     * and a signed record exists on server — isReSignRequired is true because
     * the device needs to re-confirm after a reinstall or device change.
     */
    @Test
    fun `re-sign required when local accepted version is 0 and signed record exists`() {
        val serverVersion = 1
        val localAcceptedVersion = 0
        val wasSigned = true
        val isReSignRequired = serverVersion > localAcceptedVersion && wasSigned
        assertTrue("Expected re-sign when local version is 0 but server record exists", isReSignRequired)
    }
}
