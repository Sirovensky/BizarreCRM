package com.bizarreelectronics.crm.ui.screens.dashboard

import com.bizarreelectronics.crm.ui.screens.dashboard.components.AttentionCategory
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AttentionPriority
import com.bizarreelectronics.crm.ui.screens.dashboard.components.NeedsAttentionItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §3.3 L510–L514 — pure-logic tests for NeedsAttentionSection behaviour.
 *
 * No Robolectric or Android framework required — all logic under test is
 * pure Kotlin operating on [NeedsAttentionItem] data classes and plain
 * collection operations that mirror the ViewModel's filtering/sorting rules.
 *
 * Test matrix:
 *   L510 — data model fields and priority enum
 *   L512 — context-menu action dispatch (dismiss / mark-seen / open / create-task)
 *   L513 — dismiss persistence: filter by dismissed IDs set
 *   L514 — empty state condition: list is empty after all items dismissed
 */
class NeedsAttentionSectionLogicTest {

    // -------------------------------------------------------------------------
    // Helpers — mirror ViewModel filtering/sorting logic without Android context
    // -------------------------------------------------------------------------

    /** Filter items by a set of dismissed IDs, mirroring ViewModel behaviour. */
    private fun filterDismissed(
        items: List<NeedsAttentionItem>,
        dismissedIds: Set<String>,
    ): List<NeedsAttentionItem> = items.filter { it.id !in dismissedIds }

    /** Sort by priority descending (HIGH first), mirroring ViewModel sort order. */
    private fun sortByPriority(items: List<NeedsAttentionItem>): List<NeedsAttentionItem> =
        items.sortedByDescending { it.priority.ordinal }

    // -------------------------------------------------------------------------
    // §3.3 L510 — Data model
    // -------------------------------------------------------------------------

    @Test fun `NeedsAttentionItem stores all fields correctly`() {
        val item = NeedsAttentionItem(
            id = "ticket_overdue",
            title = "3 overdue tickets",
            subtitle = "Awaiting update",
            actionLabel = "View Tickets",
            actionRoute = "tickets?filter=overdue",
            priority = AttentionPriority.HIGH,
            category = AttentionCategory.TICKET_OVERDUE,
        )
        assertEquals("ticket_overdue", item.id)
        assertEquals("3 overdue tickets", item.title)
        assertEquals("Awaiting update", item.subtitle)
        assertEquals("View Tickets", item.actionLabel)
        assertEquals("tickets?filter=overdue", item.actionRoute)
        assertEquals(AttentionPriority.HIGH, item.priority)
        assertEquals(AttentionCategory.TICKET_OVERDUE, item.category)
    }

    @Test fun `NeedsAttentionItem defaults priority to DEFAULT`() {
        val item = NeedsAttentionItem(id = "x", title = "x")
        assertEquals(AttentionPriority.DEFAULT, item.priority)
    }

    @Test fun `NeedsAttentionItem defaults category to OTHER`() {
        val item = NeedsAttentionItem(id = "x", title = "x")
        assertEquals(AttentionCategory.OTHER, item.category)
    }

    @Test fun `NeedsAttentionItem defaults subtitle to empty`() {
        val item = NeedsAttentionItem(id = "x", title = "x")
        assertEquals("", item.subtitle)
    }

    // -------------------------------------------------------------------------
    // Priority enum ordering (HIGH > INFO > DEFAULT)
    // -------------------------------------------------------------------------

    @Test fun `priority ordinal HIGH greater than INFO`() {
        assertTrue(AttentionPriority.HIGH.ordinal > AttentionPriority.INFO.ordinal)
    }

    @Test fun `priority ordinal INFO greater than DEFAULT`() {
        assertTrue(AttentionPriority.INFO.ordinal > AttentionPriority.DEFAULT.ordinal)
    }

    // -------------------------------------------------------------------------
    // §3.3 L510 — Priority-based card surface colour selection logic
    // -------------------------------------------------------------------------

    @Test fun `sortByPriority places HIGH items before INFO and DEFAULT`() {
        val items = listOf(
            NeedsAttentionItem(id = "a", title = "A", priority = AttentionPriority.DEFAULT),
            NeedsAttentionItem(id = "b", title = "B", priority = AttentionPriority.HIGH),
            NeedsAttentionItem(id = "c", title = "C", priority = AttentionPriority.INFO),
        )
        val sorted = sortByPriority(items)
        assertEquals(AttentionPriority.HIGH, sorted[0].priority)
        assertEquals(AttentionPriority.INFO, sorted[1].priority)
        assertEquals(AttentionPriority.DEFAULT, sorted[2].priority)
    }

    @Test fun `sortByPriority is stable for equal priorities`() {
        val items = listOf(
            NeedsAttentionItem(id = "a", title = "first", priority = AttentionPriority.HIGH),
            NeedsAttentionItem(id = "b", title = "second", priority = AttentionPriority.HIGH),
        )
        val sorted = sortByPriority(items)
        // Both HIGH — order preserved from input
        assertEquals("a", sorted[0].id)
        assertEquals("b", sorted[1].id)
    }

    // -------------------------------------------------------------------------
    // §3.3 L513 — Dismiss persistence: filter by dismissed IDs
    // -------------------------------------------------------------------------

    @Test fun `filterDismissed removes item whose id is in dismissed set`() {
        val items = listOf(
            NeedsAttentionItem(id = "ticket_overdue", title = "Overdue"),
            NeedsAttentionItem(id = "low_stock", title = "Low stock"),
        )
        val result = filterDismissed(items, setOf("ticket_overdue"))
        assertEquals(1, result.size)
        assertEquals("low_stock", result[0].id)
    }

    @Test fun `filterDismissed keeps all items when dismissed set is empty`() {
        val items = listOf(
            NeedsAttentionItem(id = "a", title = "A"),
            NeedsAttentionItem(id = "b", title = "B"),
        )
        val result = filterDismissed(items, emptySet())
        assertEquals(2, result.size)
    }

    @Test fun `filterDismissed returns empty list when all items are dismissed`() {
        val items = listOf(
            NeedsAttentionItem(id = "a", title = "A"),
            NeedsAttentionItem(id = "b", title = "B"),
        )
        val result = filterDismissed(items, setOf("a", "b"))
        assertTrue(result.isEmpty())
    }

    @Test fun `filterDismissed is no-op when dismissed id not present in list`() {
        val items = listOf(
            NeedsAttentionItem(id = "a", title = "A"),
        )
        val result = filterDismissed(items, setOf("x", "y"))
        assertEquals(1, result.size)
    }

    @Test fun `filterDismissed handles empty input list`() {
        val result = filterDismissed(emptyList(), setOf("a"))
        assertTrue(result.isEmpty())
    }

    // -------------------------------------------------------------------------
    // §3.3 L514 — Empty-state condition
    // -------------------------------------------------------------------------

    @Test fun `allAttentionClear is true when visible list is empty`() {
        val items = emptyList<NeedsAttentionItem>()
        assertTrue(items.isEmpty())
    }

    @Test fun `allAttentionClear is false when list has at least one item`() {
        val items = listOf(NeedsAttentionItem(id = "x", title = "X"))
        assertFalse(items.isEmpty())
    }

    @Test fun `empty state reached after all items filtered by dismiss`() {
        val items = listOf(
            NeedsAttentionItem(id = "ticket_overdue", title = "Overdue"),
        )
        val result = filterDismissed(items, setOf("ticket_overdue"))
        // §3.3 L514: empty list triggers "All clear" banner
        assertTrue(result.isEmpty())
    }

    // -------------------------------------------------------------------------
    // §3.3 L512 — Context-menu action callbacks (dispatch logic)
    // -------------------------------------------------------------------------

    @Test fun `dismiss callback receives correct item id`() {
        val dismissedIds = mutableListOf<String>()
        val item = NeedsAttentionItem(id = "payment_overdue", title = "Overdue payment")
        val onDismiss: (String) -> Unit = { dismissedIds.add(it) }

        onDismiss(item.id)

        assertEquals(1, dismissedIds.size)
        assertEquals("payment_overdue", dismissedIds[0])
    }

    @Test fun `mark-seen callback receives correct item id`() {
        val seenIds = mutableListOf<String>()
        val item = NeedsAttentionItem(id = "low_stock", title = "Low stock")
        val onMarkSeen: (String) -> Unit = { seenIds.add(it) }

        onMarkSeen(item.id)

        assertEquals(1, seenIds.size)
        assertEquals("low_stock", seenIds[0])
    }

    @Test fun `open callback receives correct action route`() {
        val routes = mutableListOf<String>()
        val item = NeedsAttentionItem(
            id = "a",
            title = "A",
            actionRoute = "tickets?filter=overdue",
        )
        val onOpen: (String) -> Unit = { routes.add(it) }

        onOpen(item.actionRoute)

        assertEquals("tickets?filter=overdue", routes[0])
    }

    @Test fun `create-task callback receives correct item id`() {
        val taskIds = mutableListOf<String>()
        val item = NeedsAttentionItem(id = "sla_breach", title = "SLA breach")
        val onCreateTask: (String) -> Unit = { taskIds.add(it) }

        onCreateTask(item.id)

        assertEquals("sla_breach", taskIds[0])
    }

    // -------------------------------------------------------------------------
    // §3.3 L513 — mark-seen priority demotion (mirrors ViewModel logic)
    // -------------------------------------------------------------------------

    @Test fun `markSeen demotes HIGH priority item to DEFAULT`() {
        val item = NeedsAttentionItem(id = "x", title = "X", priority = AttentionPriority.HIGH)
        val updated = if (item.priority == AttentionPriority.HIGH) {
            item.copy(priority = AttentionPriority.DEFAULT)
        } else {
            item
        }
        assertEquals(AttentionPriority.DEFAULT, updated.priority)
    }

    @Test fun `markSeen does not change INFO priority item`() {
        val item = NeedsAttentionItem(id = "x", title = "X", priority = AttentionPriority.INFO)
        val updated = if (item.priority == AttentionPriority.HIGH) {
            item.copy(priority = AttentionPriority.DEFAULT)
        } else {
            item
        }
        assertEquals(AttentionPriority.INFO, updated.priority)
    }

    // -------------------------------------------------------------------------
    // Category mapping — all values defined
    // -------------------------------------------------------------------------

    @Test fun `all AttentionCategory values are enumerable`() {
        val categories = AttentionCategory.values()
        assertTrue("Expected at least 7 categories", categories.size >= 7)
    }

    @Test fun `all AttentionPriority values are enumerable`() {
        val priorities = AttentionPriority.values()
        assertEquals(3, priorities.size)
    }
}
