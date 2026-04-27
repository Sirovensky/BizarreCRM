package com.bizarreelectronics.crm.ui.screens.communications

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.InboxApi
import com.bizarreelectronics.crm.data.remote.api.InboxAssignRequest
import com.bizarreelectronics.crm.data.remote.api.InboxConversation
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ── UI state ──────────────────────────────────────────────────────────────────

data class TeamInboxUiState(
    val conversations: List<InboxConversation> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    /** true = team inbox not enabled on this tenant (404 response) */
    val notConfigured: Boolean = false,
    val actionMessage: String? = null,
    val showUnreadOnly: Boolean = false,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class TeamInboxViewModel @Inject constructor(
    private val inboxApi: InboxApi,
) : ViewModel() {

    private val _state = MutableStateFlow(TeamInboxUiState())
    val state = _state.asStateFlow()

    init { loadInbox() }

    fun loadInbox() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.conversations.isEmpty(), error = null)
            runCatching {
                val unread = if (_state.value.showUnreadOnly) true else null
                inboxApi.getInbox(unread = unread)
            }.onSuccess { resp ->
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    conversations = resp.data?.conversations ?: emptyList(),
                )
            }.onFailure { e ->
                val is404 = (e as? HttpException)?.code() == 404
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    notConfigured = is404,
                    error = if (is404) null else (e.message ?: "Failed to load inbox"),
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadInbox()
    }

    fun toggleUnreadFilter() {
        _state.value = _state.value.copy(showUnreadOnly = !_state.value.showUnreadOnly)
        loadInbox()
    }

    /** Optimistically assign a conversation to [userId]. Pass null to unassign. */
    fun assign(conversationId: Long, userId: Long?, userName: String?) {
        // Optimistic update
        _state.value = _state.value.copy(
            conversations = _state.value.conversations.map { c ->
                if (c.id == conversationId) c.copy(assignedToId = userId, assignedToName = userName)
                else c
            },
        )
        viewModelScope.launch {
            runCatching { inboxApi.assignConversation(conversationId, InboxAssignRequest(userId)) }
                .onFailure {
                    _state.value = _state.value.copy(actionMessage = "Assign failed — please retry")
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamInboxScreen(
    onBack: () -> Unit,
    onConversationClick: (phone: String) -> Unit,
    viewModel: TeamInboxViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { snackbarHostState.showSnackbar(it); viewModel.clearActionMessage() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.nav_team_inbox),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                actions = {
                    // Unread toggle
                    IconButton(onClick = { viewModel.toggleUnreadFilter() }) {
                        Icon(
                            if (state.showUnreadOnly) Icons.Default.MarkEmailUnread
                            else Icons.Default.AllInbox,
                            contentDescription = if (state.showUnreadOnly)
                                "Show all conversations"
                            else
                                "Show unread only",
                            tint = if (state.showUnreadOnly)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(onClick = viewModel::refresh) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = "Refresh inbox",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.notConfigured -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.padding(32.dp),
                        ) {
                            Icon(
                                Icons.Default.Inbox,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "Team inbox not enabled on this server",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                state.isLoading -> BrandSkeleton(rows = 6, modifier = Modifier.fillMaxSize())
                state.error != null -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load inbox",
                        onRetry = viewModel::loadInbox,
                    )
                }
                state.conversations.isEmpty() -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.AllInbox,
                        title = "Inbox is empty",
                        subtitle = if (state.showUnreadOnly) "No unread conversations" else "No conversations yet",
                    )
                }
                else -> PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = viewModel::refresh,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn(
                        contentPadding = PaddingValues(bottom = 16.dp),
                    ) {
                        items(state.conversations, key = { it.id }) { conv ->
                            InboxConversationRow(
                                conversation = conv,
                                onClick = { onConversationClick(conv.convPhone) },
                                onAssignToMe = { /* TODO: pass logged-in user id */ },
                                onUnassign = { viewModel.assign(conv.id, null, null) },
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                                thickness = 1.dp,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ── Inbox row ─────────────────────────────────────────────────────────────────

@Composable
private fun InboxConversationRow(
    conversation: InboxConversation,
    onClick: () -> Unit,
    onAssignToMe: () -> Unit,
    onUnassign: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }

    val label = conversation.customerName ?: conversation.convPhone
    val a11y = buildString {
        append("Inbox conversation with $label.")
        if (conversation.unreadCount > 0) append(" ${conversation.unreadCount} unread.")
        conversation.assignedToName?.let { append(" Assigned to $it.") }
        conversation.lastMessage?.let { append(" Last: $it.") }
    }

    ListItem(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics { contentDescription = a11y },
        headlineContent = {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    label,
                    fontWeight = if (conversation.unreadCount > 0) FontWeight.Bold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (conversation.unreadCount > 0) {
                    Badge {
                        Text(
                            conversation.unreadCount.coerceAtMost(99).toString(),
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }
        },
        supportingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                conversation.lastMessage?.let {
                    Text(
                        it,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                conversation.assignedToName?.let { name ->
                    Text(
                        "Assigned to $name",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                } ?: Text(
                    "Unassigned",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        trailingContent = {
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                conversation.lastMessageAt?.let {
                    Text(
                        DateFormatter.formatRelative(it),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.size(24.dp),
                    ) {
                        Icon(
                            Icons.Default.MoreVert,
                            contentDescription = "More options for ${conversation.convPhone}",
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text("Assign to me") },
                            leadingIcon = { Icon(Icons.Default.PersonAdd, contentDescription = null) },
                            onClick = { showMenu = false; onAssignToMe() },
                        )
                        if (conversation.assignedToId != null) {
                            DropdownMenuItem(
                                text = { Text("Unassign") },
                                leadingIcon = { Icon(Icons.Default.PersonRemove, contentDescription = null) },
                                onClick = { showMenu = false; onUnassign() },
                            )
                        }
                    }
                }
            }
        },
        leadingContent = {
            Icon(
                Icons.Default.Inbox,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp),
            )
        },
    )
}
