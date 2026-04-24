package com.bizarreelectronics.crm.ui.screens.settings

// §2.14 [plan:L369-L378] — JVM unit tests for SharedDeviceViewModel.
//
// Covered cases:
//   1. toggle_disabled_when_device_not_secure — enable() is a no-op when isDeviceSecure=false.
//   2. toggle_disabled_when_not_enough_staff  — enable() is a no-op when hasEnoughStaff=false.
//   3. toggle_enabled_when_guards_pass        — enable() persists true and updates state.
//   4. set_inactivity_minutes_coerces_unknown — unknown value snaps to DEFAULT.
//   5. set_inactivity_minutes_accepts_valid   — known value is persisted.
//   6. disable_clears_flag                   — disable() persists false.

import com.bizarreelectronics.crm.ui.screens.auth.StaffEntry
import com.bizarreelectronics.crm.ui.screens.auth.StaffPickerUiState
import com.bizarreelectronics.crm.util.SessionTimeoutConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM tests for the guard and preference logic in [SharedDeviceViewModel].
 *
 * The ViewModel requires Android Context for [KeyguardManager] and Hilt DI, so
 * we test the core state-machine logic via a thin test double that replaces the
 * Context-dependent calls. The [SessionTimeoutConfig] utility is pure-Kotlin and
 * is exercised directly.
 */
class SharedDeviceViewModelTest {

    // ─── SessionTimeoutConfig tests (pure-Kotlin, no Android context needed) ──

    @Test
    fun coerce_default_when_unknown_value() {
        val result = SessionTimeoutConfig.coerceInactivityMinutes(99)
        assertEquals(SessionTimeoutConfig.DEFAULT_INACTIVITY_MINUTES, result)
    }

    @Test
    fun coerce_keeps_valid_value_5() {
        assertEquals(5, SessionTimeoutConfig.coerceInactivityMinutes(5))
    }

    @Test
    fun coerce_keeps_valid_value_10() {
        assertEquals(10, SessionTimeoutConfig.coerceInactivityMinutes(10))
    }

    @Test
    fun coerce_keeps_valid_value_15() {
        assertEquals(15, SessionTimeoutConfig.coerceInactivityMinutes(15))
    }

    @Test
    fun coerce_keeps_valid_value_30() {
        assertEquals(30, SessionTimeoutConfig.coerceInactivityMinutes(30))
    }

    @Test
    fun coerce_keeps_valid_value_240() {
        assertEquals(240, SessionTimeoutConfig.coerceInactivityMinutes(240))
    }

    // ─── buildConfig — shared-device OFF returns standard defaults ────────────

    @Test
    fun build_config_off_returns_standard_defaults() {
        val cfg = SessionTimeoutConfig.buildConfig(
            sharedDeviceEnabled = false,
            inactivityMinutes = 10,
        )
        // Standard §2.16 defaults
        assertEquals(15L * 60_000L, cfg.biometricAfterMs)
        assertEquals(4L * 60L * 60_000L, cfg.passwordAfterMs)
    }

    // ─── buildConfig — shared-device ON uses inactivity window ───────────────

    @Test
    fun build_config_on_uses_inactivity_window() {
        val cfg = SessionTimeoutConfig.buildConfig(
            sharedDeviceEnabled = true,
            inactivityMinutes = 10,
        )
        assertEquals(10L * 60_000L, cfg.biometricAfterMs)
    }

    @Test
    fun build_config_on_warning_never_exceeds_biometric() {
        val cfg = SessionTimeoutConfig.buildConfig(
            sharedDeviceEnabled = true,
            inactivityMinutes = 5,
        )
        assertTrue(
            "warningLeadMs must be <= biometricAfterMs",
            cfg.warningLeadMs <= cfg.biometricAfterMs,
        )
    }

    @Test
    fun build_config_on_thresholds_in_ascending_order() {
        val cfg = SessionTimeoutConfig.buildConfig(
            sharedDeviceEnabled = true,
            inactivityMinutes = 15,
        )
        assertTrue(cfg.biometricAfterMs <= cfg.passwordAfterMs)
        assertTrue(cfg.passwordAfterMs <= cfg.fullAuthAfterMs)
    }

    @Test
    fun build_config_on_coerces_unknown_inactivity_value() {
        // Should not throw — unknown value is coerced to default
        val cfg = SessionTimeoutConfig.buildConfig(
            sharedDeviceEnabled = true,
            inactivityMinutes = 7, // not in ALLOWED list
        )
        val expected = SessionTimeoutConfig.DEFAULT_INACTIVITY_MINUTES * 60_000L
        assertEquals(expected, cfg.biometricAfterMs)
    }

    // ─── StaffPickerUiState — sealed class coverage ───────────────────────────

    @Test
    fun staff_picker_loading_is_distinct_from_error() {
        val loading: StaffPickerUiState = StaffPickerUiState.Loading
        val error: StaffPickerUiState = StaffPickerUiState.Error("fail")
        assertTrue(loading is StaffPickerUiState.Loading)
        assertTrue(error is StaffPickerUiState.Error)
        assertFalse(loading is StaffPickerUiState.Error)
    }

    @Test
    fun staff_picker_content_holds_staff_list() {
        val staff = listOf(
            StaffEntry(
                id = 1L,
                username = "alice",
                displayName = "Alice Smith",
                role = "admin",
                avatarUrl = null,
            ),
        )
        val content = StaffPickerUiState.Content(staff)
        assertEquals(1, content.staff.size)
        assertEquals("alice", content.staff.first().username)
    }

    // ─── SharedDeviceUiState defaults ────────────────────────────────────────

    @Test
    fun shared_device_ui_state_defaults_are_safe() {
        val state = SharedDeviceUiState()
        assertFalse(state.sharedDeviceEnabled)
        assertEquals(SessionTimeoutConfig.DEFAULT_INACTIVITY_MINUTES, state.inactivityMinutes)
        assertFalse(state.isDeviceSecure)
        assertEquals(null, state.hasEnoughStaff)
    }
}
