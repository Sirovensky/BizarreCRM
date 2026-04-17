package com.bizarreelectronics.crm.ui.screens.tickets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketHistory
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.data.remote.dto.TicketPhoto
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.util.formatAsMoney
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Strip HTML tags from server-generated descriptions */
private fun stripHtml(html: String?): String {
    if (html.isNullOrBlank()) return ""
    return html.replace(Regex("<[^>]*>"), "").trim()
}

data class TicketDetailUiState(
    val ticket: TicketEntity? = null,
    val statuses: List<TicketStatusItem> = emptyList(),
    val devices: List<TicketDevice> = emptyList(),
    val notes: List<TicketNote> = emptyList(),
    val history: List<TicketHistory> = emptyList(),
    val photos: List<TicketPhoto> = emptyList(),
    /** Full TicketDetail from API — used for fields not on TicketEntity (customer object, isPinned, isStarred, assignedUser). */
    val ticketDetail: TicketDetail? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    /** Set after a successful ticket-to-invoice conversion so the screen can navigate to the new invoice. */
    val convertedInvoiceId: Long? = null,
)

@HiltViewModel
class TicketDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val ticketRepository: TicketRepository,
    private val ticketApi: TicketApi,
    private val settingsApi: SettingsApi,
    private val authPreferences: com.bizarreelectronics.crm.data.local.prefs.AuthPreferences,
    private val syncQueueDao: com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao,
    private val serverMonitor: com.bizarreelectronics.crm.util.ServerReachabilityMonitor,
    private val gson: com.google.gson.Gson,
) : ViewModel() {

    private val ticketId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L
    val serverUrl: String get() = authPreferences.serverUrl ?: ""

    /**
     * AND-20260414-L1: expose reachability so the Print button can disable
     * itself when the server URL is blank or the device is offline. Printing
     * launches a browser intent against `$serverUrl/print/ticket/:id`, which
     * requires the CRM server to be reachable — there is no on-device receipt
     * renderer yet (see AND-20260414-L1 follow-up below).
     */
    val isEffectivelyOnline get() = serverMonitor.isEffectivelyOnline

    private val _state = MutableStateFlow(TicketDetailUiState())
    val state = _state.asStateFlow()

    init {
        collectTicket()
        loadTicketDetail()
        loadStatuses()
    }

    /** Collect the Room Flow for the ticket entity — instant offline display. */
    private fun collectTicket() {
        viewModelScope.launch {
            ticketRepository.getTicket(ticketId).collect { entity ->
                if (entity != null) {
                    _state.value = _state.value.copy(
                        ticket = entity,
                        isLoading = false,
                    )
                }
            }
        }
    }

    /** Fetch full TicketDetail from API for rich nested data (devices, notes, history, photos). */
    fun loadTicketDetail() {
        viewModelScope.launch {
            // Only show loading spinner if we have no cached entity yet
            if (_state.value.ticket == null) {
                _state.value = _state.value.copy(isLoading = true, error = null)
            }
            try {
                val response = ticketApi.getTicket(ticketId)
                val detail = response.data
                if (detail != null) {
                    _state.value = _state.value.copy(
                        ticketDetail = detail,
                        devices = detail.devices ?: emptyList(),
                        notes = detail.notes ?: emptyList(),
                        history = detail.history ?: emptyList(),
                        photos = detail.photos ?: emptyList(),
                        isLoading = false,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("TicketDetail", "Failed to load detail from API: ${e.message}")
                // If we have a cached entity, just show a soft warning — not a hard error
                if (_state.value.ticket != null) {
                    _state.value = _state.value.copy(isLoading = false)
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load ticket",
                    )
                }
            }
        }
    }

    private fun loadStatuses() {
        viewModelScope.launch {
            try {
                val response = settingsApi.getStatuses()
                val statuses = response.data?.statuses ?: emptyList()
                _state.value = _state.value.copy(statuses = statuses)
            } catch (_: Exception) {
                // Non-critical; status dropdown will be empty
            }
        }
    }

    fun changeStatus(newStatusId: Long) {
        val ticket = _state.value.ticket ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = UpdateTicketRequest(
                    statusId = newStatusId,
                    updatedAt = ticket.updatedAt,
                )
                ticketRepository.updateTicket(ticketId, request)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Status updated",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to change status: ${e.message}",
                )
            }
        }
    }

    fun addNote(text: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)

            if (serverMonitor.isEffectivelyOnline.value) {
                try {
                    ticketApi.addNote(ticketId, mapOf("type" to "internal", "content" to text))
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Note added",
                    )
                    loadTicketDetail()
                    return@launch
                } catch (_: Exception) {
                    // Fall through to offline queue
                }
            }

            // Offline: queue the note for later sync
            syncQueueDao.insert(
                com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity(
                    entityType = "ticket_note",
                    entityId = ticketId,
                    operation = "add",
                    payload = gson.toJson(mapOf("type" to "internal", "content" to text)),
                )
            )
            _state.value = _state.value.copy(
                isActionInProgress = false,
                actionMessage = "Note queued — will sync when online",
            )
        }
    }

    /**
     * Convert this ticket to an invoice. When online, calls the API immediately and sets
     * [TicketDetailUiState.convertedInvoiceId] so the screen can navigate to the new invoice.
     * When offline, queues a sync entry that SyncManager will replay later.
     */
    fun convertToInvoice() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)

            if (serverMonitor.isEffectivelyOnline.value) {
                try {
                    val response = ticketApi.convertToInvoice(ticketId)
                    val invoiceId = response.data?.id
                    if (invoiceId != null) {
                        _state.value = _state.value.copy(
                            isActionInProgress = false,
                            actionMessage = "Invoice created",
                            convertedInvoiceId = invoiceId,
                        )
                        return@launch
                    }
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Convert failed: server returned no invoice",
                    )
                    return@launch
                } catch (e: Exception) {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Convert failed: ${e.message ?: "unknown error"}",
                    )
                    return@launch
                }
            }

            // Offline: queue the conversion so SyncManager can replay it when back online.
            syncQueueDao.insert(
                com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity(
                    entityType = "ticket",
                    entityId = ticketId,
                    operation = "convert_to_invoice",
                    payload = gson.toJson(mapOf("ticketId" to ticketId)),
                )
            )
            _state.value = _state.value.copy(
                isActionInProgress = false,
                actionMessage = "Convert queued — will sync when online",
            )
        }
    }

    /** Clear the converted invoice ID after the screen has navigated, so we don't re-navigate on recomposition. */
    fun clearConvertedInvoiceId() {
        _state.value = _state.value.copy(convertedInvoiceId = null)
    }

    fun togglePin() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val response = ticketApi.togglePin(ticketId)
                val detail = response.data
                if (detail != null) {
                    _state.value = _state.value.copy(
                        ticketDetail = detail,
                        isActionInProgress = false,
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = if (e.message?.contains("Unable to resolve host") == true ||
                        e.message?.contains("timeout") == true)
                        "Pin/unpin requires server connection"
                    else "Failed to toggle pin: ${e.message}",
                )
            }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketDetailScreen(
    ticketId: Long,
    onBack: () -> Unit,
    onNavigateToCustomer: (Long) -> Unit,
    onNavigateToSms: ((String) -> Unit)? = null,
    onNavigateToInvoice: (Long) -> Unit = {},
    onEditDevice: (Long) -> Unit = {},
    // AND-20260414-M1: optional callback to open the photo capture /
    // gallery upload screen for this ticket. Registered in AppNavGraph as
    // `Screen.TicketPhotos`. Optional so previews and tests that don't
    // care about photos can omit it; the entry point is hidden when null.
    onAddPhotos: ((Long) -> Unit)? = null,
    viewModel: TicketDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val ticket = state.ticket

    // @audit-fixed: dialog visibility and the in-progress note text were lost
    // on rotation. The status dropdown is a transient menu so it can stay on
    // remember (re-opening is one tap), but anything the user has typed or any
    // confirmation dialog mid-decision must survive a config change so we move
    // those to rememberSaveable.
    var showStatusDropdown by remember { mutableStateOf(false) }
    // AND-20260414-M9: kebab-menu visibility for the overflow bucket (SMS +
    // Print). Transient like showStatusDropdown — re-opening after a rotation
    // is one tap and the alternative (rememberSaveable) would leak an open
    // menu across config changes, which is surprising UX.
    var showOverflowMenu by remember { mutableStateOf(false) }
    var showNoteDialog by rememberSaveable { mutableStateOf(false) }
    var noteText by rememberSaveable { mutableStateOf("") }
    var showConvertConfirm by rememberSaveable { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    // Navigate to the new invoice once convertToInvoice() succeeds.
    LaunchedEffect(state.convertedInvoiceId) {
        state.convertedInvoiceId?.let { invoiceId ->
            onNavigateToInvoice(invoiceId)
            viewModel.clearConvertedInvoiceId()
        }
    }

    // Confirmation dialog for Convert to Invoice
    if (showConvertConfirm) {
        ConfirmDialog(
            title = "Convert to Invoice?",
            message = "This will create a new invoice from this ticket. You can record payment later.",
            confirmLabel = "Convert",
            onConfirm = {
                showConvertConfirm = false
                viewModel.convertToInvoice()
            },
            onDismiss = { showConvertConfirm = false },
        )
    }

    // Note dialog
    if (showNoteDialog) {
        AlertDialog(
            onDismissRequest = { showNoteDialog = false; noteText = "" },
            title = { Text("Add Note") },
            text = {
                OutlinedTextField(
                    value = noteText,
                    onValueChange = { noteText = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Enter note...") },
                    minLines = 3,
                    maxLines = 6,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (noteText.isNotBlank()) {
                            viewModel.addNote(noteText.trim())
                            showNoteDialog = false
                            noteText = ""
                        }
                    },
                    enabled = noteText.isNotBlank(),
                ) {
                    Text("Add")
                }
            },
            dismissButton = {
                TextButton(onClick = { showNoteDialog = false; noteText = "" }) {
                    Text("Cancel")
                }
            },
        )
    }

    Scaffold(
        // D5-8: lift bottom-anchored inputs (notes, comments, SMS composer)
        // above the soft keyboard instead of letting them vanish beneath it.
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            // BrandTopAppBar with a custom title slot: orderId in mono + status badge.
            BrandTopAppBar(
                title = ticket?.orderId ?: "T-$ticketId",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (ticket != null) {
                        val detail = state.ticketDetail
                        IconButton(
                            onClick = { showConvertConfirm = true },
                            enabled = !state.isActionInProgress,
                        ) {
                            Icon(
                                Icons.Default.Receipt,
                                contentDescription = "Convert to Invoice",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        // AND-20260414-M6: Star button removed — backend doesn't
                        // support starring yet. Follow CROSS14/FA-L7/FA-L1 pattern:
                        // better no control than a dead click. Reintroduce once the
                        // server exposes a toggle-star endpoint.
                        IconButton(onClick = { viewModel.togglePin() }) {
                            Icon(
                                Icons.Default.PushPin,
                                contentDescription = "Pin",
                                tint = if (detail?.isPinned == true) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            // AND-20260414-M9: on a native 1440x3120 phone (~360dp logical
            // width) five labeled TextButtons overflowed — the last one
            // (Print) rendered as a 35dp-wide column with the word stacked
            // vertically. Fix: keep the three primary actions (Status,
            // Call, Note) inline and fold the two secondary actions (SMS,
            // Print) into a kebab overflow menu anchored to the right.
            //
            // We intentionally did NOT use `Modifier.horizontalScroll` —
            // horizontal scrolling on a bottom bar is a discoverability
            // hazard (users don't expect a bar to scroll) and the TODO's
            // preferred option (b) spec called for an overflow menu.
            //
            // `navigationBarsPadding()` lives on `BottomAppBar` by default
            // via its Material3 windowInsets param, so the safe-area gap
            // is preserved.
            BottomAppBar {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box {
                        TextButton(
                            onClick = { showStatusDropdown = true },
                            enabled = !state.isActionInProgress,
                        ) {
                            Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Status")
                        }
                        DropdownMenu(
                            expanded = showStatusDropdown,
                            onDismissRequest = { showStatusDropdown = false },
                        ) {
                            state.statuses.forEach { status ->
                                DropdownMenuItem(
                                    text = {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            Surface(
                                                shape = MaterialTheme.shapes.extraSmall,
                                                color = try {
                                                    Color(android.graphics.Color.parseColor(status.color ?: "#6b7280"))
                                                } catch (_: Exception) {
                                                    MaterialTheme.colorScheme.primary
                                                },
                                                modifier = Modifier.size(12.dp),
                                            ) {}
                                            Text(status.name)
                                        }
                                    },
                                    onClick = {
                                        showStatusDropdown = false
                                        viewModel.changeStatus(status.id)
                                    },
                                    enabled = status.id != ticket?.statusId,
                                )
                            }
                        }
                    }
                    run {
                        val context = LocalContext.current
                        val detail = state.ticketDetail
                        val phone = detail?.customer?.phone ?: detail?.customer?.mobile ?: ticket?.customerPhone
                        TextButton(
                            onClick = {
                                if (phone != null) {
                                    val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${phone}"))
                                    context.startActivity(intent)
                                }
                            },
                            enabled = phone != null,
                        ) {
                            Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Call")
                        }
                    }
                    TextButton(
                        onClick = { showNoteDialog = true },
                        enabled = !state.isActionInProgress,
                    ) {
                        Icon(Icons.Default.Note, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Note")
                    }
                    // Overflow menu (SMS + Print) — AND-20260414-M9.
                    run {
                        val context = LocalContext.current
                        val smsDetail = state.ticketDetail
                        val smsPhone = smsDetail?.customer?.phone
                            ?: smsDetail?.customer?.mobile
                            ?: ticket?.customerPhone
                        val canSms = smsPhone != null && onNavigateToSms != null
                        val serverUrl = viewModel.serverUrl
                        // AND-20260414-L1: Print launches a browser intent
                        // against the CRM server's `/print/ticket/:id` route.
                        // Without a configured server URL OR while offline
                        // the intent would resolve to an unreachable URL, so
                        // the menu item disables itself. Compose swallows
                        // taps on disabled DropdownMenuItems silently, so
                        // users don't get a blank-screen mystery — the
                        // disabled state visually communicates the blocker.
                        //
                        // TODO(AND-20260414-L1): build a proper offline
                        // receipt renderer on device so this flow works
                        // without network — that's the "proper fix"
                        // deferred per the spec.
                        val isOnline by viewModel.isEffectivelyOnline.collectAsState()
                        val canPrint = serverUrl.isNotBlank() && isOnline
                        Box {
                            IconButton(
                                onClick = { showOverflowMenu = true },
                                enabled = !state.isActionInProgress,
                            ) {
                                Icon(
                                    Icons.Default.MoreVert,
                                    contentDescription = "More actions",
                                )
                            }
                            DropdownMenu(
                                expanded = showOverflowMenu,
                                onDismissRequest = { showOverflowMenu = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("SMS") },
                                    leadingIcon = {
                                        Icon(
                                            Icons.Default.Sms,
                                            contentDescription = null,
                                            modifier = Modifier.size(18.dp),
                                        )
                                    },
                                    onClick = {
                                        showOverflowMenu = false
                                        if (smsPhone != null && onNavigateToSms != null) {
                                            val normalized = smsPhone
                                                .replace(Regex("[^0-9]"), "")
                                                .let {
                                                    if (it.length == 11 && it.startsWith("1")) it.substring(1) else it
                                                }
                                            onNavigateToSms(normalized)
                                        }
                                    },
                                    enabled = canSms,
                                )
                                DropdownMenuItem(
                                    text = { Text("Print") },
                                    leadingIcon = {
                                        Icon(
                                            Icons.Default.Print,
                                            contentDescription = null,
                                            modifier = Modifier.size(18.dp),
                                        )
                                    },
                                    onClick = {
                                        showOverflowMenu = false
                                        if (canPrint) {
                                            val url = "$serverUrl/print/ticket/$ticketId?size=letter"
                                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                            context.startActivity(intent)
                                        } else {
                                            android.widget.Toast.makeText(
                                                context,
                                                "Print requires network + configured server",
                                                android.widget.Toast.LENGTH_SHORT,
                                            ).show()
                                        }
                                    },
                                    enabled = canPrint,
                                )
                            }
                        }
                    }
                }
            }
        },
    ) { padding ->
        when {
            state.isLoading -> {
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier.padding(padding).padding(top = 8.dp),
                )
            }
            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load ticket",
                        onRetry = { viewModel.loadTicketDetail() },
                    )
                }
            }
            ticket != null -> {
                TicketDetailContent(
                    ticket = ticket,
                    ticketId = ticketId,
                    ticketDetail = state.ticketDetail,
                    devices = state.devices,
                    notes = state.notes,
                    history = state.history,
                    photos = state.photos,
                    padding = padding,
                    onNavigateToCustomer = onNavigateToCustomer,
                    onEditDevice = onEditDevice,
                    // AND-20260414-M1: thread the add-photos callback into the
                    // lazy list so the Photos section header can expose an
                    // "Add Photo" TextButton.
                    onAddPhotos = onAddPhotos,
                    serverUrl = viewModel.serverUrl,
                )
            }
        }
    }
}

@Composable
private fun TicketDetailContent(
    ticket: TicketEntity,
    // AND-20260414-M1: the ticket id from the route args. Needed by the
    // Photos section so tapping "Add Photo" can create the
    // `tickets/{ticketId}/photos` destination. Kept separate from
    // `ticket.id` because TicketEntity.id may not equal the URL param in
    // corner cases (offline-created tickets use a negative temp id).
    ticketId: Long,
    ticketDetail: TicketDetail?,
    devices: List<TicketDevice>,
    notes: List<TicketNote>,
    history: List<TicketHistory>,
    photos: List<TicketPhoto>,
    padding: PaddingValues,
    onNavigateToCustomer: (Long) -> Unit,
    onEditDevice: (Long) -> Unit = {},
    onAddPhotos: ((Long) -> Unit)? = null,
    serverUrl: String = "",
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Customer card
        item {
            val customerName = ticketDetail?.customer?.let {
                "${it.firstName ?: ""} ${it.lastName ?: ""}".trim()
            }?.ifBlank { null }
                ?: ticket.customerName
                ?: "Unknown Customer"

            BrandCard(
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    ticket.customerId?.let { if (it > 0) onNavigateToCustomer(it) }
                },
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Default.Person, contentDescription = null)
                    Column {
                        Text(
                            customerName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        // CROSS8: shared formatPhoneDisplay emits +1 (XXX)-XXX-XXXX.
                        val phone = ticketDetail?.customer?.phone ?: ticket.customerPhone
                        if (phone != null) {
                            Text(formatPhoneDisplay(phone), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(
                            "Tap to view customer",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Info row
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                BrandCard(modifier = Modifier.weight(1f)) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text("Created", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        // CROSS46: canonical "April 16, 2026" rendering.
                        Text(DateFormatter.formatAbsolute(ticket.createdAt).ifBlank { "-" }, style = MaterialTheme.typography.bodySmall)
                    }
                }
                val assignedUser = ticketDetail?.assignedUser
                if (assignedUser != null) {
                    BrandCard(modifier = Modifier.weight(1f)) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Text("Assigned", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(assignedUser.fullName, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }

        // Devices section
        item {
            Text("Devices", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        }

        if (devices.isEmpty()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        if (ticket.firstDeviceName != null) ticket.firstDeviceName else "No devices",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(devices, key = { it.id }) { device ->
                // Thin purple left-accent when device is being actively repaired
                val isActive = device.statusName?.lowercase()?.let { s ->
                    s.contains("repair") || s.contains("progress") || s.contains("diagnos")
                } ?: false
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    // 2dp accent bar at the very top of card when active repair
                    if (isActive) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(2.dp)
                                .background(MaterialTheme.colorScheme.primary),
                        )
                    }
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                device.name ?: device.deviceName ?: "Device",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier.weight(1f),
                            )
                            IconButton(
                                onClick = { onEditDevice(device.id) },
                                modifier = Modifier.size(32.dp),
                            ) {
                                Icon(
                                    Icons.Default.Edit,
                                    contentDescription = "Edit device",
                                    modifier = Modifier.size(18.dp),
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
                        if (!device.additionalNotes.isNullOrBlank()) {
                            Text(
                                device.additionalNotes,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (!device.imei.isNullOrBlank()) {
                            Text("IMEI: ${device.imei}", style = MaterialTheme.typography.bodySmall)
                        }
                        if (!device.serial.isNullOrBlank()) {
                            Text("Serial: ${device.serial}", style = MaterialTheme.typography.bodySmall)
                        }
                        if (!device.securityCode.isNullOrBlank()) {
                            Text("Passcode: ${device.securityCode}", style = MaterialTheme.typography.bodySmall)
                        }
                        if (device.price != null && device.price > 0) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                "$${String.format("%.2f", device.total ?: device.price)}",
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        // Parts
                        val parts = device.parts ?: emptyList()
                        if (parts.isNotEmpty()) {
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("Parts:", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
                            parts.forEach { part ->
                                Text(
                                    "  ${part.name ?: "Part"} x${part.quantity ?: 1}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }

        // Notes section
        if (notes.isNotEmpty()) {
            item {
                Text("Notes", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            }
            items(notes, key = { it.id }) { note ->
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                note.userName ?: "Staff",
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                DateFormatter.formatDateTime(note.createdAt),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(stripHtml(note.msgText), style = MaterialTheme.typography.bodySmall)
                        if (note.isFlagged == true) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Icon(
                                Icons.Default.Flag,
                                contentDescription = "Flagged",
                                modifier = Modifier.size(14.dp),
                                tint = ErrorRed,
                            )
                        }
                    }
                }
            }
        }

        // Timeline / History section
        if (history.isNotEmpty()) {
            item {
                Text("Timeline", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            }
            items(history, key = { it.id }) { entry ->
                Row(
                    modifier = Modifier.padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Default.Circle,
                        contentDescription = null,
                        modifier = Modifier
                            .size(8.dp)
                            .offset(y = 6.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Column {
                        Text(stripHtml(entry.description), style = MaterialTheme.typography.bodySmall)
                        Text(
                            DateFormatter.formatDateTime(entry.createdAt),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Photos section
        //
        // AND-20260414-M1: previously this block was gated on
        // `photos.isNotEmpty()`, so a ticket with no photos had no way to
        // surface the upload flow — the PhotoCaptureScreen composable
        // existed under ui/screens/camera/ but nothing navigated to it.
        // We now always render the Photos card when an `onAddPhotos`
        // callback is wired, giving technicians an "Add Photo" entry
        // point even before the first photo is attached. When the
        // callback is absent (e.g. in previews), we fall back to the old
        // display-only behavior so we don't render a dead card.
        val canAddPhotos = onAddPhotos != null
        if (photos.isNotEmpty() || canAddPhotos) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Photos (${photos.size})",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (canAddPhotos) {
                        TextButton(onClick = { onAddPhotos?.invoke(ticketId) }) {
                            Icon(
                                Icons.Default.AddAPhoto,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Add Photo")
                        }
                    }
                }
            }
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        if (photos.isEmpty()) {
                            Text(
                                "No photos yet — tap Add Photo to attach repair images.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                photos.forEach { photo ->
                                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                        AsyncImage(
                                            model = "${serverUrl}${photo.url}",
                                            contentDescription = photo.fileName ?: "Ticket photo",
                                            modifier = Modifier
                                                .size(100.dp)
                                                .clip(RoundedCornerShape(8.dp)),
                                            contentScale = ContentScale.Crop,
                                        )
                                        Spacer(modifier = Modifier.height(4.dp))
                                        Text(
                                            photo.type ?: "photo",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Total
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    if (ticket.subtotal != 0L && ticket.subtotal != ticket.total) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Subtotal", style = MaterialTheme.typography.bodyMedium)
                            Text(ticket.subtotal.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    if (ticket.discount > 0) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Discount", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                            Text("-${ticket.discount.formatAsMoney()}", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                        }
                    }
                    if (ticket.totalTax > 0) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Tax", style = MaterialTheme.typography.bodyMedium)
                            Text(ticket.totalTax.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 4.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Total", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text(
                            ticket.total.formatAsMoney(),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }
        }
    }
}
