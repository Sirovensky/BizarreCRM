package com.bizarreelectronics.crm.ui.components

import com.bizarreelectronics.crm.util.AppError
import com.bizarreelectronics.crm.util.ErrorRecovery
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit tests for the pure helpers in [ErrorSurface] (ActionPlan §1 L230).
 *
 * These tests do NOT require a Compose or Android environment — they exercise:
 *   - [actionLabel] label-mapping helper
 *   - [iconForError] icon-mapping helper
 *   - [ErrorRecovery.recover] contract for the Cancelled branch (empty actions)
 *   - Button ordering (primary first, Dismiss last) via Recovery.actions
 *   - Destructive flag propagation via Recovery.destructive
 */
class ErrorSurfaceTest {

    // -------------------------------------------------------------------------
    // Action label mapping
    // -------------------------------------------------------------------------

    @Test
    fun `actionLabel maps Retry`() {
        assertEquals("Retry", actionLabel(ErrorRecovery.Action.Retry))
    }

    @Test
    fun `actionLabel maps EnableNetwork`() {
        assertEquals("Enable network", actionLabel(ErrorRecovery.Action.EnableNetwork))
    }

    @Test
    fun `actionLabel maps ReLogin`() {
        assertEquals("Sign in again", actionLabel(ErrorRecovery.Action.ReLogin))
    }

    @Test
    fun `actionLabel maps OpenSettings`() {
        assertEquals("Open settings", actionLabel(ErrorRecovery.Action.OpenSettings))
    }

    @Test
    fun `actionLabel maps ContactSupport`() {
        assertEquals("Contact support", actionLabel(ErrorRecovery.Action.ContactSupport))
    }

    @Test
    fun `actionLabel maps Dismiss`() {
        assertEquals("Dismiss", actionLabel(ErrorRecovery.Action.Dismiss))
    }

    @Test
    fun `actionLabel maps FreeStorage`() {
        assertEquals("Free up space", actionLabel(ErrorRecovery.Action.FreeStorage))
    }

    @Test
    fun `actionLabel maps AdjustTime`() {
        assertEquals("Adjust date & time", actionLabel(ErrorRecovery.Action.AdjustTime))
    }

    // -------------------------------------------------------------------------
    // Cancelled branch → empty actions → ErrorSurface renders nothing
    // -------------------------------------------------------------------------

    @Test
    fun `errorSurface renders nothing for Cancelled - recovery has empty actions`() {
        val recovery = ErrorRecovery.recover(AppError.Cancelled)
        assertTrue(
            "Cancelled error must produce empty actions so ErrorSurface returns early",
            recovery.actions.isEmpty(),
        )
    }

    // -------------------------------------------------------------------------
    // Button order: primary (non-Dismiss) first, Dismiss last
    // -------------------------------------------------------------------------

    @Test
    fun `action button order - Network recovery puts Retry before EnableNetwork`() {
        val recovery = ErrorRecovery.recover(AppError.Network(cause = null))
        // Network → [Retry, EnableNetwork] — no Dismiss in this recovery
        val first = recovery.actions.first()
        assertEquals(
            "First action must not be Dismiss",
            ErrorRecovery.Action.Retry,
            first,
        )
    }

    @Test
    fun `action button order - Unknown recovery has no Dismiss`() {
        val recovery = ErrorRecovery.recover(AppError.Unknown(cause = null))
        // Unknown → [Retry, ContactSupport]
        val containsDismiss = ErrorRecovery.Action.Dismiss in recovery.actions
        assertTrue("Unknown recovery should not contain Dismiss", !containsDismiss)
    }

    @Test
    fun `action button order - Dismiss not first when other actions present`() {
        // Auth(PermissionDenied) → [OpenSettings, Dismiss]
        val recovery = ErrorRecovery.recover(AppError.Auth(AppError.AuthReason.PermissionDenied))
        val hasNonDismissFirst = recovery.actions.isNotEmpty() &&
            recovery.actions.first() != ErrorRecovery.Action.Dismiss
        assertTrue(
            "When Dismiss is present alongside other actions, it must not be first",
            hasNonDismissFirst,
        )
        // Dismiss must be the last element
        assertEquals(
            "Dismiss must be last in PermissionDenied recovery",
            ErrorRecovery.Action.Dismiss,
            recovery.actions.last(),
        )
    }

    @Test
    fun `action button order - Validation recovery Dismiss is the only action`() {
        val recovery = ErrorRecovery.recover(AppError.Validation(errors = emptyList()))
        assertEquals(1, recovery.actions.size)
        assertEquals(ErrorRecovery.Action.Dismiss, recovery.actions.first())
    }

    // -------------------------------------------------------------------------
    // Destructive recovery flag
    // -------------------------------------------------------------------------

    @Test
    fun `destructive recovery - Auth SessionExpired sets destructive true`() {
        val recovery = ErrorRecovery.recover(AppError.Auth(AppError.AuthReason.SessionExpired))
        assertTrue(
            "SessionExpired recovery must be destructive (forced sign-out)",
            recovery.destructive,
        )
    }

    @Test
    fun `destructive recovery - Auth SessionRevoked sets destructive true`() {
        val recovery = ErrorRecovery.recover(AppError.Auth(AppError.AuthReason.SessionRevoked))
        assertTrue(recovery.destructive)
    }

    @Test
    fun `destructive recovery - Network is not destructive`() {
        val recovery = ErrorRecovery.recover(AppError.Network(cause = null))
        assertTrue("Network recovery must not be destructive", !recovery.destructive)
    }

    @Test
    fun `destructive recovery - Server 401 sets destructive true`() {
        val recovery = ErrorRecovery.recover(AppError.Server(status = 401, serverMessage = null, requestId = null))
        assertTrue(
            "Server 401 forces sign-out and must be destructive",
            recovery.destructive,
        )
    }

    // -------------------------------------------------------------------------
    // Icon mapping — non-null assertions (no Compose runtime needed)
    // -------------------------------------------------------------------------

    @Test
    fun `iconForError - Network maps to WifiOff`() {
        val icon = iconForError(AppError.Network(cause = null))
        assertEquals("WifiOff", icon.name)
    }

    @Test
    fun `iconForError - Auth maps to Lock`() {
        val icon = iconForError(AppError.Auth(AppError.AuthReason.SessionExpired))
        assertEquals("Lock", icon.name)
    }

    @Test
    fun `iconForError - Server maps to CloudOff`() {
        val icon = iconForError(AppError.Server(status = 500, serverMessage = null, requestId = null))
        assertEquals("CloudOff", icon.name)
    }

    @Test
    fun `iconForError - Unknown maps to Error`() {
        val icon = iconForError(AppError.Unknown(cause = null))
        assertEquals("Error", icon.name)
    }
}
