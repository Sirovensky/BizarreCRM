package com.bizarreelectronics.crm.ui.screens.team

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.TeamChatMessage
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.team.components.AvatarInitial
import com.bizarreelectronics.crm.ui.screens.team.components.ReactionPickerSheet
import com.bizarreelectronics.crm.ui.screens.team.components.TeamMessageBubble
import com.bizarreelectronics.crm.util.MentionPickerDropdown
import com.bizarreelectronics.crm.util.MentionUtil

/**
 * §47 — Team Chat thread screen.
 * Shows messages for a single room with compose + @mentions + reactions.
 * 404-tolerant: shows "Team chat not configured" empty state on 404.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamChatThreadScreen(
    onBack: () -> Unit,
    viewModel: TeamChatThreadViewModel = hiltViewModel(),
    currentUserId: Long = 0L,
    /** §47.3: navigate to ticket detail screen when @ticket embed is tapped. */
    onTicketClick: ((ticketId: Long) -> Unit)? = null,
    /** §47.3: navigate to customer search when @customer embed is tapped. */
    onCustomerClick: ((name: String) -> Unit)? = null,
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val listState = rememberLazyListState()

    var composeText by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        mutableStateOf(TextFieldValue(""))
    }
    var showReactionPickerFor by remember { mutableStateOf<String?>(null) }
    var showAttachmentStub by remember { mutableStateOf(false) }

    // Show reaction picker sheet
    if (showReactionPickerFor != null) {
        val msgId = showReactionPickerFor!!
        ReactionPickerSheet(
            onSelect = { emoji ->
                viewModel.toggleReaction(msgId, emoji)
                showReactionPickerFor = null
            },
            onDismiss = { showReactionPickerFor = null },
        )
    }

    // Attachment stub sheet
    if (showAttachmentStub) {
        ModalBottomSheet(onDismissRequest = { showAttachmentStub = false }) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(32.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "File attachments coming soon",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(32.dp))
        }
    }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    // Auto-scroll to top (newest) when new messages arrive in reverse layout
    LaunchedEffect(state.messages.size) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(0)
        }
    }

    Scaffold(
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = state.roomName.ifBlank { "Team Chat" },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = "Refresh",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
        bottomBar = {
            TeamComposeBar(
                messageText = composeText,
                onMessageChange = { newValue ->
                    composeText = newValue
                    viewModel.onComposeTextChanged(newValue.text, state.employees)
                },
                isSending = state.isSending,
                mentionSuggestions = state.mentionSuggestions,
                onMentionSelect = { employee ->
                    val updated = MentionUtil.insertMention(composeText, employee)
                    composeText = updated
                    viewModel.onComposeTextChanged(updated.text, state.employees)
                },
                onSend = {
                    viewModel.sendMessage(composeText.text.trim())
                    composeText = TextFieldValue("")
                },
                onAttachClick = { showAttachmentStub = true },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.isLoading -> {
                    BrandSkeleton(
                        rows = 6,
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {
                                contentDescription = "Loading messages"
                            },
                    )
                }
                state.notConfigured -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        EmptyState(
                            icon = Icons.Default.Forum,
                            title = "Team chat not configured",
                            subtitle = "Ask your admin to enable team chat.",
                            includeWave = false,
                        )
                    }
                }
                state.error != null && state.messages.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Something went wrong",
                            onRetry = { viewModel.refresh() },
                        )
                    }
                }
                state.messages.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {
                                contentDescription = "No messages yet. Send the first message below."
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Forum,
                            title = "No messages yet",
                            subtitle = "Send the first message below",
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Polite },
                        state = listState,
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        reverseLayout = true,
                    ) {
                        items(state.messages, key = { it.id }) { message ->
                            val isMe = message.authorId == currentUserId
                            TeamMessageBubble(
                                message = message,
                                isMe = isMe,
                                onReactionToggle = { emoji ->
                                    viewModel.toggleReaction(message.id, emoji)
                                },
                                onLongPress = { showReactionPickerFor = message.id },
                                // §47.3: forward embed taps to the caller's nav handlers.
                                onTicketClick = onTicketClick,
                                onCustomerClick = onCustomerClick,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─── Compose bar ─────────────────────────────────────────────────────────────

@Composable
private fun TeamComposeBar(
    messageText: TextFieldValue,
    onMessageChange: (TextFieldValue) -> Unit,
    isSending: Boolean,
    mentionSuggestions: List<EmployeeListItem>,
    onMentionSelect: (EmployeeListItem) -> Unit,
    onSend: () -> Unit,
    onAttachClick: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                thickness = 1.dp,
            )
            Box {
                // @mention dropdown anchored above the compose field
                MentionPickerDropdown(
                    expanded = mentionSuggestions.isNotEmpty(),
                    suggestions = mentionSuggestions,
                    onSelect = onMentionSelect,
                    onDismiss = { /* onMessageChange clears suggestions when @ gone */ },
                    modifier = Modifier.align(Alignment.TopStart),
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(8.dp),
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    // Attachment stub
                    IconButton(onClick = onAttachClick) {
                        Icon(
                            Icons.Default.AttachFile,
                            contentDescription = "Attach file (coming soon)",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    OutlinedTextField(
                        value = messageText,
                        onValueChange = onMessageChange,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Message input" },
                        placeholder = { Text("Message\u2026 (@mention to notify)") },
                        maxLines = 4,
                    )

                    IconButton(
                        onClick = {
                            if (messageText.text.isNotBlank()) onSend()
                        },
                        enabled = messageText.text.isNotBlank() && !isSending,
                    ) {
                        if (isSending) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = "Send message",
                                tint = if (messageText.text.isNotBlank())
                                    MaterialTheme.colorScheme.primary
                                else
                                    MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}
