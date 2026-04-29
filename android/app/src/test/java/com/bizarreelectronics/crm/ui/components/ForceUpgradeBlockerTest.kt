package com.bizarreelectronics.crm.ui.components

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit tests for [isUpgradeRequired] (ActionPlan §28.9).
 *
 * These tests exercise the pure gate predicate without a Compose or Android
 * runtime.  The [ForceUpgradeBlocker] composable delegates to this function,
 * so the branching logic is fully covered here.
 *
 * ## Contract under test
 * ```
 * isUpgradeRequired(serverMinVersion, currentVersion) →
 *   true   when serverMinVersion != null && currentVersion < serverMinVersion
 *   false  otherwise (null server floor, equal, or current > server floor)
 * ```
 */
class ForceUpgradeBlockerTest {

    // -------------------------------------------------------------------------
    // No upgrade required
    // -------------------------------------------------------------------------

    @Test
    fun `returns false when server min version is null`() {
        assertFalse(isUpgradeRequired(serverMinVersion = null, currentVersion = 10))
    }

    @Test
    fun `returns false when current version equals server min version`() {
        assertFalse(isUpgradeRequired(serverMinVersion = 42, currentVersion = 42))
    }

    @Test
    fun `returns false when current version is greater than server min version`() {
        assertFalse(isUpgradeRequired(serverMinVersion = 5, currentVersion = 10))
    }

    @Test
    fun `returns false when current version is one above server min version`() {
        assertFalse(isUpgradeRequired(serverMinVersion = 99, currentVersion = 100))
    }

    @Test
    fun `returns false when server min version is null and current is zero`() {
        assertFalse(isUpgradeRequired(serverMinVersion = null, currentVersion = 0))
    }

    // -------------------------------------------------------------------------
    // Upgrade required
    // -------------------------------------------------------------------------

    @Test
    fun `returns true when current version is below server min version`() {
        assertTrue(isUpgradeRequired(serverMinVersion = 20, currentVersion = 10))
    }

    @Test
    fun `returns true when current version is one below server min version`() {
        assertTrue(isUpgradeRequired(serverMinVersion = 11, currentVersion = 10))
    }

    @Test
    fun `returns true when current version is zero and server min is one`() {
        assertTrue(isUpgradeRequired(serverMinVersion = 1, currentVersion = 0))
    }

    @Test
    fun `returns true for large version gap`() {
        assertTrue(isUpgradeRequired(serverMinVersion = 1_000_000, currentVersion = 1))
    }

    // -------------------------------------------------------------------------
    // Boundary: Int.MAX_VALUE cases
    // -------------------------------------------------------------------------

    @Test
    fun `returns false when both versions are Int MAX VALUE`() {
        assertFalse(
            isUpgradeRequired(
                serverMinVersion = Int.MAX_VALUE,
                currentVersion = Int.MAX_VALUE,
            ),
        )
    }

    @Test
    fun `returns true when current is MAX minus one and server is MAX`() {
        assertTrue(
            isUpgradeRequired(
                serverMinVersion = Int.MAX_VALUE,
                currentVersion = Int.MAX_VALUE - 1,
            ),
        )
    }
}
