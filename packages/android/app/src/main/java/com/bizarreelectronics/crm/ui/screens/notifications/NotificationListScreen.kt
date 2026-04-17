package com.bizarreelectronics.crm.ui.screens.notifications

import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.NotificationDao
import com.bizarreelectronics.crm.data.local.db.entities.NotificationEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.NotificationApi
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import javax.inject.Inject

data class NotificationUiState(
    val notifications: List<NotificationEntity> = emptyList(),
    val unreadCount: Int = 0,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class NotificationListViewModel @Inject constructor(
    private val notificationApi: NotificationApi,
    private val notificationDao: NotificationDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(NotificationUiState())
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

    companion object {
        private const val TAG = "NotificationListVM"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationListScreen(
    onNotificationClick: (String, Long?) -> Unit,
    viewModel: NotificationListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Notifications",
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
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                // Brand skeleton replacing bare CircularProgressIndicator (§1 P0)
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                )
            }
            state.error != null -> {
                // Brand error surface replacing hand-rolled Box/Column (§1 P1)
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load notifications",
                        onRetry = { viewModel.load() },
                    )
                }
            }
            state.notifications.isEmpty() -> {
                // Shared EmptyState with WaveDivider replacing hand-rolled Column (§3 P2)
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.NotificationsNone,
                        title = "No notifications",
                        subtitle = "You're all caught up",
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
                    modifier = Modifier.fillMaxSize().padding(padding),
                ) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    // CROSS16-ext: reserve bottom room even without a FAB so
                    // the last row can scroll past system-gesture area and
                    // stays consistent with other list screens.
                    contentPadding = PaddingValues(bottom = 96.dp),
                ) {
                    items(state.notifications, key = { it.id }) { notification ->
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
