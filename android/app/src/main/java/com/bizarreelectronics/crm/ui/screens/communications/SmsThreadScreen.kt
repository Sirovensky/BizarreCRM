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
import androidx.compose.material.icons.automirrored.filled.Subject
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import com.bizarreelectronics.crm.data.local.draft.DraftStore
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
)

@HiltViewModel
class SmsThreadViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val smsApi: SmsApi,
    private val smsRepository: SmsRepository,
    private val serverMonitor: ServerReachabilityMonitor,
    private val draftStore: DraftStore,
    private val gson: Gson,
) : ViewModel() {

    val phone: String = savedStateHandle.get<String>("phone") ?: ""

    private val _state = MutableStateFlow(SmsThreadUiState())
    val state = _state.asStateFlow()

    private val _pendingDraft = MutableStateFlow<DraftStore.Draft?>(null)
    val pendingDraft: StateFlow<DraftStore.Draft?> = _pendingDraft.asStateFlow()

    private var collectJob: Job? = null
    private var autosaveJob: Job? = null

    init {
        collectThread()
        loadOnlineDetails()
        smsRepository.markRead(phone)
        // Load any persisted SMS draft saved for this thread (identified by phone).
        // DraftStore.DraftType.SMS is a single slot per user — entityId disambiguates
        // which thread the draft belongs to.  Only surface the prompt when the
        // entityId matches the current thread's phone so a draft from a different
        // conversation is never accidentally shown here.
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

    fun sendMessage(text: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSending = true)
            try {
                smsRepository.sendMessage(phone, text)
                // Message sent — draft is no longer needed.
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

    /**
     * Call this whenever the compose field text changes.
     * Cancels any pending autosave and restarts the 2-second debounce counter.
     * Uses [phone] as the entityId so the draft is bound to this thread.
     */
    fun onComposeFieldChanged(body: String) {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(DRAFT_AUTOSAVE_DEBOUNCE_MS)
            val json = serializePayload(body)
            draftStore.save(DraftStore.DraftType.SMS, json, entityId = phone)
        }
    }

    /** Serialise the compose body into a minimal JSON payload. */
    private fun serializePayload(body: String): String {
        val obj = JsonObject()
        obj.addProperty("body", body)
        obj.addProperty("threadPhone", phone)
        return gson.toJson(obj)
    }

    /**
     * Restore the compose field from a persisted draft.
     * Returns the body string to set in the UI's messageText state.
     * Clears [_pendingDraft] so the prompt is dismissed.
     */
    fun resumeDraft(draft: DraftStore.Draft): String {
        _pendingDraft.value = null
        return try {
            JsonParser.parseString(draft.payloadJson).asJsonObject
                .get("body")?.takeIf { !it.isJsonNull }?.asString ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    /** Permanently discard the pending draft and clear the recovery prompt. */
    fun discardDraft() {
        _pendingDraft.value = null
        viewModelScope.launch {
            draftStore.discard(DraftStore.DraftType.SMS)
        }
    }

    /**
     * Fetch templates from the server and cache them in state.
     * Idempotent: no-ops if templates are already loaded or currently loading.
     */
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
                // On failure leave templates empty so the sheet shows the empty state.
                _state.value = _state.value.copy(isLoadingTemplates = false)
            }
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
    // AND-20260414-M4: the nav graph passes the current NavBackStackEntry so we
    // can observe the `sms_template_body` key that SmsTemplatesScreen writes
    // when the user picks a template. When null (preview/tests) the feature is
    // simply unavailable and the top-bar icon is hidden.
    templateBodyFlow: kotlinx.coroutines.flow.StateFlow<String?>? = null,
    onTemplateConsumed: (() -> Unit)? = null,
    viewModel: SmsThreadViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val pendingDraft by viewModel.pendingDraft.collectAsState()
    // @audit-fixed: was remember { mutableStateOf("") } — a half-typed message
    // would be wiped on rotation. rememberSaveable persists it across the
    // configuration change.
    var messageText by rememberSaveable { mutableStateOf("") }
    var showTemplateSheet by remember { mutableStateOf(false) }
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

    // AND-20260414-M4: consume a template body that SmsTemplatesScreen wrote
    // into our savedStateHandle. Replace the compose draft with the template
    // (matches how RepairDesk web canned-responses behave) and clear the key
    // so navigating away and back doesn't re-apply the same template.
    val templateBody by (templateBodyFlow?.collectAsState() ?: remember { mutableStateOf(null) })
    LaunchedEffect(templateBody) {
        val body = templateBody
        if (!body.isNullOrBlank()) {
            messageText = body
            onTemplateConsumed?.invoke()
        }
    }

    // Build interpolation context from the current thread. Keys must match
    // server-documented available_variables (customer_name, first_name, …).
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

    // Show DraftRecoveryPrompt when a persisted draft exists for this thread and
    // the compose field is currently empty (avoid overwriting text the user has
    // already started typing).
    if (pendingDraft != null && messageText.isEmpty()) {
        DraftRecoveryPrompt(
            draft = pendingDraft!!,
            previewFormatter = ::buildSmsDraftPreview,
            onResume = {
                val restored = viewModel.resumeDraft(pendingDraft!!)
                messageText = restored
            },
            onDiscard = { viewModel.discardDraft() },
        )
    }

    // Show the inline template picker sheet.
    if (showTemplateSheet) {
        SmsTemplatePickerSheet(
            templates = state.templates,
            context = templateContext,
            onTemplateSelected = { expandedBody ->
                messageText = expandedBody
                showTemplateSheet = false
            },
            onDismiss = { showTemplateSheet = false },
            isLoading = state.isLoadingTemplates,
        )
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
                    // AND-20260414-M4: template picker — opens SmsTemplatesScreen
                    // which writes the selected body back via savedStateHandle.
                    if (onNavigateToTemplates != null) {
                        IconButton(onClick = onNavigateToTemplates) {
                            Icon(
                                Icons.AutoMirrored.Filled.Subject,
                                contentDescription = "Insert template",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
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
                onMessageChange = { newText ->
                    messageText = newText
                    viewModel.onComposeFieldChanged(newText)
                },
                isSending = state.isSending,
                onSend = {
                    viewModel.sendMessage(messageText.trim())
                    messageText = ""
                },
                onTemplateClick = {
                    viewModel.loadTemplates()
                    showTemplateSheet = true
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                // a11y: mergeDescendants collapses each shimmer box into a single
                // focus stop; contentDescription announces loading state to TalkBack.
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .semantics(mergeDescendants = true) {
                            contentDescription = "Loading messages"
                        },
                )
            }
            state.error != null && state.messages.isEmpty() -> {
                // a11y: liveRegion=Assertive interrupts TalkBack immediately on error
                // so the user hears the failure without manual exploration.
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
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
                // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                // into a single TalkBack focus stop with a cohesive description.
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
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
                        .padding(padding)
                        // a11y: liveRegion=Polite so TalkBack announces new incoming message
                        // bodies without interrupting the user's current focus.
                        .semantics { liveRegion = LiveRegionMode.Polite },
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
    onTemplateClick: () -> Unit,
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
                    modifier = Modifier
                        .weight(1f)
                        // a11y: explicit label so TalkBack reads "Message input" instead
                        // of reading the placeholder text as the field label.
                        .semantics { contentDescription = "Message input" },
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

                // Template picker icon — between text field and send button.
                IconButton(onClick = onTemplateClick) {
                    Icon(
                        Icons.Default.ListAlt,
                        contentDescription = "Insert template",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

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

    // a11y: build a cohesive sentence TalkBack reads for the whole bubble.
    // Status is folded into the outbound description so the delivery-status Text
    // node below does not need its own announcement (avoids double-read).
    val timeDisplay = message.createdAt?.take(16)?.replace("T", " ") ?: ""
    val messageBody = message.message ?: ""
    val bubbleContentDescription = if (isOutbound) {
        val statusSuffix = when (message.status) {
            "delivered" -> ", delivered"
            "sent"      -> ", sent"
            "queued"    -> ", queued"
            "failed"    -> ", failed"
            else        -> ""
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
                // a11y: mergeDescendants=true collapses all child Text nodes into this
                // single focus stop; clearAndSetSemantics replaces the auto-merged text
                // with our curated sentence so TalkBack reads a natural description.
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
                    // Timestamp in BrandMono
                    Text(
                        timeDisplay,
                        style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
                        color = timestampColor,
                    )
                    if (isOutbound && message.status != null) {
                        // a11y: status text is already folded into bubbleContentDescription;
                        // visual-only — clearAndSetSemantics on the parent Box hides it
                        // from the accessibility tree, so no double-read occurs.
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

// ---------------------------------------------------------------------------
// Draft preview formatter — used by DraftRecoveryPrompt
// ---------------------------------------------------------------------------

/**
 * Build a short, human-readable preview string from an SMS draft payload JSON.
 * Used by [DraftRecoveryPrompt] so the user can identify the draft at a glance.
 *
 * Shows the first 60 characters of the body and the thread phone number, e.g.:
 *   "Draft for +15551234567: Hi, your repair is ready for pickup an…"
 *   "Draft for +15551234567" (when body is blank)
 */
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
