package com.bizarreelectronics.crm.ui.screens.communications

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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
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
    // @audit-fixed: dialog state and the typed phone were both wiped on
    // rotation. Persisting them via rememberSaveable preserves the open
    // dialog and the phone number the user was entering.
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
            // CROSS45: WaveDivider docked directly below the TopAppBar — canonical
            // placement for every list screen (Messages previously had none).
            Column {
                BrandTopAppBar(
                    title = "Messages",
                    actions = {
                        // CROSS42: New-message action moved to FAB for parity with
                        // every other list screen (Customers/Tickets/Inventory/etc.).
                        // Only the refresh action stays in the top bar.
                        IconButton(onClick = { viewModel.loadConversations() }) {
                            Icon(
                                Icons.Default.Refresh,
                                // a11y: specific phrase so TalkBack announces "Refresh messages"
                                // rather than generic "Refresh" — matches §26 spec.
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
                // a11y: imperative phrase per §26 spec so TalkBack announces
                // "Compose new SMS" when the FAB receives focus.
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
                    // a11y: explicit label so TalkBack announces "Search conversations"
                    // when the field gains focus rather than reading the placeholder text.
                    .semantics { contentDescription = "Search conversations" },
            )

            when {
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription collapses shimmer boxes
                    // into a single "Loading conversations" TalkBack focus node.
                    Box(modifier = Modifier.semantics(mergeDescendants = true) {
                        contentDescription = "Loading conversations"
                    }) {
                        BrandSkeleton(rows = 6, modifier = Modifier.fillMaxSize())
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive interrupts TalkBack immediately so the
                    // user is not left wondering why the list is empty after a network failure.
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
                        // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                        // into one TalkBack node so the empty state reads as a single announcement.
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
                            // CROSS16-ext: bottom inset so the last row can
                            // scroll above the bottom-nav / gesture area.
                            contentPadding = PaddingValues(bottom = 80.dp),
                            // a11y: liveRegion=Polite so TalkBack announces new incoming
                            // messages without stealing focus from whatever the user is reading.
                            modifier = Modifier.semantics {
                                liveRegion = LiveRegionMode.Polite
                            },
                        ) {
                            items(state.conversations, key = { it.convPhone }) { conversation ->
                                ConversationRow(
                                    conversation = conversation,
                                    onClick = { onConversationClick(conversation.convPhone) },
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
}

@Composable
private fun ConversationRow(conversation: SmsConversationItem, onClick: () -> Unit) {
    val customer = conversation.customer
    val displayName = listOfNotNull(customer?.firstName, customer?.lastName)
        .joinToString(" ")
        .ifBlank { null }

    val hasUnread = conversation.unreadCount > 0

    // a11y: build the full announcement string once so semantics can reference it.
    // Unread count is folded in here so the badge dot is NOT a separate speakable node.
    // Format: "Conversation with NAME. Last message: PREVIEW. N unread. At TIMESTAMP. Tap to open."
    val contactLabel = displayName ?: conversation.convPhone
    val preview = conversation.lastMessage?.takeIf { it.isNotBlank() }
    val timestamp = DateFormatter.formatRelative(conversation.lastMessageAt)
    val a11yDesc = buildString {
        append("Conversation with $contactLabel.")
        if (preview != null) append(" Last message: $preview.")
        if (hasUnread) append(" ${conversation.unreadCount} unread.")
        append(" At $timestamp.")
        append(" Tap to open.")
    }

    // D5-3: explicit interactionSource + ripple() indication so the row
    // flashes on tap. A bare ListItem modifier = .clickable sometimes
    // suppressed the ripple because ListItem renders its own Surface
    // background over the indication layer.
    val interactionSource = remember { MutableInteractionSource() }

    // 2dp purple left accent bar for unread rows — applied via Box overlay
    // a11y: mergeDescendants=true collapses all child nodes (avatar, name, preview,
    // timestamp, badge dot) into a single TalkBack focus stop; Role.Button signals
    // the interactive affordance.
    Box(modifier = Modifier
        .fillMaxWidth()
        .semantics(mergeDescendants = true) {
            contentDescription = a11yDesc
            role = Role.Button
        }
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
                        // Small purple dot — replaces badge-style chip
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primary)
                                .align(Alignment.End),
                        )
                    }
                }
            },
            leadingContent = {
                // Avatar placeholder: purple-container bg with initial letter
                AvatarInitial(
                    name = displayName ?: conversation.convPhone,
                )
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
