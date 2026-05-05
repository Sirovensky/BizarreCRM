package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.util.ErrorRecovery.Action
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ErrorRecovery] — the AppError → Recovery mapping utility.
 *
 * Coverage (plan §1 L226-L230):
 *  - One test per [AppError] branch
 *  - Title/message non-empty for all non-Cancelled branches
 *  - Actions list order matches spec
 *  - Validation field errors rendered as bullets when fieldErrorsAsBullets=true
 *  - Validation first-error-only when fieldErrorsAsBullets=false
 *  - Server status variants (401, 408, 409, 429, 500, other)
 *  - Auth reason variants (SessionExpired, SessionRevoked, PermissionDenied)
 *  - Storage permission vs disk-full discrimination
 *  - Cancelled produces empty Recovery (silent)
 */
class ErrorRecoveryTest {

    // -------------------------------------------------------------------------
    // Helpers — R is the object singleton; Action imported for enum references
    // -------------------------------------------------------------------------

    private val R = ErrorRecovery

    // -------------------------------------------------------------------------
    // Network branch
    // -------------------------------------------------------------------------

    @Test fun `Network maps to Retry + EnableNetwork actions in order`() {
        val recovery = R.recover(AppError.Network(cause = null))

        assertEquals("Can't reach server", recovery.title)
        assertTrue(recovery.message.isNotBlank())
        assertEquals(listOf(Action.Retry, Action.EnableNetwork), recovery.actions)
        assertFalse(recovery.destructive)
    }

    @Test fun `Network title and message are non-blank`() {
        val recovery = R.recover(AppError.Network(cause = RuntimeException("timeout")))
        assertTrue(recovery.title.isNotBlank())
        assertTrue(recovery.message.isNotBlank())
    }

    // -------------------------------------------------------------------------
    // Server branch — status variants
    // -------------------------------------------------------------------------

    @Test fun `Server 401 maps to ReLogin action (destructive)`() {
        val recovery = R.recover(AppError.Server(401, null, null))

        assertTrue(recovery.title.isNotBlank())
        assertTrue(recovery.message.isNotBlank())
        assertEquals(listOf(Action.ReLogin), recovery.actions)
        assertTrue(recovery.destructive)
    }

    @Test fun `Server 403 maps to ReLogin action (destructive)`() {
        val recovery = R.recover(AppError.Server(403, null, null))

        assertEquals(listOf(Action.ReLogin), recovery.actions)
        assertTrue(recovery.destructive)
    }

    @Test fun `Server 408 maps to Retry action`() {
        val recovery = R.recover(AppError.Server(408, null, null))

        assertEquals("Server timeout", recovery.title)
        assertEquals(listOf(Action.Retry), recovery.actions)
        assertFalse(recovery.destructive)
    }

    @Test fun `Server 504 maps to Retry action`() {
        val recovery = R.recover(AppError.Server(504, null, null))

        assertEquals(listOf(Action.Retry), recovery.actions)
    }

    @Test fun `Server 409 maps to Retry + Dismiss actions in order`() {
        val recovery = R.recover(AppError.Server(409, null, null))

        assertEquals("Conflicting changes", recovery.title)
        assertEquals(listOf(Action.Retry, Action.Dismiss), recovery.actions)
    }

    @Test fun `Server 429 maps to Retry action with cooldown hint`() {
        val recovery = R.recover(AppError.Server(429, "Please retry after 30 seconds", null))

        assertEquals("Too many attempts", recovery.title)
        assertTrue("message should reference retry hint", recovery.message.contains("retry", ignoreCase = true))
        assertEquals(listOf(Action.Retry), recovery.actions)
    }

    @Test fun `Server 429 without Retry-After hint still shows Retry action`() {
        val recovery = R.recover(AppError.Server(429, null, null))

        assertEquals(listOf(Action.Retry), recovery.actions)
        assertTrue(recovery.message.isNotBlank())
    }

    @Test fun `Server 500 maps to Retry + ContactSupport actions in order`() {
        val recovery = R.recover(AppError.Server(500, "Internal Server Error", null))

        assertEquals("Server error", recovery.title)
        assertEquals(listOf(Action.Retry, Action.ContactSupport), recovery.actions)
    }

    @Test fun `Server 503 maps to Retry + ContactSupport (5xx range)`() {
        val recovery = R.recover(AppError.Server(503, null, null))

        assertEquals(listOf(Action.Retry, Action.ContactSupport), recovery.actions)
    }

    @Test fun `Server other status maps to Retry + Dismiss`() {
        val recovery = R.recover(AppError.Server(418, null, null))

        assertEquals("Request failed", recovery.title)
        assertEquals(listOf(Action.Retry, Action.Dismiss), recovery.actions)
    }

    // -------------------------------------------------------------------------
    // Auth branch — reason variants
    // -------------------------------------------------------------------------

    @Test fun `Auth SessionExpired maps to ReLogin (destructive)`() {
        val recovery = R.recover(AppError.Auth(AppError.AuthReason.SessionExpired))

        assertEquals("Session expired", recovery.title)
        assertTrue(recovery.message.isNotBlank())
        assertEquals(listOf(Action.ReLogin), recovery.actions)
        assertTrue(recovery.destructive)
    }

    @Test fun `Auth SessionRevoked maps to ReLogin (destructive)`() {
        val recovery = R.recover(AppError.Auth(AppError.AuthReason.SessionRevoked))

        assertEquals("Session ended", recovery.title)
        assertEquals(listOf(Action.ReLogin), recovery.actions)
        assertTrue(recovery.destructive)
    }

    @Test fun `Auth PermissionDenied maps to OpenSettings + Dismiss (not destructive)`() {
        val recovery = R.recover(AppError.Auth(AppError.AuthReason.PermissionDenied))

        assertEquals("Access denied", recovery.title)
        assertEquals(listOf(Action.OpenSettings, Action.Dismiss), recovery.actions)
        assertFalse(recovery.destructive)
    }

    // -------------------------------------------------------------------------
    // Validation branch
    // -------------------------------------------------------------------------

    @Test fun `Validation with fieldErrors renders bullets when fieldErrorsAsBullets=true`() {
        val errors = listOf(
            AppError.FieldError("email", "must be valid"),
            AppError.FieldError("phone", "too short"),
        )
        val recovery = R.recover(AppError.Validation(errors), fieldErrorsAsBullets = true)

        assertEquals("Check your inputs", recovery.title)
        assertTrue("message should contain bullet", recovery.message.contains("\u2022"))
        assertTrue(recovery.message.contains("email"))
        assertTrue(recovery.message.contains("phone"))
        assertEquals(listOf(Action.Dismiss), recovery.actions)
    }

    @Test fun `Validation renders each error as bullet line`() {
        val errors = listOf(
            AppError.FieldError("name", "is required"),
            AppError.FieldError("amount", "must be positive"),
        )
        val recovery = R.recover(AppError.Validation(errors), fieldErrorsAsBullets = true)

        val lines = recovery.message.lines()
        assertEquals(2, lines.size)
        assertTrue(lines[0].startsWith("\u2022"))
        assertTrue(lines[1].startsWith("\u2022"))
    }

    @Test fun `Validation with fieldErrorsAsBullets=false returns first error message only`() {
        val errors = listOf(
            AppError.FieldError("zip", "invalid format"),
            AppError.FieldError("city", "required"),
        )
        val recovery = R.recover(AppError.Validation(errors), fieldErrorsAsBullets = false)

        assertEquals("invalid format", recovery.message)
        assertFalse("should not contain bullet", recovery.message.contains("\u2022"))
    }

    @Test fun `Validation with empty errors returns fallback message`() {
        val recovery = R.recover(AppError.Validation(emptyList()))

        assertEquals("Check your inputs", recovery.title)
        assertTrue(recovery.message.isNotBlank())
        assertEquals(listOf(Action.Dismiss), recovery.actions)
    }

    // -------------------------------------------------------------------------
    // NotFound branch
    // -------------------------------------------------------------------------

    @Test fun `NotFound includes entity name in title`() {
        val recovery = R.recover(AppError.NotFound(entity = "ticket", id = "42"))

        assertTrue(
            "title should mention 'ticket', got: ${recovery.title}",
            recovery.title.lowercase().contains("ticket"),
        )
        assertTrue(recovery.message.isNotBlank())
        assertEquals(listOf(Action.Dismiss), recovery.actions)
    }

    @Test fun `NotFound with null id still produces non-blank title and message`() {
        val recovery = R.recover(AppError.NotFound(entity = "customer", id = null))

        assertTrue(recovery.title.isNotBlank())
        assertTrue(recovery.message.isNotBlank())
    }

    // -------------------------------------------------------------------------
    // Conflict branch
    // -------------------------------------------------------------------------

    @Test fun `Conflict maps to Retry + Dismiss actions in order`() {
        val recovery = R.recover(AppError.Conflict(serverUpdatedAt = null))

        assertEquals("Conflict detected", recovery.title)
        assertEquals(listOf(Action.Retry, Action.Dismiss), recovery.actions)
    }

    @Test fun `Conflict with serverUpdatedAt includes timestamp in message`() {
        val recovery = R.recover(AppError.Conflict(serverUpdatedAt = "2026-04-23T12:00:00Z"))

        assertTrue(
            "message should include timestamp",
            recovery.message.contains("2026-04-23T12:00:00Z"),
        )
    }

    // -------------------------------------------------------------------------
    // Storage branch
    // -------------------------------------------------------------------------

    @Test fun `Storage disk-full reason maps to FreeStorage + Dismiss`() {
        val recovery = R.recover(AppError.Storage(reason = "No space left on device"))

        assertEquals("Out of storage", recovery.title)
        assertEquals(listOf(Action.FreeStorage, Action.Dismiss), recovery.actions)
    }

    @Test fun `Storage permission-denied reason maps to OpenSettings + Dismiss`() {
        val recovery = R.recover(AppError.Storage(reason = "Permission denied"))

        assertEquals("Storage permission denied", recovery.title)
        assertEquals(listOf(Action.OpenSettings, Action.Dismiss), recovery.actions)
    }

    @Test fun `Storage access-denied variant maps to OpenSettings`() {
        val recovery = R.recover(AppError.Storage(reason = "Access denied to external storage"))
        assertEquals(listOf(Action.OpenSettings, Action.Dismiss), recovery.actions)
    }

    // -------------------------------------------------------------------------
    // Hardware branch
    // -------------------------------------------------------------------------

    @Test fun `Hardware maps to OpenSettings + Dismiss in order`() {
        val recovery = R.recover(AppError.Hardware(device = "Camera", reason = "blocked by another app"))

        assertEquals("Hardware unavailable", recovery.title)
        assertTrue(recovery.message.contains("Camera"))
        assertEquals(listOf(Action.OpenSettings, Action.Dismiss), recovery.actions)
    }

    @Test fun `Hardware title and message are non-blank`() {
        val recovery = R.recover(AppError.Hardware(device = "Barcode scanner", reason = "not found"))
        assertTrue(recovery.title.isNotBlank())
        assertTrue(recovery.message.isNotBlank())
    }

    // -------------------------------------------------------------------------
    // Cancelled branch — silent
    // -------------------------------------------------------------------------

    @Test fun `Cancelled produces empty title, empty message, and empty actions`() {
        val recovery = R.recover(AppError.Cancelled)

        assertEquals("", recovery.title)
        assertEquals("", recovery.message)
        assertTrue(recovery.actions.isEmpty())
    }

    // -------------------------------------------------------------------------
    // Unknown branch
    // -------------------------------------------------------------------------

    @Test fun `Unknown maps to Retry + ContactSupport actions in order`() {
        val recovery = R.recover(AppError.Unknown(cause = null))

        assertEquals("Something went wrong", recovery.title)
        assertTrue(recovery.message.isNotBlank())
        assertEquals(listOf(Action.Retry, Action.ContactSupport), recovery.actions)
    }

    @Test fun `Unknown with cause still has non-blank title and message`() {
        val recovery = R.recover(AppError.Unknown(cause = RuntimeException("edge case")))
        assertTrue(recovery.title.isNotBlank())
        assertTrue(recovery.message.isNotBlank())
    }

    // -------------------------------------------------------------------------
    // Cross-branch: title+message non-blank for every non-Cancelled branch
    // -------------------------------------------------------------------------

    @Test fun `every non-Cancelled branch has non-blank title and message`() {
        val errors = listOf(
            AppError.Network(null),
            AppError.Server(500, "boom", null),
            AppError.Auth(AppError.AuthReason.SessionExpired),
            AppError.Auth(AppError.AuthReason.SessionRevoked),
            AppError.Auth(AppError.AuthReason.PermissionDenied),
            AppError.Validation(listOf(AppError.FieldError("f", "msg"))),
            AppError.NotFound("invoice", "99"),
            AppError.Conflict(null),
            AppError.Storage("disk full"),
            AppError.Hardware("printer", "jammed"),
            AppError.Unknown(null),
        )

        errors.forEach { err ->
            val recovery = R.recover(err)
            assertTrue(
                "${err::class.simpleName} should have non-blank title, got '${recovery.title}'",
                recovery.title.isNotBlank(),
            )
            assertTrue(
                "${err::class.simpleName} should have non-blank message, got '${recovery.message}'",
                recovery.message.isNotBlank(),
            )
        }
    }

    // -------------------------------------------------------------------------
    // Recovery data class — immutability / copy semantics
    // -------------------------------------------------------------------------

    @Test fun `Recovery copy produces a new instance with modified field`() {
        val original = R.recover(AppError.Network(null))
        val modified = original.copy(title = "Custom title")

        assertEquals("Custom title", modified.title)
        assertEquals(original.message, modified.message)
        assertEquals(original.actions, modified.actions)
        // original is unmodified
        assertEquals("Can't reach server", original.title)
    }
}
