package com.bizarreelectronics.crm.ui.screens.communications

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.Subject
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import com.bizarreelectronics.crm.data.local.draft.DraftStore
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.SmsMessageItem
import com.bizarreelectronics.crm.data.remote.dto.SmsTemplateDto
import com.bizarreelectronics.crm.data.repository.SmsRepository
import com.bizarreelectronics.crm.ui.components.DraftRecoveryPrompt
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.communications.components.ScheduleSendSheet
import com.bizarreelectronics.crm.ui.screens.communications.components.SmsCharCounter
import com.bizarreelectronics.crm.ui.screens.communications.components.SmsDeliveryStatusDot
import com.bizarreelectronics.crm.ui.screens.communications.components.scheduleSendLocally
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

private const val DRAFT_AUTOSAVE_DEBOUNCE_MS = 2_000L
private const val COMPLIANCE_FOOTER = "\n\nReply STOP to opt out."

// L1524 — 50 common emoji for the emoji picker
private val COMMON_EMOJI = listOf(
    "😀", "😊", "😂", "🥲", "😍", "🤩", "😎", "😢", "😅", "🙏",
    "👍", "👎", "👋", "✌️", "🤝", "💪", "🔥", "⭐", "✅", "❌",
    "📱", "💬", "📞", "📧", "🔔", "⚡", "💡", "🛠️", "🧰", "🔧",
    "🏠", "🚗", "📦", "💰", "💳", "🎉", "🎁", "🙌", "❤️", "💙",
    "💯", "⏰", "📅", "🗓️", "🔑", "🛡️", "🌟", "🎯", "🚀", "✨",
)

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
    /** Templates for the inline picker sheet. Fetched once per screen lifetime. */
    val templates: List<SmsTemplateDto> = emptyList(),
    val isLoadingTemplates: Boolean = false,
    /** L1521 — true when WS emits typing event for this thread */
    val isRemoteTyping: Boolean = false,
    /** L1533 — true when server is in off-hours auto-reply mode */
    val isOffHours: Boolean = false,
)

@HiltViewModel
class SmsThreadViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val smsApi: SmsApi,
    private val smsRepository: SmsRepository,
    private val serverMonitor: ServerReachabilityMonitor,
    private val draftStore: DraftStore,
    private val gson: Gson,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    val phone: String = savedStateHandle.get<String>("phone") ?: ""

    private val _state = MutableStateFlow(SmsThreadUiState())
    val state = _state.asStateFlow()

    private val _pendingDraft = MutableStateFlow<DraftStore.Draft?>(null)
    val pendingDraft: StateFlow<DraftStore.Draft?> = _pendingDraft.asStateFlow()

    private var collectJob: Job? = null
    private var autosaveJob: Job? = null
    private var typingJob: Job? = null

    init {
        collectThread()
        loadOnlineDetails()
        smsRepository.markRead(phone)
        viewModelScope.launch {
            val draft = draftStore.load(DraftStore.DraftType.SMS)
            if (draft != null && draft.entityId == phone) {
                _pendingDraft.value = draft
            }
        }
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

    /**
     * L1528 — compliance footer. Appends "Reply STOP to opt out." to [text] if
     * this is the first outbound send to [phone]. Marks the number as opted-in.
     */
    private fun applyComplianceFooter(text: String): String {
        return if (!appPreferences.hasSmsOptInBeenSent(phone)) {
            appPreferences.markSmsOptInSent(phone)
            text + COMPLIANCE_FOOTER
        } else {
            text
        }
    }

    fun sendMessage(text: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSending = true)
            try {
                val body = applyComplianceFooter(text)
                smsRepository.sendMessage(phone, body)
                discardDraft()
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

    // ── Draft autosave ───────────────────────────────────────────────

    fun onComposeFieldChanged(body: String) {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(DRAFT_AUTOSAVE_DEBOUNCE_MS)
            val json = serializePayload(body)
            draftStore.save(DraftStore.DraftType.SMS, json, entityId = phone)
        }
    }

    private fun serializePayload(body: String): String {
        val obj = JsonObject()
        obj.addProperty("body", body)
        obj.addProperty("threadPhone", phone)
        return gson.toJson(obj)
    }

    fun resumeDraft(draft: DraftStore.Draft): String {
        _pendingDraft.value = null
        return try {
            JsonParser.parseString(draft.payloadJson).asJsonObject
                .get("body")?.takeIf { !it.isJsonNull }?.asString ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    fun discardDraft() {
        _pendingDraft.value = null
        viewModelScope.launch {
            draftStore.discard(DraftStore.DraftType.SMS)
        }
    }

    fun loadTemplates() {
        if (_state.value.templates.isNotEmpty() || _state.value.isLoadingTemplates) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingTemplates = true)
            try {
                val response = smsApi.getTemplates()
                val list = response.data?.templates ?: emptyList()
                _state.value = _state.value.copy(
                    templates = list,
                    isLoadingTemplates = false,
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(isLoadingTemplates = false)
            }
        }
    }

    // ── L1521 — typing indicator ─────────────────────────────────────

    /**
     * Called when a WebSocket "typing" event arrives for this thread.
     * Shows the indicator for 3 seconds then auto-hides.
     */
    fun onRemoteTyping() {
        _state.value = _state.value.copy(isRemoteTyping = true)
        typingJob?.cancel()
        typingJob = viewModelScope.launch {
            delay(3_000L)
            _state.value = _state.value.copy(isRemoteTyping = false)
        }
    }

    // ── L1525 — schedule send ────────────────────────────────────────

    /**
     * Schedule send via server. 404 fallback is handled in the UI layer
     * which has access to [Context] for WorkManager.
     */
    suspend fun scheduleSend(text: String, sendAtIso: String): Boolean {
        return try {
            smsApi.sendSmsScheduled(
                sendAt = sendAtIso,
                request = mapOf("to" to phone, "message" to text),
            )
            true
        } catch (_: Exception) {
            false
        }
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
    onNavigateToTemplates: (() -> Unit)? = null,
    templateBodyFlow: kotlinx.coroutines.flow.StateFlow<String?>? = null,
    onTemplateConsumed: (() -> Unit)? = null,
    viewModel: SmsThreadViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val pendingDraft by viewModel.pendingDraft.collectAsState()
    // Using TextFieldValue to track cursor position for emoji insertion (L1524)
    var messageText by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        mutableStateOf(TextFieldValue(""))
    }
    var showTemplateSheet by remember { mutableStateOf(false) }
    var showEmojiSheet by remember { mutableStateOf(false) }
    var showScheduleSheet by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    val customerName = state.customer?.let {
        "${it.firstName ?: ""} ${it.lastName ?: ""}".trim()
    }?.ifBlank { null }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    val templateBody by (templateBodyFlow?.collectAsState() ?: remember { mutableStateOf(null) })
    LaunchedEffect(templateBody) {
        val body = templateBody
        if (!body.isNullOrBlank()) {
            messageText = TextFieldValue(body, TextRange(body.length))
            onTemplateConsumed?.invoke()
        }
    }

    val templateContext = remember(state.customer, phone) {
        buildMap {
            val customer = state.customer
            if (customer != null) {
                val firstName = customer.firstName?.trim() ?: ""
                val lastName = customer.lastName?.trim() ?: ""
                put("first_name", firstName)
                put("last_name", lastName)
                put("customer_name", listOf(firstName, lastName).filter { it.isNotEmpty() }.joinToString(" "))
            }
            put("customer_phone", phone)
        }
    }

    if (pendingDraft != null && messageText.text.isEmpty()) {
        DraftRecoveryPrompt(
            draft = pendingDraft!!,
            previewFormatter = ::buildSmsDraftPreview,
            onResume = {
                val restored = viewModel.resumeDraft(pendingDraft!!)
                messageText = TextFieldValue(restored, TextRange(restored.length))
            },
            onDiscard = { viewModel.discardDraft() },
        )
    }

    if (showTemplateSheet) {
        SmsTemplatePickerSheet(
            templates = state.templates,
            context = templateContext,
            onTemplateSelected = { expandedBody ->
                messageText = TextFieldValue(expandedBody, TextRange(expandedBody.length))
                showTemplateSheet = false
            },
            onDismiss = { showTemplateSheet = false },
            isLoading = state.isLoadingTemplates,
        )
    }

    // L1524 — emoji picker sheet
    if (showEmojiSheet) {
        EmojiPickerSheet(
            onEmojiSelected = { emoji ->
                val cur = messageText
                val before = cur.text.substring(0, cur.selection.end)
                val after = cur.text.substring(cur.selection.end)
                val newText = before + emoji + after
                val newCursor = before.length + emoji.length
                messageText = TextFieldValue(newText, TextRange(newCursor))
                showEmojiSheet = false
            },
            onDismiss = { showEmojiSheet = false },
        )
    }

    // L1525 — schedule send sheet
    if (showScheduleSheet) {
        ScheduleSendSheet(
            onDismiss = { showScheduleSheet = false },
            onSchedule = { sendAtIso ->
                showScheduleSheet = false
                val textToSend = messageText.text.trim()
                if (textToSend.isNotBlank()) {
                    coroutineScope.launch {
                        val success = viewModel.scheduleSend(textToSend, sendAtIso)
                        if (!success) {
                            // 404 fallback: WorkManager
                            val triggerMs = try {
                                java.time.OffsetDateTime.parse(sendAtIso).toInstant().toEpochMilli()
                            } catch (_: Exception) {
                                System.currentTimeMillis() + 60_000L
                            }
                            scheduleSendLocally(context, phone, textToSend, triggerMs)
                        }
                        messageText = TextFieldValue("")
                        snackbarHostState.showSnackbar("Message scheduled")
                    }
                }
            },
        )
    }

    Scaffold(
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
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
                    if (onNavigateToTemplates != null) {
                        IconButton(onClick = onNavigateToTemplates) {
                            Icon(
                                Icons.AutoMirrored.Filled.Subject,
                                contentDescription = "Insert template",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    IconButton(onClick = { viewModel.toggleFlag() }) {
                        Icon(
                            Icons.Default.Flag,
                            contentDescription = if (state.isFlagged) "Unflag conversation" else "Flag conversation",
                            tint = if (state.isFlagged) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
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
            Column {
                // L1527 — char counter above compose bar
                if (messageText.text.isNotEmpty()) {
                    SmsCharCounter(text = messageText.text)
                }
                ComposeBar(
                    messageText = messageText,
                    onMessageChange = { newValue ->
                        messageText = newValue
                        viewModel.onComposeFieldChanged(newValue.text)
                    },
                    isSending = state.isSending,
                    onSend = {
                        viewModel.sendMessage(messageText.text.trim())
                        messageText = TextFieldValue("")
                    },
                    onTemplateClick = {
                        viewModel.loadTemplates()
                        showTemplateSheet = true
                    },
                    onEmojiClick = { showEmojiSheet = true },
                    onScheduleClick = { showScheduleSheet = true },
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // L1533 — off-hours banner
            if (state.isOffHours) {
                Surface(
                    color = MaterialTheme.colorScheme.tertiaryContainer,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.NightlightRound,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onTertiaryContainer,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            "Off-hours — auto-reply active until 8 AM.",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onTertiaryContainer,
                        )
                    }
                }
            }

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
                state.error != null && state.messages.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
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
                            .semantics(mergeDescendants = true) {
                                contentDescription = "No messages yet. Send the first message below."
                            },
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
                            .semantics { liveRegion = LiveRegionMode.Polite },
                        state = listState,
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        reverseLayout = true,
                    ) {
                        // L1521 — typing indicator bubble
                        if (state.isRemoteTyping) {
                            item(key = "typing_indicator") {
                                TypingIndicatorBubble()
                            }
                        }
                        items(state.messages.reversed(), key = { it.id }) { message ->
                            MessageBubble(message = message)
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// L1521 — Typing indicator bubble
// ---------------------------------------------------------------------------

@Composable
private fun TypingIndicatorBubble() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp, bottomEnd = 14.dp, bottomStart = 2.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .semantics { contentDescription = "Customer is typing" },
        ) {
            Text(
                "Typing\u2026",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// L1524 — Emoji picker bottom sheet
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EmojiPickerSheet(
    onEmojiSelected: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
        ) {
            Text("Emoji", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            val rows = COMMON_EMOJI.chunked(10)
            rows.forEach { rowEmoji ->
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    items(rowEmoji) { emoji ->
                        TextButton(onClick = { onEmojiSelected(emoji) }) {
                            Text(emoji, style = MaterialTheme.typography.titleLarge)
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Bottom compose bar
// ---------------------------------------------------------------------------

@Composable
private fun ComposeBar(
    messageText: TextFieldValue,
    onMessageChange: (TextFieldValue) -> Unit,
    isSending: Boolean,
    onSend: () -> Unit,
    onTemplateClick: () -> Unit,
    onEmojiClick: () -> Unit,
    onScheduleClick: () -> Unit,
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
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                OutlinedTextField(
                    value = messageText,
                    onValueChange = onMessageChange,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Message input" },
                    placeholder = { Text("Type a message...") },
                    maxLines = 4,
                )

                // L1524 — emoji picker
                IconButton(onClick = onEmojiClick) {
                    Icon(
                        Icons.Default.EmojiEmotions,
                        contentDescription = "Insert emoji",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // Template picker
                IconButton(onClick = onTemplateClick) {
                    Icon(
                        Icons.Default.ListAlt,
                        contentDescription = "Insert template",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // L1525 — schedule send
                IconButton(onClick = onScheduleClick) {
                    Icon(
                        Icons.Default.Schedule,
                        contentDescription = "Schedule send",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                IconButton(
                    onClick = {
                        if (messageText.text.isNotBlank()) onSend()
                    },
                    enabled = messageText.text.isNotBlank() && !isSending,
                ) {
                    if (isSending) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(
                            Icons.AutoMirrored.Filled.Send,
                            contentDescription = "Send message",
                            tint = if (messageText.text.isNotBlank()) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Message bubble with L1519 delivery status + L1520 read receipt
// ---------------------------------------------------------------------------

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

    val timeDisplay = message.createdAt?.take(16)?.replace("T", " ") ?: ""
    val messageBody = message.message ?: ""
    val bubbleContentDescription = if (isOutbound) {
        val statusSuffix = when (message.status) {
            "delivered" -> ", delivered"
            "sent" -> ", sent"
            "queued" -> ", queued"
            "failed" -> ", failed"
            else -> ""
        }
        "Sent at $timeDisplay$statusSuffix: $messageBody"
    } else {
        "Received at $timeDisplay: $messageBody"
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isOutbound) Arrangement.End else Arrangement.Start,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = 280.dp)
                .clip(bubbleShape)
                .background(bubbleBg)
                .padding(12.dp)
                .clearAndSetSemantics { contentDescription = bubbleContentDescription },
        ) {
            Column {
                Text(
                    messageBody,
                    color = textColor,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Timestamp
                    Text(
                        timeDisplay,
                        style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
                        color = timestampColor,
                    )
                    // L1519 — delivery status dot (outbound only)
                    if (isOutbound) {
                        SmsDeliveryStatusDot(
                            status = message.status,
                            readAt = null, // readAt not in SmsMessageItem yet — stub null
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Draft preview formatter — used by DraftRecoveryPrompt
// ---------------------------------------------------------------------------

private fun buildSmsDraftPreview(payloadJson: String): String {
    return try {
        val obj = JsonParser.parseString(payloadJson).asJsonObject
        val threadPhone = obj.get("threadPhone")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val body = obj.get("body")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val prefix = if (threadPhone.isNotBlank()) "Draft for $threadPhone" else "SMS draft"
        if (body.isBlank()) {
            prefix
        } else {
            val snippet = if (body.length > 60) body.take(60) + "\u2026" else body
            "$prefix: $snippet"
        }
    } catch (_: Exception) {
        "SMS draft"
    }
}
