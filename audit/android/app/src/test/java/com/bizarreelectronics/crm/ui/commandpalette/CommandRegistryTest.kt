package com.bizarreelectronics.crm.ui.commandpalette

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §54 — Unit tests for [CommandRegistry].
 *
 * Verifies:
 *  1. Static command list is non-empty and has unique IDs.
 *  2. Blank query returns all non-admin commands when isAdmin=false.
 *  3. Blank query returns all commands (incl. admin-only) when isAdmin=true.
 *  4. Admin-only commands are excluded when isAdmin=false.
 *  5. Search by label substring works case-insensitively.
 *  6. Search by keyword works.
 *  7. Dynamic commands are merged and searchable.
 *  8. Results are capped at 20.
 *  9. Results are grouped in display order (NAVIGATION → ACTIONS → RECENT).
 */
class CommandRegistryTest {

    // ── 1. Static list sanity ─────────────────────────────────────────────────

    @Test
    fun `staticCommands is non-empty`() {
        assertTrue(CommandRegistry.staticCommands.isNotEmpty())
    }

    @Test
    fun `staticCommands has unique IDs`() {
        val ids = CommandRegistry.staticCommands.map { it.id }
        assertEquals("Duplicate command IDs found", ids.distinct().size, ids.size)
    }

    // ── 2. Blank query, non-admin ────────────────────────────────────────────

    @Test
    fun `blank query returns non-admin commands when not admin`() {
        val results = CommandRegistry.search(query = "", isAdmin = false)
        assertTrue(results.isNotEmpty())
        results.forEach { cmd ->
            assertFalse("Admin-only command should be excluded: ${cmd.id}", cmd.adminOnly)
        }
    }

    // ── 3. Blank query, admin ─────────────────────────────────────────────────

    @Test
    fun `blank query returns admin commands when isAdmin=true`() {
        val results = CommandRegistry.search(query = "", isAdmin = true)
        val adminCmds = CommandRegistry.staticCommands.filter { it.adminOnly }
        adminCmds.forEach { adminCmd ->
            assertTrue(
                "Admin command ${adminCmd.id} should appear for admin",
                results.any { it.id == adminCmd.id },
            )
        }
    }

    // ── 4. Admin gate ─────────────────────────────────────────────────────────

    @Test
    fun `adminOnly commands hidden from non-admin`() {
        val adminOnlyIds = CommandRegistry.staticCommands
            .filter { it.adminOnly }
            .map { it.id }

        if (adminOnlyIds.isEmpty()) return // No admin-only commands yet — vacuously pass.

        val results = CommandRegistry.search(query = "", isAdmin = false)
        val resultIds = results.map { it.id }
        adminOnlyIds.forEach { id ->
            assertFalse("Admin-only command $id should not appear for non-admin", id in resultIds)
        }
    }

    // ── 5. Label search ────────────────────────────────────────────────────────

    @Test
    fun `search by label substring is case-insensitive`() {
        val results = CommandRegistry.search(query = "tickets", isAdmin = false)
        assertTrue("Expected 'Go to Tickets' in results", results.any { it.label.contains("Tickets", ignoreCase = true) })
    }

    @Test
    fun `search by label 'new' returns action commands`() {
        val results = CommandRegistry.search(query = "new", isAdmin = false)
        assertTrue(results.any { it.group == CommandGroup.ACTIONS })
    }

    // ── 6. Keyword search ─────────────────────────────────────────────────────

    @Test
    fun `search by keyword finds commands without that word in label`() {
        // "repairs" is a keyword for Go to Tickets, not in the label
        val results = CommandRegistry.search(query = "repairs", isAdmin = false)
        assertTrue(
            "Expected ticket nav command via keyword 'repairs'",
            results.any { it.id == "nav:tickets" },
        )
    }

    @Test
    fun `search by keyword scan finds scanner command`() {
        val results = CommandRegistry.search(query = "scan", isAdmin = false)
        assertTrue(results.any { it.id == "action:scan-barcode" })
    }

    // ── 7. Dynamic commands merged ───────────────────────────────────────────

    @Test
    fun `dynamic commands are included in search results`() {
        val dynamic = listOf(
            Command(
                id = "recent:ticket:42",
                label = "Ticket #42 — iPhone screen",
                group = CommandGroup.RECENT,
                route = "tickets/42",
                keywords = listOf("iphone", "screen"),
            ),
        )
        val results = CommandRegistry.search(query = "iphone", isAdmin = false, dynamicCommands = dynamic)
        assertTrue("Dynamic command should appear in results", results.any { it.id == "recent:ticket:42" })
    }

    @Test
    fun `dynamic admin-only commands hidden from non-admin`() {
        val dynamic = listOf(
            Command(
                id = "dynamic:admin-report",
                label = "Admin Only Report",
                group = CommandGroup.ACTIONS,
                route = "reports/admin",
                adminOnly = true,
            ),
        )
        val results = CommandRegistry.search(query = "Admin Only", isAdmin = false, dynamicCommands = dynamic)
        assertFalse(results.any { it.id == "dynamic:admin-report" })
    }

    // ── 8. Result cap ─────────────────────────────────────────────────────────

    @Test
    fun `results are capped at 20`() {
        // Generate 30 dummy commands
        val dynamic = (1..30).map { i ->
            Command(
                id = "dyn:$i",
                label = "Dynamic Command $i",
                group = CommandGroup.ACTIONS,
                route = "route/$i",
            )
        }
        val results = CommandRegistry.search(query = "", isAdmin = true, dynamicCommands = dynamic)
        assertTrue("Results should not exceed 20", results.size <= 20)
    }

    // ── 9. Group order ────────────────────────────────────────────────────────

    @Test
    fun `results are ordered NAVIGATION then ACTIONS then RECENT`() {
        val dynamic = listOf(
            Command(
                id = "recent:x",
                label = "A recent item",
                group = CommandGroup.RECENT,
                route = "somewhere",
            ),
        )
        val results = CommandRegistry.search(query = "", isAdmin = false, dynamicCommands = dynamic)
        if (results.size < 2) return

        val groupOrder = results.map { it.group.ordinal }
        for (i in 0 until groupOrder.size - 1) {
            assertTrue(
                "Group order violated at index $i: ${groupOrder[i]} > ${groupOrder[i + 1]}",
                groupOrder[i] <= groupOrder[i + 1],
            )
        }
    }
}
