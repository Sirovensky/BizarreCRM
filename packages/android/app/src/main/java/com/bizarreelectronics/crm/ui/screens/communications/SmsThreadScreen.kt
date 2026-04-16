package com.bizarreelectronics.crm.ui.screens.communications

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.SmsMessageItem
import com.bizarreelectronics.crm.data.repository.SmsRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SmsThreadUiState(
    val messages: List<SmsMessageItem> = emptyList(),
    val customer: CustomerListItem? = null,
    val recentTickets: List<Map<String, Any>>? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val isSending: Boolean = false,
    val isFlagged: Boolean = false,
    val isPinned: Boolean = false,
    val actionMessage: String? = null,
)

@HiltViewModel
class SmsThreadViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val smsApi: SmsApi,
    private val smsRepository: SmsRepository,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    val phone: String = savedStateHandle.get<String>("phone") ?: ""

    private val _state = MutableStateFlow(SmsThreadUiState())
    val state = _state.asStateFlow()

    private var collectJob: Job? = null

    init {
        collectThread()
        loadOnlineDetails()
        smsRepository.markRead(phone)
    }

    /** Collect messages from Room (offline-capable) */
    private fun collectThread() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            smsRepository.getThread(phone).collect { entities ->
                _state.value = _state.value.copy(
                    messages = entities.map { it.toSmsMessageItem() },
                    isLoading = false,
                )
            }
        }
    }

    /** Load customer info and recent tickets from API (online-only enrichment) */
    private fun loadOnlineDetails() {
        viewModelScope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = smsApi.getThread(phone)
                val data = response.data ?: return@launch
                _state.value = _state.value.copy(
                    customer = data.customer,
                    recentTickets = data.recentTickets,
                )
            } catch (_: Exception) {}
        }
    }

    fun loadThread() {
        collectThread()
        loadOnlineDetails()
    }

    fun sendMessage(text: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSending = true)
            try {
                smsRepository.sendMessage(phone, text)
                _state.value = _state.value.copy(
                    isSending = false,
                    actionMessage = if (serverMonitor.isEffectivelyOnline.value) "Message sent" else "Message queued for sending",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSending = false,
                    actionMessage = "Failed to send: ${e.message}",
                )
            }
        }
    }

    fun toggleFlag() {
        smsRepository.toggleFlag(phone)
        _state.value = _state.value.copy(isFlagged = !_state.value.isFlagged)
    }

    fun togglePin() {
        smsRepository.togglePin(phone)
        _state.value = _state.value.copy(isPinned = !_state.value.isPinned)
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

private fun SmsMessageEntity.toSmsMessageItem() = SmsMessageItem(
    id = id,
    fromNumber = fromNumber,
    toNumber = toNumber,
    convPhone = convPhone,
    message = message,
    status = status,
    direction = direction,
    messageType = messageType,
    createdAt = createdAt,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsThreadScreen(
    phone: String,
    onBack: () -> Unit,
    viewModel: SmsThreadViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    // @audit-fixed: was remember { mutableStateOf("") } — a half-typed message
    // would be wiped on rotation. rememberSaveable persists it across the
    // configuration change.
    var messageText by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()
    val snackbarHostState = remember { SnackbarHostState() }

    val customerName = state.customer?.let {
        "${it.firstName ?: ""} ${it.lastName ?: ""}".trim()
    }?.ifBlank { null }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    Scaffold(
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            // Flag active = error (hue-shifted red), pin active = primary (purple).
            // activeActionIndex = null since callers control tinting inline.
            BrandTopAppBar(
                title = customerName ?: phone,
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
                    // Flag: error tint when flagged, muted when not
                    IconButton(onClick = { viewModel.toggleFlag() }) {
                        Icon(
                            Icons.Default.Flag,
                            contentDescription = if (state.isFlagged) "Unflag conversation" else "Flag conversation",
                            tint = if (state.isFlagged) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    // Pin: primary purple when pinned, muted when not
                    IconButton(onClick = { viewModel.togglePin() }) {
                        Icon(
                            Icons.Default.PushPin,
                            contentDescription = if (state.isPinned) "Unpin conversation" else "Pin conversation",
                            tint = if (state.isPinned) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(onClick = { viewModel.loadThread() }) {
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
            ComposeBar(
                messageText = messageText,
                onMessageChange = { messageText = it },
                isSending = state.isSending,
                onSend = {
                    viewModel.sendMessage(messageText.trim())
                    messageText = ""
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                )
            }
            state.error != null && state.messages.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Something went wrong",
                        onRetry = { viewModel.loadThread() },
                    )
                }
            }
            state.messages.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Chat,
                        title = "No messages yet",
                        subtitle = "Send the first message below",
                    )
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    state = listState,
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    reverseLayout = true,
                ) {
                    items(state.messages.reversed(), key = { it.id }) { message ->
                        MessageBubble(message = message)
                    }
                }
            }
        }
    }
}

/**
 * Bottom compose bar.
 * - `surfaceContainer` bg + 1px top outline divider (no tonalElevation which
 *   reads flat on OLED dark surfaces).
 * - Character counter in BrandMono labelSmall.
 * - Send button: purple when enabled, muted when disabled.
 */
@Composable
private fun ComposeBar(
    messageText: String,
    onMessageChange: (String) -> Unit,
    isSending: Boolean,
    onSend: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            // 1px top outline divider instead of tonalElevation
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                thickness = 1.dp,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = messageText,
                    onValueChange = onMessageChange,
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Type a message...") },
                    maxLines = 4,
                    trailingIcon = {
                        // Character counter in BrandMono
                        Text(
                            "${messageText.length}/160",
                            style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
                            color = if (messageText.length > 160) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                )

                IconButton(
                    onClick = {
                        if (messageText.isNotBlank()) {
                            onSend()
                        }
                    },
                    enabled = messageText.isNotBlank() && !isSending,
                ) {
                    if (isSending) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(
                            Icons.AutoMirrored.Filled.Send,
                            contentDescription = "Send message",
                            tint = if (messageText.isNotBlank()) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/**
 * Single chat bubble.
 * - Outbound: [primaryContainer] bg + [onPrimaryContainer] text.
 * - Inbound:  [surfaceContainerHigh] bg + [onSurface] text.
 * - 14dp radius on all corners; tail corner (bottom-end for outbound,
 *   bottom-start for inbound) squared to 2dp.
 * - Timestamps rendered in [BrandMono] labelSmall.
 */
@Composable
private fun MessageBubble(message: SmsMessageItem) {
    val isOutbound = message.direction == "outbound"

    val bubbleShape = RoundedCornerShape(
        topStart = 14.dp,
        topEnd = 14.dp,
        bottomStart = if (isOutbound) 14.dp else 2.dp,
        bottomEnd = if (isOutbound) 2.dp else 14.dp,
    )

    val bubbleBg = if (isOutbound) MaterialTheme.colorScheme.primaryContainer
    else MaterialTheme.colorScheme.surfaceContainerHigh

    val textColor = if (isOutbound) MaterialTheme.colorScheme.onPrimaryContainer
    else MaterialTheme.colorScheme.onSurface

    val timestampColor = if (isOutbound)
        MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
    else
        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isOutbound) Arrangement.End else Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = 280.dp)
                .clip(bubbleShape)
                .background(bubbleBg)
                .padding(12.dp),
        ) {
            Column {
                Text(
                    message.message ?: "",
                    color = textColor,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Timestamp in BrandMono
                    Text(
                        message.createdAt?.take(16)?.replace("T", " ") ?: "",
                        style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
                        color = timestampColor,
                    )
                    if (isOutbound && message.status != null) {
                        Text(
                            when (message.status) {
                                "delivered" -> "Delivered"
                                "sent" -> "Sent"
                                "queued" -> "Queued"
                                "failed" -> "Failed"
                                else -> ""
                            },
                            style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
                            color = if (message.status == "failed") MaterialTheme.colorScheme.error
                            else timestampColor,
                        )
                    }
                }
            }
        }
    }
}
