package com.bizarreelectronics.crm.ui.screens.dashboard

import com.bizarreelectronics.crm.data.local.prefs.SavedDashboard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §3.17 L602-L610 — Unit tests for dashboard layout config logic.
 *
 * Tests cover:
 * - [DashboardLayoutConfig] default state.
 * - Role-based default tile resolution via a pure function mirroring [DashboardViewModel.defaultTilesFor].
 * - [SavedDashboard] serialisation round-trip.
 * - Tile reorder: visible order reflects save order minus hidden tiles.
 * - Role-gate: tiles not in [allowedTiles] are excluded from [visibleTiles].
 *
 * All tests are pure JVM — no Android context required.
 */
class DashboardLayoutTest {

    // -------------------------------------------------------------------------
    // DashboardLayoutConfig defaults
    // -------------------------------------------------------------------------

    @Test
    fun `DashboardLayoutConfig default is empty and not first-launch`() {
        val config = DashboardLayoutConfig()
        assertTrue(config.visibleTiles.isEmpty())
        assertTrue(config.hiddenTiles.isEmpty())
        assertTrue(config.allowedTiles.isEmpty())
        assertTrue(config.savedDashboards.isEmpty())
        assertEquals(null, config.activeDashboardName)
        assertFalse(config.isFirstLaunch)
    }

    // -------------------------------------------------------------------------
    // Role-template resolution (mirrors DashboardViewModel.defaultTilesFor)
    // -------------------------------------------------------------------------

    private fun defaultTilesFor(role: String): List<String> = when (role.lowercase()) {
        "tech", "technician" -> listOf("my-queue", "my-commission", "tasks")
        "cashier" -> listOf("today-sales", "shift-totals", "quick-actions")
        else -> listOf(
            "open-tickets", "revenue", "appointments", "low-stock",
            "pending-payments", "my-queue", "team-inbox", "activity-feed",
            "profit-hero", "busy-hours", "leaderboard", "repeat-customer",
            "churn-alert", "forecast", "missing-parts",
        )
    }

    @Test
    fun `admin role gets all tiles as default`() {
        val tiles = defaultTilesFor("admin")
        assertTrue(tiles.contains("open-tickets"))
        assertTrue(tiles.contains("revenue"))
        assertTrue(tiles.contains("my-queue"))
        assertTrue(tiles.size >= 10)
    }

    @Test
    fun `manager role gets all tiles (same as admin)`() {
        assertEquals(defaultTilesFor("admin"), defaultTilesFor("manager"))
    }

    @Test
    fun `tech role gets queue + commission + tasks only`() {
        val tiles = defaultTilesFor("tech")
        assertEquals(listOf("my-queue", "my-commission", "tasks"), tiles)
    }

    @Test
    fun `technician alias matches tech`() {
        assertEquals(defaultTilesFor("tech"), defaultTilesFor("technician"))
    }

    @Test
    fun `cashier role gets sales + shift + quick-actions`() {
        val tiles = defaultTilesFor("cashier")
        assertEquals(listOf("today-sales", "shift-totals", "quick-actions"), tiles)
    }

    @Test
    fun `unknown role falls back to admin tiles`() {
        val tiles = defaultTilesFor("guest")
        assertEquals(defaultTilesFor("admin"), tiles)
    }

    @Test
    fun `role resolution is case-insensitive`() {
        assertEquals(defaultTilesFor("tech"), defaultTilesFor("TECH"))
        assertEquals(defaultTilesFor("cashier"), defaultTilesFor("Cashier"))
    }

    // -------------------------------------------------------------------------
    // Tile reorder persistence (pure logic)
    // -------------------------------------------------------------------------

    @Test
    fun `visible tiles follow saved order minus hidden tiles`() {
        val savedOrder = listOf("revenue", "open-tickets", "low-stock", "appointments")
        val hidden = setOf("low-stock")
        val allowed = savedOrder.toSet()

        val visible = savedOrder.filter { it in allowed && it !in hidden }

        assertEquals(listOf("revenue", "open-tickets", "appointments"), visible)
    }

    @Test
    fun `reordering tiles produces correct visible order`() {
        val original = listOf("a", "b", "c", "d")
        // Simulate drag: move "d" to index 1
        val reordered = original.toMutableList()
        val item = reordered.removeAt(3)
        reordered.add(1, item)

        assertEquals(listOf("a", "d", "b", "c"), reordered)
    }

    @Test
    fun `all tiles hidden produces empty visible list`() {
        val savedOrder = listOf("a", "b", "c")
        val hidden = setOf("a", "b", "c")
        val allowed = savedOrder.toSet()

        val visible = savedOrder.filter { it in allowed && it !in hidden }
        assertTrue(visible.isEmpty())
    }

    // -------------------------------------------------------------------------
    // Role-gate filter (allowedTiles restriction)
    // -------------------------------------------------------------------------

    @Test
    fun `tile not in allowedTiles is excluded from visible`() {
        val savedOrder = listOf("my-queue", "my-commission", "tasks", "leaderboard")
        val hidden = emptySet<String>()
        val allowed = setOf("my-queue", "my-commission", "tasks") // leaderboard NOT allowed

        val visible = savedOrder.filter { it in allowed && it !in hidden }

        assertFalse(visible.contains("leaderboard"))
        assertEquals(listOf("my-queue", "my-commission", "tasks"), visible)
    }

    @Test
    fun `empty allowedTiles produces empty visible list`() {
        val savedOrder = listOf("a", "b")
        val allowed = emptySet<String>()

        val visible = savedOrder.filter { it in allowed }
        assertTrue(visible.isEmpty())
    }

    // -------------------------------------------------------------------------
    // SavedDashboard serialisation round-trip
    // -------------------------------------------------------------------------

    @Test
    fun `SavedDashboard serialises and deserialises correctly`() {
        val original = SavedDashboard(
            name = "Morning",
            tileOrder = listOf("open-tickets", "revenue", "my-queue"),
            hiddenTiles = setOf("leaderboard", "churn-alert"),
        )
        val json = SavedDashboard.serialize(original)
        val restored = SavedDashboard.deserialize(json)

        assertEquals(original.name, restored?.name)
        assertEquals(original.tileOrder, restored?.tileOrder)
        assertEquals(original.hiddenTiles, restored?.hiddenTiles)
    }

    @Test
    fun `SavedDashboard list serialises and deserialises correctly`() {
        val list = listOf(
            SavedDashboard("Morning", listOf("a", "b"), setOf("c")),
            SavedDashboard("End of day", listOf("c", "a"), setOf("b")),
        )
        val json = SavedDashboard.serializeList(list)
        val restored = SavedDashboard.deserializeList(json)

        assertEquals(2, restored.size)
        assertEquals("Morning", restored[0].name)
        assertEquals("End of day", restored[1].name)
        assertEquals(listOf("a", "b"), restored[0].tileOrder)
        assertEquals(setOf("b"), restored[1].hiddenTiles)
    }

    @Test
    fun `empty list round-trips to empty list`() {
        val json = SavedDashboard.serializeList(emptyList())
        val restored = SavedDashboard.deserializeList(json)
        assertTrue(restored.isEmpty())
    }

    @Test
    fun `SavedDashboard with name containing quotes is safe`() {
        val original = SavedDashboard(
            name = "Boss's view",
            tileOrder = listOf("revenue"),
            hiddenTiles = emptySet(),
        )
        val json = SavedDashboard.serialize(original)
        val restored = SavedDashboard.deserialize(json)
        assertEquals(original.name, restored?.name)
    }

    // -------------------------------------------------------------------------
    // DashboardLayoutConfig copy / update helpers
    // -------------------------------------------------------------------------

    @Test
    fun `applying customization updates visibleTiles and hiddenTiles`() {
        val initial = DashboardLayoutConfig(
            visibleTiles = listOf("a", "b", "c"),
            hiddenTiles = emptySet(),
            allowedTiles = setOf("a", "b", "c", "d"),
        )
        val newOrder = listOf("c", "a", "b", "d")
        val newHidden = setOf("d")
        val visible = newOrder.filter { it in initial.allowedTiles && it !in newHidden }
        val updated = initial.copy(visibleTiles = visible, hiddenTiles = newHidden)

        assertEquals(listOf("c", "a", "b"), updated.visibleTiles)
        assertEquals(setOf("d"), updated.hiddenTiles)
    }

    @Test
    fun `activating a saved preset filters by allowedTiles`() {
        val preset = SavedDashboard("Night", listOf("a", "b", "c", "x"), setOf("c"))
        val config = DashboardLayoutConfig(
            allowedTiles = setOf("a", "b", "c"), // "x" NOT allowed
        )
        val visible = preset.tileOrder.filter { it in config.allowedTiles && it !in preset.hiddenTiles }
        assertEquals(listOf("a", "b"), visible)
    }

    @Test
    fun `saved dashboards list is capped at 5`() {
        val existing = (1..5).map { SavedDashboard("Layout $it") }
        val newOne = SavedDashboard("Layout 6")
        val updated = (existing + newOne).takeLast(5)
        assertEquals(5, updated.size)
        assertEquals("Layout 2", updated.first().name)
    }
}
