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
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class NotificationUiState(
    val notifications: List<NotificationEntity> = emptyList(),
    val unreadCount: Int = 0,
    val isLoading: Boolean = true,
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
        // Collect cached notifications from Room for instant display
        viewModelScope.launch {
            notificationDao.getAll().collect { entities ->
                _state.value = _state.value.copy(notifications = entities)
            }
        }
        // Collect unread count from Room
        viewModelScope.launch {
            notificationDao.getUnreadCount().collect { count ->
                _state.value = _state.value.copy(unreadCount = count)
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
                _state.value = _state.value.copy(isLoading = false)
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
                _state.value = _state.value.copy(isLoading = false)
            } catch (e: Exception) {
                Log.d(TAG, "API fetch failed: ${e.message}")
                _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Failed to load")
            }
        }
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
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Notifications")
                        if (state.unreadCount > 0) {
                            Badge { Text(state.unreadCount.toString()) }
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.load() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    if (state.unreadCount > 0) {
                        TextButton(onClick = { viewModel.markAllRead() }) {
                            Text("Mark All Read")
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = { viewModel.load() }) { Text("Retry") }
                    }
                }
            }
            state.notifications.isEmpty() -> {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.NotificationsNone, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("No notifications", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            else -> {
                LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                    items(state.notifications, key = { it.id }) { notification ->
                        val isUnread = !notification.isRead
                        val icon = when (notification.type) {
                            "ticket" -> Icons.Default.ConfirmationNumber
                            "invoice" -> Icons.Default.Receipt
                            "sms" -> Icons.Default.Chat
                            else -> Icons.Default.Info
                        }

                        ListItem(
                            modifier = Modifier
                                .clickable {
                                    if (isUnread) viewModel.markRead(notification.id)
                                    onNotificationClick(notification.type, notification.entityId)
                                }
                                .then(
                                    if (isUnread) Modifier.background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.15f))
                                    else Modifier
                                ),
                            headlineContent = {
                                Text(notification.title, fontWeight = if (isUnread) FontWeight.Bold else FontWeight.Normal)
                            },
                            supportingContent = { Text(notification.message) },
                            leadingContent = {
                                Box {
                                    Icon(icon, contentDescription = notification.type)
                                    if (isUnread) {
                                        Badge(modifier = Modifier.align(Alignment.TopEnd).size(8.dp))
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
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}
