package com.bizarreelectronics.crm.ui.screens.communications

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.ripple
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
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
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.communications.components.SmsFilter
import com.bizarreelectronics.crm.ui.screens.communications.components.SmsFilterChipRow
import com.bizarreelectronics.crm.ui.screens.communications.components.applySmsFilter
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
    /** L1508 — active filter chip */
    val currentFilter: SmsFilter = SmsFilter.All,
)

@HiltViewModel
class SmsListViewModel @Inject constructor(
    private val smsApi: SmsApi,
    private val smsRepository: SmsRepository,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(SmsListUiState())
    val state = _state.asStateFlow()

    /** Raw unfiltered conversations from server/cache. Filters applied in displayConversations. */
    private var rawConversations: List<SmsConversationItem> = emptyList()

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
                    rawConversations = response.data?.conversations ?: emptyList()
                    _state.value = _state.value.copy(
                        conversations = applySmsFilter(rawConversations, _state.value.currentFilter),
                        isLoading = false,
                        isRefreshing = false,
                    )
                    for (conv in rawConversations) {
                        smsRepository.getThread(conv.convPhone)
                    }
                    return@launch
                } catch (e: Exception) {
                    // Fall through to offline mode
                }
            }

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
                val searched = if (q.isEmpty()) offlineConversations
                else offlineConversations.filter {
                    it.convPhone.contains(q) || it.lastMessage?.lowercase()?.contains(q) == true
                }
                rawConversations = searched
                _state.value = _state.value.copy(
                    conversations = applySmsFilter(rawConversations, _state.value.currentFilter),
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

    /** L1508 — switch filter and re-apply to cached raw list. */
    fun onFilterSelected(filter: SmsFilter) {
        _state.value = _state.value.copy(
            currentFilter = filter,
            conversations = applySmsFilter(rawConversations, filter),
        )
    }

    /** L1509 — optimistic pin; calls API (404 tolerated). */
    fun pinThread(phone: String) {
        rawConversations = rawConversations.map { conv ->
            if (conv.convPhone == phone) conv.copy(isPinned = !conv.isPinned) else conv
        }
        _state.value = _state.value.copy(
            conversations = applySmsFilter(rawConversations, _state.value.currentFilter),
        )
        viewModelScope.launch {
            try {
                smsApi.pinThread(phone)
            } catch (_: Exception) { /* 404-tolerated */ }
        }
    }

    /** L1511 — optimistic archive; calls API (404 tolerated). */
    fun archiveThread(phone: String) {
        rawConversations = rawConversations.map { conv ->
            if (conv.convPhone == phone) conv.copy(isArchived = true) else conv
        }
        _state.value = _state.value.copy(
            conversations = applySmsFilter(rawConversations, _state.value.currentFilter),
        )
        viewModelScope.launch {
            try {
                smsApi.archiveThread(phone)
            } catch (_: Exception) { /* 404-tolerated */ }
        }
    }

    /** L1511 — mark read/unread. */
    fun markRead(phone: String) {
        smsRepository.markRead(phone)
        rawConversations = rawConversations.map { conv ->
            if (conv.convPhone == phone) conv.copy(unreadCount = 0) else conv
        }
        _state.value = _state.value.copy(
            conversations = applySmsFilter(rawConversations, _state.value.currentFilter),
        )
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
    var showNewMsgDialog by rememberSaveable { mutableStateOf(false) }
    var newMsgPhone by rememberSaveable { mutableStateOf("") }

    if (showNewMsgDialog) {
        AlertDialog(
            onDismissRequest = {
                showNewMsgDialog = false
                newMsgPhone = ""
            },
            title = { Text("New conversation") },
            text = {
                OutlinedTextField(
                    value = newMsgPhone,
                    onValueChange = { newMsgPhone = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Phone number") },
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
                    Text("Start chat")
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
            Column {
                BrandTopAppBar(
                    title = "Messages",
                    actions = {
                        IconButton(onClick = { viewModel.loadConversations() }) {
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "Refresh messages",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                )
                WaveDivider()
            }
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showNewMsgDialog = true },
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Icon(Icons.Default.Edit, contentDescription = "Compose new SMS")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search conversations...",
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { contentDescription = "Search conversations" },
            )

            // L1508 — filter chips
            SmsFilterChipRow(
                currentFilter = state.currentFilter,
                onFilterSelected = { viewModel.onFilterSelected(it) },
            )

            when {
                state.isLoading -> {
                    Box(modifier = Modifier.semantics(mergeDescendants = true) {
                        contentDescription = "Loading conversations"
                    }) {
                        BrandSkeleton(rows = 6, modifier = Modifier.fillMaxSize())
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Something went wrong",
                            onRetry = { viewModel.loadConversations() },
                        )
                    }
                }
                state.conversations.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Box(modifier = Modifier.semantics(mergeDescendants = true) {}) {
                            EmptyState(
                                icon = Icons.Default.Forum,
                                title = "No conversations",
                                subtitle = "Tap the + button to start a new conversation",
                                includeWave = false,
                            )
                        }
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(bottom = 80.dp),
                            modifier = Modifier.semantics {
                                liveRegion = LiveRegionMode.Polite
                            },
                        ) {
                            items(state.conversations, key = { it.convPhone }) { conversation ->
                                // L1511 — swipe to archive (left) or mark read (right)
                                ConversationSwipeRow(
                                    conversation = conversation,
                                    onArchive = { viewModel.archiveThread(conversation.convPhone) },
                                    onMarkRead = { viewModel.markRead(conversation.convPhone) },
                                ) {
                                    ConversationRow(
                                        conversation = conversation,
                                        onClick = { onConversationClick(conversation.convPhone) },
                                        onPin = { viewModel.pinThread(conversation.convPhone) },
                                        onArchive = { viewModel.archiveThread(conversation.convPhone) },
                                        onMarkRead = { viewModel.markRead(conversation.convPhone) },
                                    )
                                }
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
}

// ---------------------------------------------------------------------------
// L1511 — SwipeToDismissBox: left=Archive, right=Mark read/unread
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConversationSwipeRow(
    conversation: SmsConversationItem,
    onArchive: () -> Unit,
    onMarkRead: () -> Unit,
    content: @Composable () -> Unit,
) {
    val view = LocalView.current
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    onArchive()
                    false
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    onMarkRead()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
        positionalThreshold = { totalDistance -> totalDistance * 0.35f },
    )

    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue != SwipeToDismissBoxValue.Settled) {
            dismissState.reset()
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            val scheme = MaterialTheme.colorScheme
            when (direction) {
                SwipeToDismissBoxValue.EndToStart -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(scheme.errorContainer)
                            .padding(end = 20.dp),
                        contentAlignment = Alignment.CenterEnd,
                    ) {
                        Icon(
                            Icons.Default.Archive,
                            contentDescription = "Archive",
                            tint = scheme.onErrorContainer,
                        )
                    }
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    val isUnread = conversation.unreadCount > 0
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(scheme.primaryContainer)
                            .padding(start = 20.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Icon(
                            if (isUnread) Icons.Default.MarkEmailRead else Icons.Default.Email,
                            contentDescription = if (isUnread) "Mark read" else "Mark unread",
                            tint = scheme.onPrimaryContainer,
                        )
                    }
                }
                SwipeToDismissBoxValue.Settled -> {
                    Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface))
                }
            }
        },
        content = { content() },
    )
}

// ---------------------------------------------------------------------------
// Conversation row with long-press context menu
// ---------------------------------------------------------------------------

@Composable
private fun ConversationRow(
    conversation: SmsConversationItem,
    onClick: () -> Unit,
    onPin: () -> Unit,
    onArchive: () -> Unit,
    onMarkRead: () -> Unit,
) {
    val customer = conversation.customer
    val displayName = listOfNotNull(customer?.firstName, customer?.lastName)
        .joinToString(" ")
        .ifBlank { null }

    val hasUnread = conversation.unreadCount > 0
    val clipboardManager = LocalClipboardManager.current

    // L1512 — context menu state
    var showContextMenu by remember { mutableStateOf(false) }

    val contactLabel = displayName ?: conversation.convPhone
    val preview = conversation.lastMessage?.takeIf { it.isNotBlank() }
    val timestamp = DateFormatter.formatRelative(conversation.lastMessageAt)
    val a11yDesc = buildString {
        append("Conversation with $contactLabel.")
        if (preview != null) append(" Last message: $preview.")
        if (hasUnread) append(" ${conversation.unreadCount} unread.")
        append(" At $timestamp.")
        if (conversation.isPinned) append(" Pinned.")
        if (conversation.sentiment == "negative") append(" Negative sentiment.")
        append(" Tap to open.")
    }

    val interactionSource = remember { MutableInteractionSource() }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = a11yDesc
                role = Role.Button
            },
    ) {
        if (hasUnread) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .fillMaxHeight()
                    .width(2.dp)
                    .background(MaterialTheme.colorScheme.primary),
            )
        }
        ListItem(
            modifier = Modifier.clickable(
                interactionSource = interactionSource,
                indication = ripple(),
                onClick = onClick,
                onClickLabel = "Open conversation",
            ),
            headlineContent = {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        displayName ?: conversation.convPhone,
                        fontWeight = if (hasUnread) FontWeight.Bold else FontWeight.Normal,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
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
                    // L1510 — negative sentiment badge
                    if (conversation.sentiment == "negative") {
                        SuggestionChip(
                            onClick = {},
                            label = { Text("Negative", style = MaterialTheme.typography.labelSmall) },
                            colors = SuggestionChipDefaults.suggestionChipColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer,
                                labelColor = MaterialTheme.colorScheme.onErrorContainer,
                            ),
                            modifier = Modifier.height(20.dp),
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
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primary)
                                .align(Alignment.End),
                        )
                    }
                    // L1512 — context menu anchor
                    Box {
                        IconButton(
                            onClick = { showContextMenu = true },
                            modifier = Modifier.size(24.dp),
                        ) {
                            Icon(
                                Icons.Default.MoreVert,
                                contentDescription = "More options",
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        DropdownMenu(
                            expanded = showContextMenu,
                            onDismissRequest = { showContextMenu = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Open") },
                                leadingIcon = { Icon(Icons.Default.OpenInNew, null) },
                                onClick = { showContextMenu = false; onClick() },
                            )
                            DropdownMenuItem(
                                text = { Text("Copy phone") },
                                leadingIcon = { Icon(Icons.Default.ContentCopy, null) },
                                onClick = {
                                    showContextMenu = false
                                    clipboardManager.setText(AnnotatedString(conversation.convPhone))
                                },
                            )
                            DropdownMenuItem(
                                text = { Text(if (hasUnread) "Mark read" else "Mark unread") },
                                leadingIcon = { Icon(Icons.Default.MarkEmailRead, null) },
                                onClick = { showContextMenu = false; onMarkRead() },
                            )
                            DropdownMenuItem(
                                text = { Text(if (conversation.isPinned) "Unpin" else "Pin") },
                                leadingIcon = { Icon(Icons.Default.PushPin, null) },
                                onClick = { showContextMenu = false; onPin() },
                            )
                            DropdownMenuItem(
                                text = { Text("Archive") },
                                leadingIcon = { Icon(Icons.Default.Archive, null) },
                                onClick = { showContextMenu = false; onArchive() },
                            )
                        }
                    }
                }
            },
            leadingContent = {
                AvatarInitial(name = displayName ?: conversation.convPhone)
            },
        )
    }
}

/** Purple-container avatar with first initial, 36dp. */
@Composable
private fun AvatarInitial(name: String) {
    val initial = name.firstOrNull()?.uppercaseChar()?.toString() ?: "?"
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initial,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
