package com.bizarreelectronics.crm.ui.screens.notifications

import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.NotificationDao
import com.bizarreelectronics.crm.data.local.db.entities.NotificationEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.NotificationApi
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * CROSS55: high-level bucket for filter chips on the Notifications list.
 *
 * Semantics:
 *   - ALL       → no filter
 *   - UNREAD    → rows where `!isRead`
 *   - MENTIONS  → rows where `type == "mention"` (mirrors `team_mentions`
 *                 wire shape; no-op today for seeded notifications that carry
 *                 `ticket` / `invoice` / `sms` / `system` types)
 *   - SYSTEM    → rows where `type == "system"`
 *
 * Kept as an enum (not a string) so the chip row can render a static label
 * list without allocating at recompose time. Add new buckets by extending
 * the enum + the `matches` branch below.
 */
enum class NotificationFilter(val label: String) {
    ALL("All"),
    UNREAD("Unread"),
    MENTIONS("Mentions"),
    SYSTEM("System"),
    ;

    fun matches(n: NotificationEntity): Boolean = when (this) {
        ALL -> true
        UNREAD -> !n.isRead
        MENTIONS -> n.type.equals("mention", ignoreCase = true)
        SYSTEM -> n.type.equals("system", ignoreCase = true)
    }
}

/**
 * CROSS55 §13.1 tabs — four top-level scopes that sit above the type filter
 * chips. Tab filters are applied first; chip filters narrow within the tab.
 *
 *  - ALL        → all notifications (no scope restriction)
 *  - UNREAD     → `!isRead` — same predicate as NotificationFilter.UNREAD but
 *                 surfaced as a primary tab so it's one tap away, not buried in chips
 *  - ASSIGNED   → `userId == currentUserId` — notifications addressed to the
 *                 logged-in user.  Uses `userId` because that is the field set to
 *                 `authPreferences.userId` at upsert time; we have no separate
 *                 `assignedToUserId` column in this schema.
 *  - MENTIONS   → `type == "mention"` — mirrors the chip but promoted to tab
 *                 for discoverability.
 */
enum class NotificationTab(val label: String) {
    ALL("All"),
    UNREAD("Unread"),
    ASSIGNED("Assigned to me"),
    MENTIONS("Mentions"),
    ;

    /** Returns true when [n] belongs in this tab for [currentUserId]. */
    fun matches(n: NotificationEntity, currentUserId: Long): Boolean = when (this) {
        ALL -> true
        UNREAD -> !n.isRead
        ASSIGNED -> n.userId == currentUserId
        MENTIONS -> n.type.equals("mention", ignoreCase = true)
    }
}

data class NotificationUiState(
    val notifications: List<NotificationEntity> = emptyList(),
    val unreadCount: Int = 0,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    // CROSS55: search query + active filter for the Notifications list parity
    // with Tickets / Inventory / Customers. The filtered view is derived on
    // the fly in [filteredNotifications] so we don't have to re-query Room
    // on every keystroke.
    val searchQuery: String = "",
    val selectedFilter: NotificationFilter = NotificationFilter.ALL,
    // §13.1 tabs — selected tab index mirrored here so the VM can expose
    // per-tab unread counts without the Composable doing the counting itself.
    val selectedTab: NotificationTab = NotificationTab.ALL,
    // current user ID from AuthPreferences — needed to evaluate the
    // ASSIGNED tab predicate in-memory without an extra DAO query.
    val currentUserId: Long = 0L,
) {
    /**
     * CROSS55: filtered + searched list derived from `notifications`. Applied
     * in-memory (Room already returns a bounded recent-first list) so typing
     * feels instant and filter chips flip without waiting on a DB round-trip.
     *
     * §13.1 tabs — tab filter is applied first (broader scope), then the
     * type chip filter narrows within it. Search runs last.
     */
    val filteredNotifications: List<NotificationEntity>
        get() {
            val q = searchQuery.trim()
            return notifications
                .asSequence()
                .filter { selectedTab.matches(it, currentUserId) }
                .filter { selectedFilter.matches(it) }
                .filter { n ->
                    if (q.isEmpty()) true
                    else n.title.contains(q, ignoreCase = true) ||
                        n.message.contains(q, ignoreCase = true)
                }
                .toList()
        }

    /**
     * §13.1 — per-tab unread count for badge rendering. Ignores the active
     * chip filter so the badge reflects the raw tab scope (not a narrowed sub-view).
     */
    fun unreadCountForTab(tab: NotificationTab): Int =
        notifications.count { tab.matches(it, currentUserId) && !it.isRead }
}

@HiltViewModel
class NotificationListViewModel @Inject constructor(
    private val notificationApi: NotificationApi,
    private val notificationDao: NotificationDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        NotificationUiState(currentUserId = authPreferences.userId),
    )
    val state = _state.asStateFlow()

    init {
        // @audit-fixed: previously two separate launch blocks each emitted into
        // _state.value.copy(...) — they could clobber each other when both
        // flows tick within the same Compose recomposition window, briefly
        // showing a stale notifications list with a fresh unread count (or
        // vice-versa). Using combine ensures one atomic emission per change.
        viewModelScope.launch {
            combine(
                notificationDao.getAll(),
                notificationDao.getUnreadCount(),
            ) { entities, count -> entities to count }
                .collect { (entities, count) ->
                    _state.value = _state.value.copy(
                        notifications = entities,
                        unreadCount = count,
                    )
                }
        }
        // Fetch from API to sync Room
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            if (!serverMonitor.isEffectivelyOnline.value) {
                // Offline: Room flows already populating state
                _state.value = _state.value.copy(isLoading = false, isRefreshing = false)
                return@launch
            }
            try {
                val response = notificationApi.getNotifications()
                val apiNotifications = response.data?.notifications ?: emptyList()
                // Upsert API results into Room (flows will auto-update state)
                notificationDao.insertAll(apiNotifications.map { item ->
                    NotificationEntity(
                        id = item.id,
                        userId = item.userId ?: authPreferences.userId,
                        type = item.type ?: "system",
                        title = item.title ?: "",
                        message = item.message ?: "",
                        entityType = item.entityType,
                        entityId = item.entityId,
                        isRead = item.isRead != 0,
                        createdAt = item.createdAt ?: "",
                    )
                })
                _state.value = _state.value.copy(isLoading = false, isRefreshing = false)
            } catch (e: Exception) {
                Log.d(TAG, "API fetch failed: ${e.message}")
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = e.message ?: "Failed to load",
                )
            }
        }
    }

    // D5-7: force-refresh hook for PullToRefreshBox. Sets isRefreshing so the
    // spinner renders, then load() clears it when the API call resolves.
    // Non-breaking — load() still callable directly from the top-bar Refresh
    // icon; this just gives the user a swipe-down gesture when the Room cache
    // has drifted from the server.
    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        load()
    }

    fun markRead(id: Long) {
        viewModelScope.launch {
            // Update Room immediately (flow auto-updates UI)
            notificationDao.markRead(id)
            // Fire-and-forget API call if online
            if (serverMonitor.isEffectivelyOnline.value) {
                try {
                    notificationApi.markRead(id)
                } catch (e: Exception) {
                    Log.d(TAG, "API markRead failed: ${e.message}")
                }
            }
        }
    }

    fun markAllRead() {
        viewModelScope.launch {
            // Update Room immediately (flow auto-updates UI)
            notificationDao.markAllRead(authPreferences.userId)
            // Fire-and-forget API call if online
            if (serverMonitor.isEffectivelyOnline.value) {
                try {
                    notificationApi.markAllRead()
                } catch (e: Exception) {
                    Log.d(TAG, "API markAllRead failed: ${e.message}")
                }
            }
        }
    }

    // CROSS55: search query + filter chip handlers. Both update state only —
    // filtering happens inside [NotificationUiState.filteredNotifications] so
    // we avoid a Room round-trip per keystroke.
    fun onSearchChange(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun onFilterChange(filter: NotificationFilter) {
        _state.value = _state.value.copy(selectedFilter = filter)
    }

    // §13.1 — tab change handler. Switching tabs resets the type-chip filter to
    // ALL so the new tab always shows its full scope on first open. This matches
    // the pattern used by Tickets (status tabs reset search on tab switch).
    fun onTabChange(tab: NotificationTab) {
        _state.value = _state.value.copy(
            selectedTab = tab,
            selectedFilter = NotificationFilter.ALL,
        )
    }

    companion object {
        private const val TAG = "NotificationListVM"
    }
}

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun NotificationListScreen(
    onNotificationClick: (String, Long?) -> Unit,
    // CROSS55: top-bar settings-gear routes here. Callers (AppNavGraph) wire
    // this to Screen.NotificationSettings so the inbox and prefs stay
    // separate per CROSS54.
    onNavigateToPrefs: () -> Unit = {},
    viewModel: NotificationListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    // CROSS55: derive the view list once per recomposition from the backing
    // Room snapshot + current chip/search state. Using a `remember(...)` keyed
    // on the inputs keeps the list stable for equal filter + equal source.
    val visible = remember(
        state.notifications,
        state.searchQuery,
        state.selectedFilter,
        state.selectedTab,
    ) { state.filteredNotifications }

    Scaffold(
        topBar = {
            // CROSS45: WaveDivider docked directly below the TopAppBar — canonical
            // placement for every list screen.
            Column {
                BrandTopAppBar(
                    // CROSS54: renamed from "Notifications" → "Activity" so the
                    // Settings entry labelled "Notifications" is reserved for
                    // preferences (push enable, categories, quiet hours). The
                    // nav route remains "notifications" so deep-links and FCM
                    // extras (MainActivity.kt maps "notification" → "notifications")
                    // keep working.
                    title = "Activity",
                    actions = {
                        // Unread count badge — primary purple, not Material error red
                        if (state.unreadCount > 0) {
                            BadgedBox(
                                modifier = Modifier.padding(end = 4.dp),
                                badge = {
                                    Badge(
                                        containerColor = MaterialTheme.colorScheme.primary,
                                        contentColor = MaterialTheme.colorScheme.onPrimary,
                                    ) {
                                        Text(state.unreadCount.toString())
                                    }
                                },
                            ) {
                                // Invisible anchor for the badge; the badge itself carries the count
                                Spacer(modifier = Modifier.size(0.dp))
                            }
                        }
                        IconButton(onClick = { viewModel.load() }) {
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "Refresh",
                            )
                        }
                        if (state.unreadCount > 0) {
                            TextButton(onClick = { viewModel.markAllRead() }) {
                                Text("Mark all read")
                            }
                        }
                        // CROSS55: settings-gear → notification preferences.
                        // Distinct from the inbox itself (CROSS54) so users
                        // can toggle push/email/etc. without re-opening
                        // Settings from scratch.
                        IconButton(onClick = onNavigateToPrefs) {
                            Icon(
                                Icons.Default.Settings,
                                contentDescription = "Notification preferences",
                            )
                        }
                    },
                )
                WaveDivider()

                // §13.1 tabs — All / Unread / Assigned to me / Mentions.
                // Placed inside the topBar Column so it scrolls with the app bar
                // on very short screens (follows Material 3 tab-below-toolbar pattern).
                // Each tab shows a count badge when there are unread items in that scope.
                ScrollableTabRow(
                    selectedTabIndex = NotificationTab.entries.indexOf(state.selectedTab),
                    edgePadding = 16.dp,
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.primary,
                    divider = {},
                ) {
                    NotificationTab.entries.forEach { tab ->
                        val tabUnread = state.unreadCountForTab(tab)
                        Tab(
                            selected = state.selectedTab == tab,
                            onClick = { viewModel.onTabChange(tab) },
                            text = {
                                if (tabUnread > 0) {
                                    BadgedBox(
                                        badge = {
                                            Badge(
                                                containerColor = MaterialTheme.colorScheme.primary,
                                                contentColor = MaterialTheme.colorScheme.onPrimary,
                                            ) {
                                                Text(
                                                    tabUnread.toString(),
                                                    fontSize = 10.sp,
                                                )
                                            }
                                        },
                                    ) {
                                        Text(tab.label)
                                    }
                                } else {
                                    Text(tab.label)
                                }
                            },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // CROSS55: search bar — matches TicketList / InventoryList placement
            // (padded, above the filter chips).
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChange(it) },
                placeholder = "Search notifications...",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // CROSS55: filter chip row — All / Unread / Mentions / System.
            LazyRow(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(end = 24.dp),
            ) {
                items(NotificationFilter.entries.toList(), key = { it.name }) { filter ->
                    FilterChip(
                        selected = state.selectedFilter == filter,
                        onClick = { viewModel.onFilterChange(filter) },
                        label = { Text(filter.label) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    // Brand skeleton replacing bare CircularProgressIndicator (§1 P0)
                    BrandSkeleton(
                        rows = 6,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                state.error != null -> {
                    // Brand error surface replacing hand-rolled Box/Column (§1 P1)
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load notifications",
                            onRetry = { viewModel.load() },
                        )
                    }
                }
                visible.isEmpty() -> {
                    // Shared EmptyState with WaveDivider replacing hand-rolled Column (§3 P2)
                    // CROSS55: subtitle adapts so the user can tell an empty list from
                    // an empty FILTERED list (e.g. nothing matches "Unread").
                    val (title, subtitle) = when {
                        state.notifications.isEmpty() -> "No notifications" to "You're all caught up"
                        state.searchQuery.isNotEmpty() -> "No matches" to "Try a different search"
                        else -> "No notifications" to "No ${state.selectedFilter.label.lowercase()} notifications"
                    }
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.NotificationsNone,
                            title = title,
                            subtitle = subtitle,
                        )
                    }
                }
                else -> {
                    // D5-7: wrap notifications list in PullToRefreshBox so users
                    // can force a server re-fetch when the cached list is stale,
                    // without restarting the app.
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            // CROSS16-ext: reserve bottom room even without a FAB so
                            // the last row can scroll past system-gesture area and
                            // stays consistent with other list screens.
                            contentPadding = PaddingValues(bottom = 96.dp),
                        ) {
                            // §13.1 group by day with sticky headers. Each
                            // header renders "Today" / "Yesterday" /
                            // "April 18, 2026" keyed off createdAt. Rows that
                            // couldn't be parsed fall into "Earlier".
                            val grouped = groupNotificationsByDay(visible)
                            grouped.forEach { (label, group) ->
                                stickyHeader(key = "hdr-$label") {
                                    Text(
                                        text = label,
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .background(MaterialTheme.colorScheme.surface)
                                            .padding(horizontal = 16.dp, vertical = 8.dp),
                                    )
                                }
                                items(group, key = { it.id }) { notification ->
                                val isUnread = !notification.isRead
                                val icon = when (notification.type) {
                                    "ticket" -> Icons.Default.ConfirmationNumber
                                    "invoice" -> Icons.Default.Receipt
                                    "sms" -> Icons.Default.Chat
                                    else -> Icons.Default.Info
                                }

                                // Unread rows: BrandCard with primaryContainer bg (sanctioned
                                // highlight usage per §1 "intentional brand-container usage only
                                // for highlight cards"). Read rows: standard surface bg.
                                val containerColor = if (isUnread) {
                                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.08f)
                                } else {
                                    MaterialTheme.colorScheme.surface
                                }

                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(containerColor)
                                        .clickable {
                                            if (isUnread) viewModel.markRead(notification.id)
                                            onNotificationClick(notification.type, notification.entityId)
                                        },
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    // 2dp purple left accent bar for unread — brand list-item pattern
                                    Box(
                                        modifier = Modifier
                                            .width(2.dp)
                                            .height(64.dp)
                                            .background(
                                                if (isUnread) MaterialTheme.colorScheme.primary
                                                else containerColor,
                                            ),
                                    )

                                    ListItem(
                                        modifier = Modifier.weight(1f),
                                        colors = ListItemDefaults.colors(
                                            containerColor = containerColor,
                                        ),
                                        headlineContent = {
                                            Text(
                                                notification.title,
                                                fontWeight = if (isUnread) FontWeight.SemiBold else FontWeight.Normal,
                                            )
                                        },
                                        supportingContent = {
                                            Text(
                                                notification.message,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        },
                                        leadingContent = {
                                            Box {
                                                Icon(
                                                    icon,
                                                    contentDescription = notification.type,
                                                    tint = if (isUnread) {
                                                        MaterialTheme.colorScheme.primary
                                                    } else {
                                                        MaterialTheme.colorScheme.onSurfaceVariant
                                                    },
                                                )
                                                if (isUnread) {
                                                    Badge(
                                                        modifier = Modifier
                                                            .align(Alignment.TopEnd)
                                                            .size(8.dp),
                                                        containerColor = MaterialTheme.colorScheme.primary,
                                                    )
                                                }
                                            }
                                        },
                                        trailingContent = {
                                            Text(
                                                DateFormatter.formatRelative(notification.createdAt),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        },
                                    )
                                }

                                // Brand-aligned divider: outline at 40% alpha (§3 P2)
                                BrandListItemDivider()
                            }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * §13.1 — group notifications by calendar day in the device timezone.
 *
 * Labels: "Today" / "Yesterday" / absolute date for older entries.
 * Parse failures fall into a single "Earlier" bucket at the end. Order
 * preserved within each group (input is already newest-first).
 */
private fun groupNotificationsByDay(
    list: List<com.bizarreelectronics.crm.data.local.db.entities.NotificationEntity>,
): List<Pair<String, List<com.bizarreelectronics.crm.data.local.db.entities.NotificationEntity>>> {
    if (list.isEmpty()) return emptyList()
    val zone = java.time.ZoneId.systemDefault()
    val today = java.time.LocalDate.now(zone)
    val yesterday = today.minusDays(1)
    val absoluteFmt = java.time.format.DateTimeFormatter
        .ofPattern("LLLL d, yyyy", java.util.Locale.getDefault())

    val groups = linkedMapOf<String, MutableList<com.bizarreelectronics.crm.data.local.db.entities.NotificationEntity>>()
    val earlier = "Earlier"

    for (item in list) {
        val raw = item.createdAt
        val label = if (raw.isBlank()) {
            earlier
        } else {
            val parsed = runCatching {
                // Server sends UTC "YYYY-MM-DD HH:MM:SS". Anchor at UTC so
                // devices east of UTC don't misbucket entries near midnight.
                val normalized = raw.replace(' ', 'T')
                java.time.LocalDateTime.parse(normalized)
                    .atZone(java.time.ZoneOffset.UTC)
                    .withZoneSameInstant(zone)
                    .toLocalDate()
            }.getOrNull()
            when (parsed) {
                null -> earlier
                today -> "Today"
                yesterday -> "Yesterday"
                else -> parsed.format(absoluteFmt)
            }
        }
        groups.getOrPut(label) { mutableListOf() }.add(item)
    }
    return groups.map { (k, v) -> k to v }
}
