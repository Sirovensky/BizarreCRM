package com.bizarreelectronics.crm.ui.screens.communications

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.dto.SmsConversationItem
import com.bizarreelectronics.crm.data.repository.SmsRepository
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SmsListUiState(
    val conversations: List<SmsConversationItem> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
)

@HiltViewModel
class SmsListViewModel @Inject constructor(
    private val smsApi: SmsApi,
    private val smsRepository: SmsRepository,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(SmsListUiState())
    val state = _state.asStateFlow()

    init {
        loadConversations()
    }

    fun loadConversations() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.conversations.isEmpty(), error = null)

            if (serverMonitor.isEffectivelyOnline.value) {
                try {
                    val q = _state.value.searchQuery.trim()
                    val keyword = q.ifEmpty { null }
                    val response = smsApi.getConversations(keyword)
                    val conversations = response.data?.conversations ?: emptyList()
                    _state.value = _state.value.copy(
                        conversations = conversations,
                        isLoading = false,
                        isRefreshing = false,
                    )
                    // Also cache messages in Room for offline
                    for (conv in conversations) {
                        smsRepository.getThread(conv.convPhone) // triggers background cache
                    }
                    return@launch
                } catch (e: Exception) {
                    // Fall through to offline mode
                }
            }

            // Offline fallback: show cached conversations from Room
            smsRepository.getConversations().collect { cachedMessages ->
                val offlineConversations = cachedMessages.map { msg ->
                    SmsConversationItem(
                        convPhone = msg.convPhone,
                        lastMessageAt = msg.createdAt,
                        lastMessage = msg.message,
                        lastDirection = msg.direction,
                        messageCount = 0,
                        unreadCount = 0,
                        customer = null,
                        recentTicket = null,
                        isFlagged = false,
                        isPinned = false,
                    )
                }
                val q = _state.value.searchQuery.trim().lowercase()
                val filtered = if (q.isEmpty()) offlineConversations
                else offlineConversations.filter { it.convPhone.contains(q) || it.lastMessage?.lowercase()?.contains(q) == true }
                _state.value = _state.value.copy(
                    conversations = filtered,
                    isLoading = false,
                    isRefreshing = false,
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadConversations()
    }

    private var searchJob: Job? = null

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300L)
            loadConversations()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsListScreen(
    onConversationClick: (String) -> Unit,
    viewModel: SmsListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showNewMsgDialog by remember { mutableStateOf(false) }
    var newMsgPhone by remember { mutableStateOf("") }

    if (showNewMsgDialog) {
        AlertDialog(
            onDismissRequest = {
                showNewMsgDialog = false
                newMsgPhone = ""
            },
            title = { Text("New Conversation") },
            text = {
                OutlinedTextField(
                    value = newMsgPhone,
                    onValueChange = { newMsgPhone = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Phone Number") },
                    placeholder = { Text("e.g. 5551234567") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val normalized = newMsgPhone.trim().replace(Regex("[^0-9]"), "").let {
                            if (it.length == 11 && it.startsWith("1")) it.substring(1) else it
                        }
                        if (normalized.isNotBlank()) {
                            showNewMsgDialog = false
                            newMsgPhone = ""
                            onConversationClick(normalized)
                        }
                    },
                    enabled = newMsgPhone.trim().replace(Regex("[^0-9]"), "").isNotBlank(),
                ) {
                    Text("Start Chat")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showNewMsgDialog = false
                    newMsgPhone = ""
                }) {
                    Text("Cancel")
                }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("Messages") },
                actions = {
                    IconButton(onClick = { showNewMsgDialog = true }) {
                        Icon(Icons.Default.Edit, contentDescription = "New Message")
                    }
                    IconButton(onClick = { viewModel.loadConversations() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search conversations...") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                singleLine = true,
                trailingIcon = {
                    if (state.searchQuery.isNotEmpty()) {
                        IconButton(onClick = { viewModel.onSearchChanged("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear")
                        }
                    }
                },
            )

            when {
                state.isLoading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.height(8.dp))
                            TextButton(onClick = { viewModel.loadConversations() }) { Text("Retry") }
                        }
                    }
                }
                state.conversations.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.Forum,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "No conversations",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn {
                            items(state.conversations, key = { it.convPhone }) { conversation ->
                                ConversationRow(
                                    conversation = conversation,
                                    onClick = { onConversationClick(conversation.convPhone) },
                                )
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ConversationRow(conversation: SmsConversationItem, onClick: () -> Unit) {
    val customer = conversation.customer
    val displayName = listOfNotNull(customer?.firstName, customer?.lastName)
        .joinToString(" ")
        .ifBlank { null }

    val hasUnread = conversation.unreadCount > 0

    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        headlineContent = {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    displayName ?: conversation.convPhone,
                    fontWeight = if (hasUnread) FontWeight.Bold else FontWeight.Normal,
                )
                if (conversation.isPinned) {
                    Icon(
                        Icons.Default.PushPin,
                        contentDescription = "Pinned",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                if (conversation.isFlagged) {
                    Icon(
                        Icons.Default.Flag,
                        contentDescription = "Flagged",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        supportingContent = {
            Text(
                conversation.lastMessage ?: "",
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontWeight = if (hasUnread) FontWeight.SemiBold else FontWeight.Normal,
            )
        },
        trailingContent = {
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    DateFormatter.formatRelative(conversation.lastMessageAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (hasUnread) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Badge { Text("${conversation.unreadCount}") }
                }
            }
        },
        leadingContent = {
            Icon(Icons.Default.Person, contentDescription = null)
        },
    )
}
