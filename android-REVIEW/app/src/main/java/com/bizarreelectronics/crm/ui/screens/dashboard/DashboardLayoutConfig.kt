package com.bizarreelectronics.crm.ui.screens.dashboard

/**
 * §3.17 L609 — Shared dashboard layout configuration consumed by both
 * [DashboardScreen] and the Glance widget module.
 *
 * This is the single source of truth for which tiles are visible and in what order.
 * The Glance widget reads [visibleTiles] to know which KPI values to surface on the
 * home-screen widget. [DashboardScreen] uses [visibleTiles] to drive the LazyColumn
 * tile rendering order.
 *
 * **Glance widget contract**: The widget module (`widget/glance/`) should read a
 * [DashboardLayoutConfig] via `AppPreferences` (injected into its worker) rather
 * than hard-coding tile IDs. No Glance widget code changes are required in this
 * commit — the contract is established here so the widget can adopt it independently.
 *
 * @property visibleTiles   Ordered list of tile IDs to display. Derived from the
 *                          role template (or user-saved order) minus hidden tiles.
 * @property hiddenTiles    Set of tile IDs the user has explicitly hidden.
 * @property allowedTiles   Role-gated superset — tiles not in this set may not be
 *                          shown regardless of user preference.
 * @property savedDashboards Named layout presets the user can switch between.
 * @property activeDashboardName Name of the currently active preset, or null for Default.
 * @property isFirstLaunch  True when no [dashboardTileOrder] pref exists yet — used by
 *                          [DashboardScreen] to show the "Show all tiles" affordance (L610).
 */
data class DashboardLayoutConfig(
    val visibleTiles: List<String> = emptyList(),
    val hiddenTiles: Set<String> = emptySet(),
    val allowedTiles: Set<String> = emptySet(),
    val savedDashboards: List<com.bizarreelectronics.crm.data.local.prefs.SavedDashboard> = emptyList(),
    val activeDashboardName: String? = null,
    val isFirstLaunch: Boolean = false,
)
