package com.bizarreelectronics.crm.ui.screens.notifications

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
import com.bizarreelectronics.crm.data.remote.api.NotificationApi
import com.bizarreelectronics.crm.data.remote.dto.NotificationItem
import com.bizarreelectronics.crm.util.DateFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class NotificationUiState(
    val notifications: List<NotificationItem> = emptyList(),
    val unreadCount: Int = 0,
    val isLoading: Boolean = true,
    val error: String? = null,
)

@HiltViewModel
class NotificationListViewModel @Inject constructor(
    private val notificationApi: NotificationApi,
) : ViewModel() {

    private val _state = MutableStateFlow(NotificationUiState())
    val state = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = notificationApi.getNotifications()
                val notifications = response.data?.notifications ?: emptyList()
                val countResponse = notificationApi.getUnreadCount()
                val unread = countResponse.data?.count ?: 0
                _state.value = _state.value.copy(
                    notifications = notifications,
                    unreadCount = unread,
                    isLoading = false,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Failed to load")
            }
        }
    }

    fun markRead(id: Long) {
        viewModelScope.launch {
            try {
                notificationApi.markRead(id)
                _state.value = _state.value.copy(
                    notifications = _state.value.notifications.map {
                        if (it.id == id) it.copy(isRead = 1) else it
                    },
                    unreadCount = (_state.value.unreadCount - 1).coerceAtLeast(0),
                )
            } catch (_: Exception) {}
        }
    }

    fun markAllRead() {
        viewModelScope.launch {
            try {
                notificationApi.markAllRead()
                _state.value = _state.value.copy(
                    notifications = _state.value.notifications.map { it.copy(isRead = 1) },
                    unreadCount = 0,
                )
            } catch (_: Exception) {}
        }
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
                        val isUnread = notification.isRead == 0
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
                                    onNotificationClick(notification.type ?: "system", notification.entityId)
                                }
                                .then(
                                    if (isUnread) Modifier.background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.15f))
                                    else Modifier
                                ),
                            headlineContent = {
                                Text(notification.title ?: "", fontWeight = if (isUnread) FontWeight.Bold else FontWeight.Normal)
                            },
                            supportingContent = { Text(notification.message ?: "") },
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
