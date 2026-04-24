package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import com.bizarreelectronics.crm.util.WindowMode
import com.bizarreelectronics.crm.util.rememberWindowMode
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.ui.theme.LocalDashboardDensity
import com.bizarreelectronics.crm.data.local.db.dao.NotificationDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.repository.DashboardRepository
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.DashboardFab
import com.bizarreelectronics.crm.ui.components.EmptyStateIllustration
import com.bizarreelectronics.crm.ui.components.PermissionGatedCard
import com.bizarreelectronics.crm.ui.components.SyncStatusBadge
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.screens.dashboard.components.BusyHoursHeatmap
import com.bizarreelectronics.crm.ui.screens.dashboard.components.ChurnAlertCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.DashboardDatePreset
import com.bizarreelectronics.crm.ui.screens.dashboard.components.DateRange
import com.bizarreelectronics.crm.ui.screens.dashboard.components.DateRangeSelector
import com.bizarreelectronics.crm.ui.screens.dashboard.components.ForecastCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.KpiGrid
import com.bizarreelectronics.crm.ui.screens.dashboard.components.KpiTile
import com.bizarreelectronics.crm.ui.screens.dashboard.components.LeaderboardCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.MissingPartsCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.ProfitHeroCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.RepeatCustomerCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.toDateRange
import com.bizarreelectronics.crm.ui.screens.dashboard.components.LeaderboardEntry
import com.bizarreelectronics.crm.ui.screens.dashboard.components.MissingPartItem
import com.bizarreelectronics.crm.ui.screens.dashboard.components.NeedsAttentionItem
import com.bizarreelectronics.crm.ui.screens.dashboard.components.NeedsAttentionSection
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AttentionCategory
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AttentionPriority
import com.bizarreelectronics.crm.data.remote.api.DashboardApi
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.ui.screens.dashboard.components.ActivityItem
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AnnouncementDto
import com.bizarreelectronics.crm.ui.screens.dashboard.components.MyQueueTicket
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgency
import com.bizarreelectronics.crm.ui.screens.dashboard.components.ActivityFeedCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AnnouncementBanner
import com.bizarreelectronics.crm.ui.screens.dashboard.components.AvatarLongPressMenu
import com.bizarreelectronics.crm.ui.screens.dashboard.components.CelebratoryModal
import com.bizarreelectronics.crm.ui.screens.dashboard.components.DashboardCustomizationSheet
import com.bizarreelectronics.crm.ui.screens.dashboard.components.DashboardTabletActions
import com.bizarreelectronics.crm.ui.screens.dashboard.components.MyQueueSection
import com.bizarreelectronics.crm.ui.screens.dashboard.components.DashboardCachedBanner
import com.bizarreelectronics.crm.ui.screens.dashboard.components.SavedDashboardTabs
import com.bizarreelectronics.crm.ui.screens.dashboard.components.SetupChecklistCard
import com.bizarreelectronics.crm.ui.screens.dashboard.components.TeamInboxTile
import com.bizarreelectronics.crm.ui.screens.dashboard.components.UnreadSmsPill
import com.bizarreelectronics.crm.util.rememberReduceMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

data class KpiCard(
    val label: String,
    val value: String,
    val iconTint: Color,
    /**
     * §3.1 — tile taps deep-link to a filtered list. Null = tile is inert.
     * Used by [KpiCardView] to gate `Modifier.clickable` and give the
     * Card a proper `Role.Button` for TalkBack.
     */
    val onClick: (() -> Unit)? = null,
    val icon: @Composable () -> Unit,
)

data class DashboardUiState(
    val greeting: String = "",
    val openTickets: Int = 0,
    val revenueToday: Double = 0.0,
    val appointmentsToday: Int = 0,
    val lowStockCount: Int = 0,
    // §3 L488 — pending payments KPI. Populated from server when available;
    // stays 0 until a dedicated dashboard-stats endpoint exposes the field.
    val pendingPayments: Int = 0,
    val myQueue: List<TicketSummary> = emptyList(),
    val needsAttention: List<AttentionItem> = emptyList(),
    // CROSS1: ticket_all_employees_view_all == '0' enables the assignment feature.
    // When off (default), hide My Queue section entirely.
    val assignmentEnabled: Boolean = false,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    // U9 fix: per-section error state. The legacy single `error` field merged
    // everything into one generic "some data may be outdated" banner — users
    // had no way to tell which API was down.
    val statsError: String? = null,
    val attentionError: String? = null,
    val queueError: String? = null,
    // §3.14 L570 — true when a network error occurred but cached data exists.
    // Drives [DashboardCachedBanner].
    val hasNetworkError: Boolean = false,
    val hasCachedData: Boolean = false,
    // §3.14 L571 — true on brand-new tenant with no prior data loaded.
    // When true + KPI value is 0, a per-tile stub emoji is shown.
    val firstLaunch: Boolean = false,
    // §3.14 L573/L581 — setup wizard progress for [SetupChecklistCard] + completion ring.
    val setupCompletedSteps: Int = 0,
    val setupTotalSteps: Int = 5,
    // §3.14 L572 — permission gates: which tiles the current role can see.
    val canViewReports: Boolean = true,
) {
    // True if any of the three parallel loads failed.
    val hasAnyError: Boolean
        get() = statsError != null || attentionError != null || queueError != null

    /**
     * §3 L497 — true when every KPI is zero, indicating a brand-new tenant.
     * [DashboardEmptyState] is shown in place of the KPI grid when this is true.
     * Hidden immediately once any single KPI becomes non-zero.
     */
    val allKpisZero: Boolean
        get() = openTickets == 0 &&
            revenueToday == 0.0 &&
            appointmentsToday == 0 &&
            lowStockCount == 0 &&
            pendingPayments == 0

    /** §3.14 L570 — show cached banner when network failed but data is available. */
    val showCachedBanner: Boolean
        get() = hasNetworkError && hasCachedData
}

data class TicketSummary(val id: Long, val orderId: String, val customerName: String, val statusName: String, val statusColor: String)
data class AttentionItem(val type: String, val message: String, val entityId: Long?)

// U12 fix: hour → greeting is a pure function used by both the VM and any
// Composable that needs to derive a value keyed on the current hour.
internal fun greetingForHour(hour: Int): String = when {
    hour < 12 -> "Good morning"
    hour < 17 -> "Good afternoon"
    else -> "Good evening"
}

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val dashboardRepository: DashboardRepository,
    private val settingsApi: SettingsApi,
    /** §3.3 L513 — dismiss endpoint; 404-tolerant. */
    private val dashboardApi: DashboardApi,
    /** §3.12 L561 — SMS unread count; 404-tolerant. */
    private val smsApi: SmsApi,
    syncManager: SyncManager,
    syncQueueDao: SyncQueueDao,
    notificationDao: NotificationDao,
    /** Exposed for BI widget cards and NeedsAttentionSection (reduce-motion + dismiss cache). */
    val appPreferences: com.bizarreelectronics.crm.data.local.prefs.AppPreferences,
) : ViewModel() {

    // Exposed so the Dashboard can render a SyncStatusBadge without the
    // screen layer needing its own Hilt injection. Read-only access to the
    // SyncManager state flow — the screen can tap-to-force-sync via [forceSync].
    val isSyncing: StateFlow<Boolean> = syncManager.isSyncing
    val pendingSyncCount: Flow<Int> = syncQueueDao.getCount()
    // CROSS22-badge: unread-notification count for the dashboard bell badge.
    val unreadNotificationCount: Flow<Int> = notificationDao.getUnreadCount()

    private val syncManagerRef = syncManager

    fun forceSync() {
        viewModelScope.launch {
            try { syncManagerRef.syncAll() } catch (_: Exception) {}
        }
    }

    // -------------------------------------------------------------------------
    // §3.2 L500–L506 — BI widget state slots.
    //
    // All flows default to empty / stub values. Cards render a "Connect data"
    // affordance when they receive empty collections — no network calls are made
    // until the corresponding server endpoints ship.
    //
    // Stub contract:
    //   profitTrend    — empty list → ProfitHeroCard shows "Connect Profit data"
    //   busyHours      — empty array → BusyHoursHeatmap shows "No heatmap data"
    //   leaderboard    — empty list → LeaderboardCard shows "No leaderboard data"
    //   repeatPercent  — null → RepeatCustomerCard shows "—"
    //   churnAtRisk    — null → ChurnAlertCard shows "Data unavailable"
    //   forecastCents  — null → ForecastCard shows "Forecast available with 90+ days"
    //   missingParts   — null → MissingPartsCard shows "Connect Inventory data"
    // -------------------------------------------------------------------------

    /** §3.2 L500 — daily net-margin percentages for Profit Hero sparkline (≤30 pts). */
    private val _profitTrend = MutableStateFlow<List<Double>>(emptyList())
    val profitTrend: StateFlow<List<Double>> = _profitTrend.asStateFlow()

    /** §3.2 L501 — 7×24 ticket-volume grid for the Busy Hours heatmap. */
    private val _busyHours = MutableStateFlow<Array<IntArray>>(emptyArray())
    val busyHours: StateFlow<Array<IntArray>> = _busyHours.asStateFlow()

    /** §3.2 L502 — top staff entries for the Leaderboard card. */
    private val _leaderboard = MutableStateFlow<List<LeaderboardEntry>>(emptyList())
    val leaderboard: StateFlow<List<LeaderboardEntry>> = _leaderboard.asStateFlow()

    /** §3.2 L503 — % repeat customers last 90 days. Null = no data. */
    private val _repeatPercent = MutableStateFlow<Double?>(null)
    val repeatPercent: StateFlow<Double?> = _repeatPercent.asStateFlow()

    /** §3.2 L503 — pp delta vs prior 90-day period. Null = unknown. */
    private val _repeatTrendDelta = MutableStateFlow<Double?>(null)
    val repeatTrendDelta: StateFlow<Double?> = _repeatTrendDelta.asStateFlow()

    /** §3.2 L504 — count of at-risk customers for Churn Alert. Null = data unavailable. */
    private val _churnAtRisk = MutableStateFlow<Int?>(null)
    val churnAtRisk: StateFlow<Int?> = _churnAtRisk.asStateFlow()

    /** §3.2 L505 — projected 30-day revenue in cents. Null = insufficient history. */
    private val _forecastCents = MutableStateFlow<Long?>(null)
    val forecastCents: StateFlow<Long?> = _forecastCents.asStateFlow()

    /** §3.2 L505 — days of revenue history for Forecast progress bar. */
    private val _forecastHistoryDays = MutableStateFlow<Int?>(null)
    val forecastHistoryDays: StateFlow<Int?> = _forecastHistoryDays.asStateFlow()

    /** §3.2 L506 — inventory items needing reorder. Null = source not connected. */
    private val _missingParts = MutableStateFlow<List<MissingPartItem>?>(null)
    val missingParts: StateFlow<List<MissingPartItem>?> = _missingParts.asStateFlow()

    // -------------------------------------------------------------------------
    // §3.4 L519 — My Queue section visibility
    // -------------------------------------------------------------------------

    private val _showMyQueue = MutableStateFlow(appPreferences.dashboardShowMyQueue)
    val showMyQueue: StateFlow<Boolean> = _showMyQueue.asStateFlow()

    fun setShowMyQueue(on: Boolean) {
        appPreferences.dashboardShowMyQueue = on
        _showMyQueue.value = on
    }

    // -------------------------------------------------------------------------
    // §3.5 L531 — Celebratory modal
    // -------------------------------------------------------------------------

    /**
     * §3.5 L531 — true when the queue just transitioned from non-zero → zero and
     * the modal has not yet been shown today.
     *
     * Derived by [collectMyQueue] by tracking the previous queue size. The flag
     * is cleared when the user dismisses the modal via [dismissCelebratoryModal].
     */
    private val _showCelebratoryModal = MutableStateFlow(false)
    val showCelebratoryModal: StateFlow<Boolean> = _showCelebratoryModal.asStateFlow()

    /** Previous queue size — used to detect the non-zero → zero transition. */
    private var _previousQueueSize: Int = -1 // -1 = "not yet observed"

    fun dismissCelebratoryModal() {
        _showCelebratoryModal.value = false
        val today = java.time.LocalDate.now().toString()
        appPreferences.lastCelebrationDate = today
    }

    // -------------------------------------------------------------------------
    // §3.6 L534 — Activity feed
    // -------------------------------------------------------------------------

    private val _recentActivity = MutableStateFlow<List<ActivityItem>>(emptyList())
    val recentActivity: StateFlow<List<ActivityItem>> = _recentActivity.asStateFlow()

    // -------------------------------------------------------------------------
    // §3.7 L538 — Announcement banner
    // -------------------------------------------------------------------------

    private val _announcement = MutableStateFlow<AnnouncementDto?>(null)
    val announcement: StateFlow<AnnouncementDto?> = _announcement.asStateFlow()

    /**
     * §3.7 — Persist the dismissed announcement id and clear the banner.
     * The ViewModel will not re-show the same id until a different announcement
     * is returned from the server.
     */
    fun dismissAnnouncement(id: String) {
        appPreferences.dismissedAnnouncementId = id
        _announcement.value = null
    }

    // -------------------------------------------------------------------------
    // §3.3 L510–L514 — Needs-Attention row-level cards
    // -------------------------------------------------------------------------

    /**
     * §3.3 L510 — Needs-Attention items visible to the user.
     * Already filtered by [AppPreferences.dismissedAttentionIds]; sorted HIGH first.
     */
    private val _needsAttentionItems = MutableStateFlow<List<NeedsAttentionItem>>(emptyList())
    val needsAttentionItems: StateFlow<List<NeedsAttentionItem>> = _needsAttentionItems.asStateFlow()

    /** §3.3 L514 — true when the visible attention list is empty. */
    val allAttentionClear: Boolean
        get() = _needsAttentionItems.value.isEmpty()

    /**
     * §3.3 L512/L513 — optimistically remove [id], then attempt server-side
     * dismiss (POST /dashboard/attention/{id}/dismiss). Falls back to local
     * prefs cache on 404 (endpoint not yet implemented).
     */
    fun dismissAttention(id: String) {
        val previous = _needsAttentionItems.value
        _needsAttentionItems.value = previous.filter { it.id != id }
        viewModelScope.launch {
            try {
                dashboardApi.dismissAttentionItem(id)
                appPreferences.addDismissedAttentionId(id)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    appPreferences.addDismissedAttentionId(id)
                } else {
                    android.util.Log.w("Dashboard", "dismissAttention failed (${e.code()}): ${e.message}")
                    _needsAttentionItems.value = previous
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "dismissAttention offline fallback for $id: ${e.message}")
                appPreferences.addDismissedAttentionId(id)
            }
        }
    }

    /** §3.3 L512 — restore a dismissed item (Snackbar undo). */
    fun undoDismissAttention(id: String) {
        appPreferences.removeDismissedAttentionId(id)
        refresh()
    }

    /**
     * §3.3 L512 — local-only "mark seen" flag. Demotes HIGH to DEFAULT priority;
     * does not remove the item or call the server.
     */
    fun markAttentionSeen(id: String) {
        appPreferences.addSeenAttentionId(id)
        _needsAttentionItems.value = _needsAttentionItems.value.map { item ->
            if (item.id == id && item.priority == AttentionPriority.HIGH) {
                item.copy(priority = AttentionPriority.DEFAULT)
            } else {
                item
            }
        }
    }

    private val _state = MutableStateFlow(DashboardUiState())
    val state = _state.asStateFlow()

    // §3 L491 — current date-range selection.
    // Default = TODAY. The UI calls setCurrentRange() when the user picks a
    // different preset or confirms a custom range from the date picker.
    //
    // previousPeriodValues is intentionally empty until the server ships the
    // /dashboard/compare endpoint. The KpiGrid delta chip slot is wired but
    // data-less — no network call is made for comparison values yet.
    private val _currentRange = MutableStateFlow(
        DashboardDatePreset.TODAY.toDateRange(),
    )
    val currentRange: StateFlow<DateRange> = _currentRange.asStateFlow()

    /**
     * §3 L491 — update the active date range and re-fetch KPIs for that range.
     * Re-uses the existing [loadDashboard] which reads [currentRange] for the
     * date context once the stats endpoint supports date parameters.
     */
    fun setCurrentRange(range: DateRange) {
        _currentRange.value = range
        // Re-trigger load so new range is reflected in KPI values when the
        // server endpoint supports date filtering. Currently a no-op date-wise
        // but keeps the contract correct for when the API lands.
        refresh()
    }

    // -------------------------------------------------------------------------
    // §3.12 L561 — SMS unread count
    // -------------------------------------------------------------------------

    /**
     * §3.12 L561 — Unread SMS conversation count. Null = 404 / endpoint not yet
     * available. Badge is hidden when null.
     */
    private val _unreadSmsCount = MutableStateFlow<Int?>(null)
    val unreadSmsCount: StateFlow<Int?> = _unreadSmsCount.asStateFlow()

    fun refreshSmsCount() {
        viewModelScope.launch {
            try {
                val response = smsApi.getUnreadCount()
                _unreadSmsCount.value = response.data?.count
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _unreadSmsCount.value = null // endpoint not yet live — hide badge
                } else {
                    android.util.Log.w("Dashboard", "getUnreadCount failed (${e.code()}): ${e.message}")
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "getUnreadCount offline: ${e.message}")
            }
        }
    }

    // -------------------------------------------------------------------------
    // §3.12 L562 — Team Inbox unread count
    // -------------------------------------------------------------------------

    /**
     * §3.12 L562 — Team Inbox unread count from `GET /inbox`. Null = 404 / hide tile.
     */
    private val _teamInboxCount = MutableStateFlow<Int?>(null)
    val teamInboxCount: StateFlow<Int?> = _teamInboxCount.asStateFlow()

    fun refreshTeamInbox() {
        viewModelScope.launch {
            try {
                val response = dashboardApi.getInbox()
                _teamInboxCount.value = response.data?.unreadCount
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _teamInboxCount.value = null // endpoint not yet live — hide tile
                } else {
                    android.util.Log.w("Dashboard", "getInbox failed (${e.code()}): ${e.message}")
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "getInbox offline: ${e.message}")
            }
        }
    }

    // -------------------------------------------------------------------------
    // §3.17 L602-L610 — Dashboard layout config (role templates + customization)
    // -------------------------------------------------------------------------

    /**
     * §3.17 L609 — Shared layout configuration read by DashboardScreen and the
     * Glance widget. Updated by [loadRoleTemplate] on init and by
     * [applyCustomization] / [activateSavedDashboard] on user action.
     */
    private val _layoutConfig = MutableStateFlow(DashboardLayoutConfig())
    val layoutConfig: StateFlow<DashboardLayoutConfig> = _layoutConfig.asStateFlow()

    /**
     * §3.17 L602-L603 — Ordered tile IDs for a given [role] when the server
     * returns 404 (endpoint not yet live) or on network error.
     *
     * - admin / manager : all tiles
     * - tech            : my-queue, my-commission, tasks
     * - cashier         : today-sales, shift-totals, quick-actions
     * - fallback        : same as admin
     */
    fun defaultTilesFor(role: String): List<String> = when (role.lowercase()) {
        "tech", "technician" -> listOf("my-queue", "my-commission", "tasks")
        "cashier" -> listOf("today-sales", "shift-totals", "quick-actions")
        else -> listOf(
            "open-tickets", "revenue", "appointments", "low-stock",
            "pending-payments", "my-queue", "team-inbox", "activity-feed",
            "profit-hero", "busy-hours", "leaderboard", "repeat-customer",
            "churn-alert", "forecast", "missing-parts",
        )
    }

    /**
     * §3.17 L602 — Load the role template from the server. Falls back to
     * [defaultTilesFor] on HTTP 404 or any network error.
     *
     * On first launch ([dashboardTileOrder] not yet set), the role-default tile
     * order is persisted to prefs and the advanced tiles are hidden (L610).
     */
    private fun loadRoleTemplate() {
        viewModelScope.launch {
            val role = authPreferences.userRole ?: "admin"
            val isFirstLaunch = appPreferences.dashboardTileOrder.isEmpty()

            val (defaultTiles, allowedTiles) = try {
                val response = dashboardApi.getRoleTemplate(role)
                val dto = response.data
                if (dto != null) {
                    Pair(dto.defaultTiles, dto.allowedTiles)
                } else {
                    val defaults = defaultTilesFor(role)
                    Pair(defaults, defaults.toSet())
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    val defaults = defaultTilesFor(role)
                    Pair(defaults, defaults.toSet())
                } else {
                    android.util.Log.w("Dashboard", "getRoleTemplate(${e.code()}): ${e.message}")
                    val defaults = defaultTilesFor(role)
                    Pair(defaults, defaults.toSet())
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "getRoleTemplate offline: ${e.message}")
                val defaults = defaultTilesFor(role)
                Pair(defaults, defaults.toSet())
            }

            // L610 — on first launch, persist the role defaults and mark advanced tiles hidden.
            if (isFirstLaunch) {
                appPreferences.dashboardTileOrder = defaultTiles
                // Advanced tiles are those in allowedTiles but NOT in defaultTiles.
                val advanced = allowedTiles - defaultTiles.toSet()
                appPreferences.dashboardHiddenTiles = advanced
            }

            val savedOrder = appPreferences.dashboardTileOrder
            val hidden = appPreferences.dashboardHiddenTiles
            val effectiveOrder = if (savedOrder.isNotEmpty()) savedOrder else defaultTiles
            val visible = effectiveOrder
                .filter { it in allowedTiles && it !in hidden }

            _layoutConfig.value = DashboardLayoutConfig(
                visibleTiles = visible,
                hiddenTiles = hidden,
                allowedTiles = allowedTiles,
                savedDashboards = appPreferences.savedDashboards,
                activeDashboardName = null,
                isFirstLaunch = isFirstLaunch,
            )
        }
    }

    /**
     * §3.17 L496 / L606 — Persist a new tile order + hidden set from the
     * customisation sheet and rebuild [layoutConfig].
     *
     * @param orderedTiles All tiles in their new drag-sorted order.
     * @param hiddenTiles  Tiles the user has checked "hide".
     */
    fun applyCustomization(orderedTiles: List<String>, hiddenTiles: Set<String>) {
        appPreferences.dashboardTileOrder = orderedTiles
        appPreferences.dashboardHiddenTiles = hiddenTiles
        val current = _layoutConfig.value
        val visible = orderedTiles.filter { it in current.allowedTiles && it !in hiddenTiles }
        _layoutConfig.value = current.copy(
            visibleTiles = visible,
            hiddenTiles = hiddenTiles,
        )
    }

    /**
     * §3.17 L607-L608 — Switch to a saved dashboard preset by name.
     * Passing null reverts to the "Default" layout (role-template order + prefs).
     */
    fun activateSavedDashboard(name: String?) {
        val current = _layoutConfig.value
        if (name == null) {
            // Revert to current prefs-based order.
            val savedOrder = appPreferences.dashboardTileOrder
            val hidden = appPreferences.dashboardHiddenTiles
            val visible = savedOrder.filter { it in current.allowedTiles && it !in hidden }
            _layoutConfig.value = current.copy(
                visibleTiles = visible,
                hiddenTiles = hidden,
                activeDashboardName = null,
            )
            return
        }
        val preset = current.savedDashboards.firstOrNull { it.name == name } ?: return
        val visible = preset.tileOrder.filter { it in current.allowedTiles && it !in preset.hiddenTiles }
        _layoutConfig.value = current.copy(
            visibleTiles = visible,
            hiddenTiles = preset.hiddenTiles,
            activeDashboardName = name,
        )
    }

    /**
     * §3.17 L607-L608 — Save the current tile order + hidden set as a named preset.
     * Replaces an existing preset with the same name; max 5 saved dashboards (oldest dropped).
     */
    fun saveCurrentLayoutAs(name: String) {
        val current = _layoutConfig.value
        val newDashboard = com.bizarreelectronics.crm.data.local.prefs.SavedDashboard(
            name = name,
            tileOrder = current.visibleTiles + current.hiddenTiles.toList(),
            hiddenTiles = current.hiddenTiles,
        )
        val existing = appPreferences.savedDashboards.toMutableList()
        val idx = existing.indexOfFirst { it.name == name }
        val updated = if (idx >= 0) {
            existing.toMutableList().also { it[idx] = newDashboard }
        } else {
            (existing + newDashboard).takeLast(5)
        }
        appPreferences.setSavedDashboards(updated)
        _layoutConfig.value = current.copy(
            savedDashboards = updated,
            activeDashboardName = name,
        )
    }

    /** §3.17 L610 — Reveal all allowed tiles (called from "Show all tiles" button). */
    fun showAllTiles() {
        val current = _layoutConfig.value
        appPreferences.dashboardHiddenTiles = emptySet()
        val visible = current.visibleTiles + current.hiddenTiles.filter { it in current.allowedTiles }
        _layoutConfig.value = current.copy(
            visibleTiles = visible,
            hiddenTiles = emptySet(),
            isFirstLaunch = false,
        )
    }

    init {
        loadDashboard()
        collectMyQueue()
        loadAssignmentSetting()
        loadActivityFeed()
        loadAnnouncement()
        refreshSmsCount()
        refreshTeamInbox()
        loadRoleTemplate()
        startPeriodicRefresh()
    }

    /** §3.12 — auto-refresh SMS unread + team inbox every 30 s. */
    private fun startPeriodicRefresh() {
        viewModelScope.launch {
            while (true) {
                delay(30_000L)
                refreshSmsCount()
                refreshTeamInbox()
            }
        }
    }

    private fun loadAssignmentSetting() {
        viewModelScope.launch {
            try {
                val cfg = settingsApi.getConfig().data ?: return@launch
                val enabled = cfg["ticket_all_employees_view_all"] == "0"
                _state.value = _state.value.copy(assignmentEnabled = enabled)
            } catch (_: Exception) {
                // Offline / server error — leave at default (off).
            }
        }
    }

    private fun loadDashboard() {
        viewModelScope.launch {
            // CROSS20: fall back to capitalized username when first_name is blank (empty
            // string is truthy in Kotlin ?: chain). Avoids "Good afternoon, admin" lowercase.
            val name = authPreferences.userFirstName?.takeIf { it.isNotBlank() }
                ?: authPreferences.username?.replaceFirstChar { it.uppercase() }
                ?: ""
            // U12 fix: compute the greeting once per load (keyed to "now"),
            // not on every recomposition. greetingForHour is a pure function
            // so we can call it freely.
            val greetingText = greetingForHour(java.time.LocalTime.now().hour)

            _state.value = _state.value.copy(
                greeting = "$greetingText, $name",
                statsError = null,
                attentionError = null,
                queueError = null,
            )

            // U9 fix: track each section's error independently.
            // Stats.
            try {
                val stats = dashboardRepository.getDashboardStats()
                _state.value = _state.value.copy(
                    openTickets = stats.openTickets,
                    revenueToday = stats.revenueToday,
                    appointmentsToday = stats.appointmentsToday,
                    statsError = null,
                    // §3.14 L570 — mark that we have live data; clear network-error flag.
                    hasNetworkError = false,
                    hasCachedData = true,
                )
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load stats: ${e.message}")
                _state.value = _state.value.copy(
                    statsError = e.message ?: "Failed to load KPIs",
                    // §3.14 L570 — signal network error; banner shown if hasCachedData.
                    hasNetworkError = true,
                )
            }

            // Needs-attention.
            try {
                val attention = dashboardRepository.getNeedsAttention()
                val dismissed = appPreferences.dismissedAttentionIds
                val attentionItems = mutableListOf<AttentionItem>()
                val richItems = mutableListOf<NeedsAttentionItem>()

                if (attention.staleTicketsCount > 0) {
                    attentionItems.add(AttentionItem("ticket", "${attention.staleTicketsCount} stale tickets need attention", null))
                    val id = "ticket_overdue"
                    if (id !in dismissed) richItems.add(NeedsAttentionItem(
                        id = id, title = "${attention.staleTicketsCount} overdue tickets",
                        subtitle = "Awaiting update or status change",
                        actionLabel = "View Tickets", actionRoute = "tickets?filter=overdue",
                        priority = AttentionPriority.HIGH, category = AttentionCategory.TICKET_OVERDUE,
                    ))
                }
                if (attention.missingPartsCount > 0) {
                    attentionItems.add(AttentionItem("parts", "${attention.missingPartsCount} parts missing across open tickets", null))
                    val id = "missing_parts"
                    if (id !in dismissed) richItems.add(NeedsAttentionItem(
                        id = id, title = "${attention.missingPartsCount} parts missing",
                        subtitle = "Parts required for open tickets",
                        actionLabel = "View Parts", actionRoute = "inventory?filter=missing",
                        priority = AttentionPriority.INFO, category = AttentionCategory.LOW_STOCK,
                    ))
                }
                if (attention.overdueInvoicesCount > 0) {
                    attentionItems.add(AttentionItem("invoice", "${attention.overdueInvoicesCount} overdue invoices", null))
                    val id = "payment_overdue"
                    if (id !in dismissed) richItems.add(NeedsAttentionItem(
                        id = id, title = "${attention.overdueInvoicesCount} overdue invoices",
                        subtitle = "Payment not received",
                        actionLabel = "View Invoices", actionRoute = "invoices?filter=overdue",
                        priority = AttentionPriority.HIGH, category = AttentionCategory.PAYMENT_FAILED,
                    ))
                }
                if (attention.lowStockCount > 0) {
                    val id = "low_stock"
                    if (id !in dismissed) richItems.add(NeedsAttentionItem(
                        id = id, title = "${attention.lowStockCount} items low in stock",
                        subtitle = "Below minimum threshold",
                        actionLabel = "View Inventory", actionRoute = "inventory?filter=low_stock",
                        priority = AttentionPriority.INFO, category = AttentionCategory.LOW_STOCK,
                    ))
                }

                _needsAttentionItems.value = richItems.sortedByDescending { it.priority.ordinal }
                _state.value = _state.value.copy(
                    lowStockCount = attention.lowStockCount,
                    needsAttention = attentionItems,
                    attentionError = null,
                )
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to load needs-attention: ${e.message}")
                _state.value = _state.value.copy(
                    attentionError = e.message ?: "Failed to load Needs Attention",
                )
            }

            // My Queue refresh.
            try {
                dashboardRepository.refreshMyQueue()
                _state.value = _state.value.copy(queueError = null)
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "Failed to refresh queue: ${e.message}")
                _state.value = _state.value.copy(
                    queueError = e.message ?: "Failed to refresh My Queue",
                )
            }

            _state.value = _state.value.copy(
                isLoading = false,
                isRefreshing = false,
            )
        }
    }

    /** Collect the Room Flow for My Queue — updates automatically when DB changes. */
    private fun collectMyQueue() {
        viewModelScope.launch {
            dashboardRepository.getMyQueue().collect { entities ->
                val currentSize = entities.size
                // §3.5 — detect non-zero → zero transition for celebratory modal
                val wasNonZero = _previousQueueSize > 0
                val isNowZero = currentSize == 0
                if (wasNonZero && isNowZero) {
                    val today = java.time.LocalDate.now().toString()
                    if (appPreferences.lastCelebrationDate != today) {
                        _showCelebratoryModal.value = true
                    }
                }
                _previousQueueSize = currentSize

                _state.value = _state.value.copy(
                    myQueue = entities.map { entity ->
                        TicketSummary(
                            id = entity.id,
                            orderId = entity.orderId,
                            customerName = entity.customerName ?: "Unknown",
                            statusName = entity.statusName ?: "",
                            statusColor = entity.statusColor ?: "#6b7280",
                        )
                    },
                )
            }
        }
    }

    /**
     * §3.6 L534 — Load the activity feed from `GET /activity?limit=20`.
     * Silently stubs to empty list on 404 (endpoint not yet implemented).
     */
    private fun loadActivityFeed() {
        viewModelScope.launch {
            try {
                val response = dashboardApi.recentActivity(limit = 20)
                _recentActivity.value = response.data?.items ?: emptyList()
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    // Endpoint not yet implemented — show empty state
                    _recentActivity.value = emptyList()
                } else {
                    android.util.Log.w("Dashboard", "recentActivity failed (${e.code()}): ${e.message}")
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "recentActivity offline fallback: ${e.message}")
                _recentActivity.value = emptyList()
            }
        }
    }

    /**
     * §3.7 L538 — Fetch the current announcement from `GET /announcements/current`.
     * Silently returns null on 404. Suppresses banners for already-dismissed ids.
     */
    private fun loadAnnouncement() {
        viewModelScope.launch {
            try {
                val response = dashboardApi.currentAnnouncement()
                val dto = response.data
                if (dto != null && dto.id != appPreferences.dismissedAnnouncementId) {
                    _announcement.value = dto
                }
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 404) {
                    _announcement.value = null
                } else {
                    android.util.Log.w("Dashboard", "currentAnnouncement failed (${e.code()}): ${e.message}")
                }
            } catch (e: Exception) {
                android.util.Log.w("Dashboard", "currentAnnouncement offline fallback: ${e.message}")
                _announcement.value = null
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadDashboard()
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun DashboardScreen(
    onNavigateToTicket: (Long) -> Unit,
    onNavigateToTickets: () -> Unit,
    onCreateTicket: () -> Unit = {},
    onCreateCustomer: () -> Unit = {},
    onLogSale: () -> Unit = {},
    onScanBarcode: (() -> Unit)? = null,
    onNavigateToNotifications: (() -> Unit)? = null,
    // §3.11 — opens ClockInOutScreen. Tile rendered above KPI grid; null
    // hides the tile (e.g. previews, non-nav callers).
    onClockInOut: (() -> Unit)? = null,
    // §3.1 — KPI tiles deep-link into the relevant filtered list. Nullable
    // so previews / standalone dashboard tests can pass without a NavController.
    onNavigateToAppointments: (() -> Unit)? = null,
    onNavigateToInventory: (() -> Unit)? = null,
    // §3.9 — tap greeting → Settings → Profile. Nullable keeps previews +
    // isolated tests composable without a NavController.
    onNavigateToProfile: (() -> Unit)? = null,
    // §3.10 — sync badge redirects to Settings → Data → Sync Issues when
    // pending rows are stuck; force-sync stays the default for clean state.
    onNavigateToSyncIssues: (() -> Unit)? = null,
    // §3.8 L543 — tablet action row: Settings shortcut.
    onNavigateToSettings: (() -> Unit)? = null,
    // §3.9 L549 — avatar long-press: switch user / sign out.
    onSwitchUser: (() -> Unit)? = null,
    onSignOut: (() -> Unit)? = null,
    // §3.12 L561 — SMS pill tap → SMS tab.
    onNavigateToSms: (() -> Unit)? = null,
    // §3.14 L573/L581 — Setup Wizard navigation for SetupChecklistCard + completion ring.
    onNavigateToSetup: (() -> Unit)? = null,
    // §3.16 L593 — "Show more" on Activity Feed card → full Activity Feed screen.
    onNavigateToActivityFeed: (() -> Unit)? = null,
    viewModel: DashboardViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val currentRange by viewModel.currentRange.collectAsState()
    // §3.8 L543 — detect tablet to conditionally show action row vs FAB.
    val windowMode = rememberWindowMode()
    val isTablet = windowMode != WindowMode.Phone
    // [P1] FAB expand state hoisted so this screen can render a scrim overlay.
    // Passed to DashboardFab as expandedState so both share a single source of truth.
    val fabExpandedState = remember { mutableStateOf(false) }

    // §3.4–3.7 — new section state
    val showMyQueue by viewModel.showMyQueue.collectAsState()
    val recentActivity by viewModel.recentActivity.collectAsState()
    val announcement by viewModel.announcement.collectAsState()
    val showCelebratoryModal by viewModel.showCelebratoryModal.collectAsState()
    val reduceMotion = rememberReduceMotion(viewModel.appPreferences)

    // §3.12 — SMS unread + team inbox counts.
    val unreadSmsCount by viewModel.unreadSmsCount.collectAsState()
    val teamInboxCount by viewModel.teamInboxCount.collectAsState()

    // §3.17 L602-L610 — Layout config (role templates + customization).
    val layoutConfig by viewModel.layoutConfig.collectAsState()
    var showCustomizationSheet by remember { mutableStateOf(false) }

    // §3.8 L557 — Snackbar host for clock-in success toast.
    val clockSnackbarHostState = remember { SnackbarHostState() }

    // §3.9 — avatar initials: first char of each word in the name portion of the greeting.
    // The greeting format is "Good morning, Pavel Ivanov" — name is after the comma.
    val avatarInitials by remember(state.greeting) {
        val namePart = state.greeting.substringAfter(", ").trim()
        val words = namePart.split(" ").filter { it.isNotBlank() }
        mutableStateOf(words.mapNotNull { it.firstOrNull()?.uppercaseChar() }.take(2).joinToString(""))
    }

    // §3 L491 — track which preset is active so the segmented button row
    // highlights the correct button. Defaults to TODAY; set to CUSTOM when
    // the user confirms a date-picker selection.
    var selectedPreset by remember { mutableStateOf(DashboardDatePreset.TODAY) }

    // Monochrome + state rule: icons muted by default, only tinted when the
    // value conveys state that matters. Zero revenue, zero tickets, zero
    // appointments, zero low-stock = no state, so muted. Once a value is
    // non-zero the icon picks up the semantic hue (primary / success / teal /
    // warning) so a user scanning the grid notices the things that changed.
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val openTicketsTint = if (state.openTickets > 0) MaterialTheme.colorScheme.primary else muted
    val revenueTint = if (state.revenueToday > 0) SuccessGreen else muted
    val apptsTint = if (state.appointmentsToday > 0) MaterialTheme.colorScheme.secondary else muted
    val lowStockTint = if (state.lowStockCount > 0) WarningAmber else muted
    val pendingTint = if (state.pendingPayments > 0) MaterialTheme.colorScheme.tertiary else muted

    // §3 L488 — KpiTile list fed into KpiGrid composable.
    // deltaPercent is null for all tiles until /dashboard/compare ships.
    val kpiTiles = listOf(
        KpiTile(
            label = "Open Tickets",
            value = state.openTickets.toString(),
            iconTint = openTicketsTint,
            icon = {
                Icon(Icons.Default.ConfirmationNumber, contentDescription = null, tint = openTicketsTint)
            },
            onClick = onNavigateToTickets,
        ),
        KpiTile(
            label = "Revenue",
            value = "$${String.format("%.2f", state.revenueToday)}",
            iconTint = revenueTint,
            icon = {
                Icon(Icons.Default.AttachMoney, contentDescription = null, tint = revenueTint)
            },
            // Revenue tile has no detail screen on Android yet — inert tap.
            onClick = null,
        ),
        KpiTile(
            label = "Appointments",
            value = state.appointmentsToday.toString(),
            iconTint = apptsTint,
            icon = {
                Icon(Icons.Default.CalendarToday, contentDescription = null, tint = apptsTint)
            },
            onClick = onNavigateToAppointments,
        ),
        KpiTile(
            label = "Low Stock",
            value = state.lowStockCount.toString(),
            iconTint = lowStockTint,
            icon = {
                Icon(Icons.Default.Warning, contentDescription = null, tint = lowStockTint)
            },
            onClick = onNavigateToInventory,
        ),
        KpiTile(
            label = "Pending Payments",
            value = state.pendingPayments.toString(),
            iconTint = pendingTint,
            icon = {
                Icon(Icons.Default.Pending, contentDescription = null, tint = pendingTint)
            },
            // No detail screen yet — inert tap.
            onClick = null,
        ),
    )

    // Legacy KpiCard list kept for KpiCardView usages elsewhere in this file.
    val kpis = listOf(
        KpiCard(
            label = "Open Tickets",
            value = state.openTickets.toString(),
            iconTint = openTicketsTint,
            onClick = onNavigateToTickets,
        ) {
            Icon(Icons.Default.ConfirmationNumber, contentDescription = null, tint = openTicketsTint)
        },
        KpiCard(
            label = "Revenue Today",
            value = "$${String.format("%.2f", state.revenueToday)}",
            iconTint = revenueTint,
            onClick = null,
        ) {
            Icon(Icons.Default.AttachMoney, contentDescription = null, tint = revenueTint)
        },
        KpiCard(
            label = "Appointments",
            value = state.appointmentsToday.toString(),
            iconTint = apptsTint,
            onClick = onNavigateToAppointments,
        ) {
            Icon(Icons.Default.CalendarToday, contentDescription = null, tint = apptsTint)
        },
        KpiCard(
            label = "Low Stock",
            value = state.lowStockCount.toString(),
            iconTint = lowStockTint,
            onClick = onNavigateToInventory,
        ) {
            Icon(Icons.Default.Warning, contentDescription = null, tint = lowStockTint)
        },
    )

    Scaffold(
        snackbarHost = { SnackbarHost(hostState = clockSnackbarHostState) },
        // [P1] BrandTopAppBar hosts the greeting title and sync badge in the
        // action slot, saving a full row in the LazyColumn and anchoring sync
        // status where every Android app puts it.
        //
        // CROSS45: WaveDivider docked directly below the TopAppBar (moved from
        // its previous LazyColumn mid-list position) — canonical placement
        // for every list/dashboard screen.
        topBar = {
            Column {
                BrandTopAppBar(
                    title = state.greeting.ifEmpty { "Dashboard" },
                    // §3.9 — greeting itself is the profile shortcut. When
                    // onNavigateToProfile is wired, render the title as a
                    // clickable Text with role=Button so TalkBack announces
                    // it as an action (the default titleContent is inert).
                    // Null lets BrandTopAppBar fall back to the normal
                    // heading-style Text.
                    titleContent = onNavigateToProfile?.let { onProfile ->
                        {
                            Text(
                                text = state.greeting.ifEmpty { "Dashboard" },
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier
                                    .semantics {
                                        role = Role.Button
                                        heading()
                                    }
                                    .clickable(onClick = onProfile),
                            )
                        }
                    },
                    // §3.9 L549 — avatar in the navigation slot (phone + tablet).
                    navigationIcon = {
                        AvatarLongPressMenu(
                            initials = avatarInitials.ifBlank { "?" },
                            onNavigateToProfile = onNavigateToProfile,
                            onSwitchUser = onSwitchUser,
                            onSignOut = onSignOut,
                        )
                    },
                    actions = {
                        // §3.8 L543 — Tablet: replace FAB with inline action row.
                        if (isTablet) {
                            DashboardTabletActions(
                                onCreateTicket = onCreateTicket,
                                onCreateCustomer = onCreateCustomer,
                                onScanBarcode = onScanBarcode,
                                onNewSms = onNavigateToSms,
                                onNavigateToSettings = onNavigateToSettings,
                            )
                        }
                        // §3.12 L561 — SMS unread pill.
                        if (onNavigateToSms != null) {
                            UnreadSmsPill(
                                unreadCount = unreadSmsCount,
                                onNavigateToSms = onNavigateToSms,
                            )
                        }
                        // CROSS22 + CROSS22-badge: bell icon + unread count badge.
                        if (onNavigateToNotifications != null) {
                            val unread by viewModel.unreadNotificationCount.collectAsState(initial = 0)
                            BadgedBox(
                                badge = {
                                    if (unread > 0) {
                                        Badge {
                                            Text(if (unread > 99) "99+" else unread.toString())
                                        }
                                    }
                                },
                            ) {
                                IconButton(onClick = onNavigateToNotifications) {
                                    Icon(
                                        Icons.Default.Notifications,
                                        contentDescription = if (unread > 0) "Notifications ($unread unread)" else "Notifications",
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                        SyncStatusBadge(
                            isSyncingFlow = viewModel.isSyncing,
                            pendingCountFlow = viewModel.pendingSyncCount,
                            onForceSync = { viewModel.forceSync() },
                            onOpenIssues = onNavigateToSyncIssues,
                        )
                    },
                )
                WaveDivider()
            }
        },
        // §3.8 L543 — FAB only shown on phone; tablet uses action row in TopAppBar.
        floatingActionButton = {
            if (!isTablet) {
                DashboardFab(
                    onNewTicket = onCreateTicket,
                    onNewCustomer = onCreateCustomer,
                    onLogSale = onLogSale,
                    onScanBarcode = onScanBarcode,
                    expandedState = fabExpandedState,
                )
            }
        },
    ) { scaffoldPadding ->
    // [P1] Scrim overlay wraps content so it renders above the list
    // but below the Scaffold's FAB layer. The scrim Box is drawn after
    // PullToRefreshBox so it appears on top in Z-order.
    Box(modifier = Modifier.fillMaxSize()) {
    PullToRefreshBox(
        isRefreshing = state.isRefreshing,
        onRefresh = { viewModel.refresh() },
        modifier = Modifier.fillMaxSize().padding(scaffoldPadding),
    ) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // §3.7 L538 — Announcement banner (sticky, top-of-feed position)
        announcement?.let { ann ->
            item {
                AnnouncementBanner(
                    announcement = ann,
                    onDismiss = { viewModel.dismissAnnouncement(it) },
                    onLearnMore = { id ->
                        android.util.Log.i("Dashboard", "announcement_learn_more id=$id")
                    },
                )
            }
        }

        // U9 fix: top-of-screen summary banner only appears if ANY section
        // failed, and each failing section also gets its own in-place banner
        // below. This tells users exactly which chunk of the dashboard is
        // stale instead of a generic "some data may be outdated" soup.
        if (state.hasAnyError) {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small,
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.CloudOff,
                            // decorative — non-clickable banner; sibling "Some sections failed…" Text carries the announcement
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
                        )
                        Text(
                            "Some sections failed to load. Pull to refresh.",
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                            color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
                        )
                    }
                }
            }
        }

        // §3.14 L570 — Cached data banner. Shown when network failed but cached data
        // is available. Uses tertiaryContainer surface (informational, not error).
        // ReduceMotion-aware fade controlled by [rememberReduceMotion].
        if (state.showCachedBanner) {
            item {
                DashboardCachedBanner(
                    visible = true,
                    onRetry = { viewModel.refresh() },
                    reduceMotion = reduceMotion,
                )
            }
        }

        // CROSS45: WaveDivider moved to topBar slot (directly below the app bar)
        // so placement is consistent across every list/dashboard screen.

        // §3.14 L573/L574 — Setup checklist card for brand-new tenants.
        // Shown when setupCompletedSteps < setupTotalSteps (default 5).
        // Contains completion ring (L581) in the top-right corner.
        // onNavigateToSetup is nullable — card hidden when nav is not wired.
        if (onNavigateToSetup != null) {
            item {
                SetupChecklistCard(
                    completedSteps = state.setupCompletedSteps,
                    totalSteps = state.setupTotalSteps,
                    onNavigateToSetup = onNavigateToSetup,
                )
            }
        }

        // §3.5 — getting-started checklist. Auto-hides at 100% complete or
        // when explicitly dismissed; keys off local Room counts + prefs so
        // it works offline.
        item {
            OnboardingChecklist()
        }

        // §3.11 — Clock in/out tile. Surfaces current state pulled from
        // GET /employees and routes to the dedicated screen on tap.
        if (onClockInOut != null) {
            item {
                ClockInTile(
                    onOpen = onClockInOut,
                    snackbarHostState = clockSnackbarHostState,
                )
            }
        }

        // [P1] Date sub-line — greeting moved to top bar; only the date remains
        // here as a contextual anchor.
        // CROSS46: route through the canonical DateFormatter.formatAbsolute
        // ("April 16, 2026") instead of the ad-hoc "EEEE, MMMM d" pattern.
        item {
            val todayFormatted = remember {
                com.bizarreelectronics.crm.util.DateFormatter.formatAbsolute(System.currentTimeMillis())
            }
            Text(
                todayFormatted,
                modifier = Modifier.padding(horizontal = 16.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // U9 fix: KPI stats error banner in the KPI section.
        if (state.statsError != null) {
            item {
                SectionErrorBanner(
                    "KPIs failed to load: ${state.statsError}",
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // §3 L491 — Date-range selector. Sits above the KPI heading so users
        // understand the grid values reflect the selected window.
        item {
            DateRangeSelector(
                selectedPreset = selectedPreset,
                onRangeSelected = { range ->
                    // Resolve which preset matches the new range so the button
                    // row stays highlighted correctly.
                    selectedPreset = DashboardDatePreset.entries.firstOrNull { preset ->
                        preset != DashboardDatePreset.CUSTOM &&
                            preset.toDateRange().from == range.from &&
                            preset.toDateRange().to == range.to
                    } ?: DashboardDatePreset.CUSTOM
                    viewModel.setCurrentRange(range)
                },
                modifier = Modifier.padding(vertical = 4.dp),
            )
        }

        // §3.17 L607-L608 — Saved dashboard tabs (Default | Morning | End of day | + Add).
        if (layoutConfig.savedDashboards.isNotEmpty() || true /* always show Default tab */) {
            item {
                SavedDashboardTabs(
                    savedDashboards = layoutConfig.savedDashboards,
                    activeName = layoutConfig.activeDashboardName,
                    onSelect = { name -> viewModel.activateSavedDashboard(name) },
                    onAdd = { viewModel.saveCurrentLayoutAs(it) },
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // §3.17 L610 — First-launch "Show all tiles" affordance.
        if (layoutConfig.isFirstLaunch) {
            item {
                TextButton(
                    onClick = { viewModel.showAllTiles() },
                    modifier = Modifier
                        .padding(horizontal = 16.dp)
                        .semantics { contentDescription = "Show all available tiles" },
                ) {
                    Text("Show all tiles")
                }
            }
        }

        // KPI section heading — a11y: heading() so TalkBack announces "Today's KPIs, heading"
        item {
            Text(
                "${currentRange.label} KPIs",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )
        }

        // §3 L497 — empty state for new tenants. Shown only when all KPIs are zero.
        // Once any KPI becomes non-zero the grid is rendered instead.
        if (state.allKpisZero && !state.isLoading) {
            item {
                // §3.14 L571 — firstLaunch: show per-KPI stub emoji illustrations
                // when the tenant has no data yet. Uses EmptyStateIllustration wrapper.
                if (state.firstLaunch) {
                    EmptyStateIllustration(
                        emoji = "📋",
                        title = "No tickets yet",
                        subtitle = "Create your first repair ticket to get started.",
                        primaryCta = "New Ticket",
                        onPrimaryCta = onCreateTicket,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                } else {
                    DashboardEmptyState(onCreateTicket = onCreateTicket)
                }
            }
        } else {
            // §3 L488 — KpiGrid (responsive: 2/3/4 cols by WindowMode).
            // a11y: liveRegion=Polite so TalkBack announces updated values
            // after a sync without interrupting the user.
            item {
                KpiGrid(
                    tiles = kpiTiles,
                    // §3.17 L496 — Long-press any tile to open the customization sheet.
                    modifier = Modifier
                        .semantics { liveRegion = LiveRegionMode.Polite }
                        .combinedClickable(
                            onClick = {},
                            onLongClick = { showCustomizationSheet = true },
                            onLongClickLabel = "Customize dashboard tiles",
                        ),
                )
            }
        }

        // §3.12 L562 — Team Inbox tile. Hidden when teamInboxCount is null (404).
        teamInboxCount?.let { inboxCount ->
            item {
                TeamInboxTile(
                    unreadCount = inboxCount,
                    onNavigateToInbox = {
                        android.util.Log.i("Dashboard", "team_inbox_tap count=$inboxCount — inbox route not yet available")
                    },
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // CROSS1: entire "My Queue" section hidden when assignment feature is off
        // OR when the user has toggled the section off via dashboardShowMyQueue pref.
        if (state.assignmentEnabled && showMyQueue) {
            // U9 fix: My Queue error banner in-place.
            if (state.queueError != null) {
                item {
                    SectionErrorBanner(
                        "My Queue failed to refresh: ${state.queueError}",
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }

            // §3.4 L519–L526 — polished My Queue section with urgency chips,
            // device field, time-since-opened, and long-press context menu.
            item {
                MyQueueSection(
                    tickets = state.myQueue.map { t ->
                        MyQueueTicket(
                            id = t.id,
                            orderId = t.orderId,
                            customerName = t.customerName,
                            device = "", // device not in TicketSummary; stub until enriched
                            timeSinceOpened = "", // stub — VM will add once queue entity carries created_at
                            urgency = when {
                                t.statusName.contains("urgent", ignoreCase = true) ||
                                    t.statusName.contains("critical", ignoreCase = true) -> TicketUrgency.Critical
                                t.statusName.contains("waiting", ignoreCase = true) ||
                                    t.statusName.contains("parts", ignoreCase = true) -> TicketUrgency.High
                                t.statusName.contains("in progress", ignoreCase = true) ||
                                    t.statusName.contains("repair", ignoreCase = true) -> TicketUrgency.Medium
                                else -> TicketUrgency.Normal
                            },
                            statusName = t.statusName,
                        )
                    },
                    onViewAll = onNavigateToTickets,
                    onTicketClick = onNavigateToTicket,
                )
            }
        }

        // U9 fix: Needs Attention error banner in-place.
        if (state.attentionError != null) {
            item {
                SectionErrorBanner(
                    "Needs Attention failed to load: ${state.attentionError}",
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // Needs Attention
        if (state.needsAttention.isNotEmpty()) {
            item {
                // a11y: heading() so TalkBack announces "Needs Attention, heading" on focus
                Text(
                    "Needs Attention",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .semantics { heading() },
                )
            }
            items(state.needsAttention, key = { "${it.type}:${it.message}" }) { item ->
                // [P2] WarningBg replaced with WarningAmber.copy(alpha=0.12f) so it
                // doesn't glow as a light-mode pastel on the dark OLED ramp.
                AttentionCard(
                    item = item,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        }

        // §3.3 L510–L514 — Needs-Attention row-level cards.
        // Single insertion between KPI grid and BI Insights widgets per spec.
        item {
            val attentionItems by viewModel.needsAttentionItems.collectAsState()
            NeedsAttentionSection(
                items = attentionItems,
                onItemClick = { route ->
                    when {
                        route.startsWith("tickets") -> onNavigateToTickets()
                        route.startsWith("inventory") -> onNavigateToInventory?.invoke()
                        else -> { /* unknown route — no-op */ }
                    }
                },
                onDismiss = viewModel::dismissAttention,
                onMarkSeen = viewModel::markAttentionSeen,
                appPreferences = viewModel.appPreferences,
            )
        }

        // §3.6 L534 — Activity Feed card
        item {
            ActivityFeedCard(
                items = recentActivity,
                // §3.16 L593 — "Show more" navigates to the full Activity Feed screen.
                onShowMore = onNavigateToActivityFeed,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }

        // §3.2 L500–L506 — BI Widgets "Insights" section.
        // §3.14 L572 — wrapped in PermissionGatedCard when canViewReports is false.
        // Widgets flow 1-column on Phone, 2-column on Tablet/Desktop.
        item {
            PermissionGatedCard(
                requiredPermission = "Reports",
                hasPermission = state.canViewReports,
                modifier = Modifier.padding(horizontal = 0.dp),
            ) {
                InsightsSection(viewModel = viewModel)
            }
        }
    }
    }
    // §3.5 L531 — Celebratory modal overlay (ModalBottomSheet; rendered at the
    // Box level so it appears above the list content in Z-order).
    CelebratoryModal(
        visible = showCelebratoryModal,
        onDismiss = { viewModel.dismissCelebratoryModal() },
        reduceMotion = reduceMotion,
    )

    // §3.17 L496 — Customization sheet: opened by long-press on any tile.
    if (showCustomizationSheet) {
        DashboardCustomizationSheet(
            layoutConfig = layoutConfig,
            reduceMotion = reduceMotion,
            onSave = { orderedTiles, hiddenTiles ->
                viewModel.applyCustomization(orderedTiles, hiddenTiles)
                showCustomizationSheet = false
            },
            onDismiss = { showCustomizationSheet = false },
        )
    }

    // Scrim: rendered after PullToRefreshBox so it sits above the list in Z-order.
    // Tapping collapses the FAB; only visible when FAB is expanded.
    if (fabExpandedState.value) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.32f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = { fabExpandedState.value = false },
                ),
        )
    }
    } // end scrim Box
    }
}

// ---------------------------------------------------------------------------
// Queue ticket row — BrandCard treatment + BrandStatusBadge
// ---------------------------------------------------------------------------

@Composable
private fun QueueTicketRow(
    ticket: TicketSummary,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            // a11y: merge children so TalkBack reads the ticket as one unit; Role.Button
            // signals it is actionable; contentDescription provides the full announcement.
            .semantics(mergeDescendants = true) {
                contentDescription = "Ticket ${ticket.orderId}, ${ticket.customerName}, status: ${ticket.statusName}. Tap to open."
                role = Role.Button
            }
            .clickable(onClick = onClick)
            .defaultMinSize(minHeight = 48.dp)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            ),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                // Order ID in titleSmall — reads like a code/ID
                Text(
                    ticket.orderId,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    ticket.customerName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            // [P1] BrandStatusBadge replaces raw color-parsed Surface pill
            BrandStatusBadge(
                label = ticket.statusName,
                status = ticket.statusName,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Attention card — WarningAmber dynamic alpha instead of hardcoded WarningBg
// ---------------------------------------------------------------------------

@Composable
private fun AttentionCard(item: AttentionItem, modifier: Modifier = Modifier) {
    // [P2] Dynamic alpha so the card reads correctly on the dark OLED ramp
    // rather than glowing with the light-mode #FEF3C7 pastel.
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = WarningAmber.copy(alpha = 0.12f),
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // decorative — non-clickable alert card; sibling item.message Text carries the announcement
            Icon(Icons.Default.Warning, contentDescription = null, tint = WarningAmber, modifier = Modifier.size(20.dp))
            Text(item.message, style = MaterialTheme.typography.bodySmall)
        }
    }
}

// ---------------------------------------------------------------------------
// SectionErrorBanner — toned down per spec
// ---------------------------------------------------------------------------

// U9 fix: in-place per-section error banner.
// [P1] Toned down: onErrorContainer at 90% alpha, 12sp, icon at 14dp.
@Composable
private fun SectionErrorBanner(message: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.errorContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.ErrorOutline,
                // decorative — non-clickable section error banner; sibling message Text carries the announcement
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
            )
            Text(
                message,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.9f),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// KpiCardView — BrandCard treatment + display-condensed value + breathing top pad
// ---------------------------------------------------------------------------

// [P1] BrandCard treatment: 1px outline border, no elevation shadow, 14dp radius.
// Display-condensed (headlineMedium = Barlow Condensed via Typography.kt) for value.
// All KPI values use primary purple — icon tint carries secondary differentiation.
// 20dp top padding so the icon breathes.
@Composable
fun KpiCardView(kpi: KpiCard, modifier: Modifier = Modifier) {
    // §3.1 / §26 — clickable tile wrapper. Only applied when the KpiCard provides
    // an onClick; inert tiles (e.g. Revenue Today) stay non-focusable so
    // TalkBack doesn't announce a button that does nothing.
    //
    // a11y: mergeDescendants collapses icon + value + label into one node so
    // TalkBack reads the tile as a single announcement rather than three
    // separate focus stops. contentDescription gives the full human-readable
    // string. Role.Button is only added on clickable tiles — inert tiles get
    // no role so TalkBack does not call them buttons.
    val semanticsModifier = if (kpi.onClick != null) {
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = "${kpi.label}: ${kpi.value}. Tap to view list."
            role = Role.Button
        }
    } else {
        // a11y: inert tile — still merge so TalkBack reads value + label together,
        // but no Role.Button since there is no action.
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = "${kpi.label}: ${kpi.value}."
        }
    }
    val clickModifier = if (kpi.onClick != null) {
        Modifier.clickable(onClick = kpi.onClick)
    } else {
        Modifier
    }
    Card(
        modifier = modifier
            // a11y: 48dp floor ensures the tile meets the Material 3 minimum touch target
            .defaultMinSize(minHeight = 48.dp)
            .then(semanticsModifier)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .then(clickModifier),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 16.dp)) {
            kpi.icon()
            Spacer(modifier = Modifier.height(8.dp))
            // Monochrome + state: value color mirrors the icon tint (state hue
            // when non-zero, muted when zero). Keeps the grid calm on empty
            // screens and only surfaces color where it's load-bearing.
            Text(
                kpi.value,
                style = MaterialTheme.typography.headlineMedium, // Barlow Condensed via Typography
                color = kpi.iconTint,
            )
            Text(
                kpi.label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// §3.2 L500–L506 — Insights section (BI widgets)
// ---------------------------------------------------------------------------

/**
 * "Insights" section rendered below the KPI grid in [DashboardScreen].
 *
 * Layout adapts to [WindowMode]:
 *   - Phone   → single-column vertical stack
 *   - Tablet / Desktop → 2-column grid using Row pairs
 *
 * All widgets handle empty / stub data gracefully — this composable never
 * crashes regardless of what the ViewModel emits.
 */
@Composable
private fun InsightsSection(viewModel: DashboardViewModel) {
    val windowMode = rememberWindowMode()
    val isTwoCol = windowMode != WindowMode.Phone
    // §3.19 L615 — BI widgets section spacing follows LocalDashboardDensity.
    val dashboardDensity = LocalDashboardDensity.current
    val sectionSpacing = dashboardDensity.baseSpacing

    // Collect all BI state flows
    val profitTrend by viewModel.profitTrend.collectAsState()
    val busyHours by viewModel.busyHours.collectAsState()
    val leaderboard by viewModel.leaderboard.collectAsState()
    val repeatPercent by viewModel.repeatPercent.collectAsState()
    val repeatTrendDelta by viewModel.repeatTrendDelta.collectAsState()
    val churnAtRisk by viewModel.churnAtRisk.collectAsState()
    val forecastCents by viewModel.forecastCents.collectAsState()
    val forecastHistoryDays by viewModel.forecastHistoryDays.collectAsState()
    val missingParts by viewModel.missingParts.collectAsState()

    // Net margin from latest trend point (last value = most recent day)
    val netMarginPercent = profitTrend.lastOrNull()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = sectionSpacing),
        verticalArrangement = Arrangement.spacedBy(sectionSpacing),
    ) {
        // Section heading
        Text(
            text = "Insights",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.semantics { heading() },
        )

        if (isTwoCol) {
            // 2-column layout for tablet/desktop
            // Row 1: Profit Hero + Repeat Customer
            Row(
                horizontalArrangement = Arrangement.spacedBy(sectionSpacing),
                modifier = Modifier.fillMaxWidth(),
            ) {
                ProfitHeroCard(
                    trendPoints = profitTrend,
                    netMarginPercent = netMarginPercent,
                    appPreferences = viewModel.appPreferences,
                    modifier = Modifier.weight(1f),
                )
                RepeatCustomerCard(
                    repeatPercent = repeatPercent,
                    trendDelta = repeatTrendDelta,
                    modifier = Modifier.weight(1f),
                )
            }
            // Row 2: Churn Alert + Forecast
            Row(
                horizontalArrangement = Arrangement.spacedBy(sectionSpacing),
                modifier = Modifier.fillMaxWidth(),
            ) {
                ChurnAlertCard(
                    atRiskCount = churnAtRisk,
                    modifier = Modifier.weight(1f),
                )
                ForecastCard(
                    forecastRevenue = forecastCents,
                    historyDays = forecastHistoryDays,
                    modifier = Modifier.weight(1f),
                )
            }
            // Row 3: Leaderboard (full width)
            LeaderboardCard(
                entries = leaderboard,
                modifier = Modifier.fillMaxWidth(),
            )
            // Row 4: Busy Hours heatmap (full width — 24 columns need width)
            BusyHoursHeatmap(
                data = busyHours,
                modifier = Modifier.fillMaxWidth(),
            )
            // Row 5: Missing Parts (full width)
            MissingPartsCard(
                items = missingParts,
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            // 1-column layout for phones
            ProfitHeroCard(
                trendPoints = profitTrend,
                netMarginPercent = netMarginPercent,
                appPreferences = viewModel.appPreferences,
            )
            RepeatCustomerCard(
                repeatPercent = repeatPercent,
                trendDelta = repeatTrendDelta,
            )
            ChurnAlertCard(atRiskCount = churnAtRisk)
            ForecastCard(
                forecastRevenue = forecastCents,
                historyDays = forecastHistoryDays,
            )
            LeaderboardCard(entries = leaderboard)
            BusyHoursHeatmap(data = busyHours)
            MissingPartsCard(items = missingParts)
        }
    }
}

