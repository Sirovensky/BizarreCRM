package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Status color swatches (tenant-recognisable palette) ──────────────────────
private val STATUS_COLOR_SWATCHES = listOf(
    "#6b7280", // neutral gray  (Intake / default)
    "#3b82f6", // blue          (Diagnostic)
    "#f59e0b", // amber         (Awaiting Parts)
    "#8b5cf6", // purple        (In Repair)
    "#10b981", // green         (Ready / Completed)
    "#ef4444", // red           (Cancelled / Unrepair)
    "#ec4899", // pink          (Warranty Return)
    "#06b6d4", // cyan          (Awaiting Approval)
    "#f97316", // orange        (Urgent)
    "#84cc16", // lime          (QA)
    "#14b8a6", // teal          (On-site)
    "#a78bfa", // lavender      (Low priority)
)

// ─── UiState ──────────────────────────────────────────────────────────────────

data class StatusEditorUiState(
    val statuses: List<TicketStatusItem> = emptyList(),
    val isLoading: Boolean = false,
    val savingId: Long? = null,   // non-null while PUT in flight
    val errorMessage: String? = null,
    val snackMessage: String? = null,
)

// ─── ViewModel ────────────────────────────────────────────────────────────────

@HiltViewModel
class TicketStatusEditorViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _state = MutableStateFlow(StatusEditorUiState(isLoading = true))
    val state: StateFlow<StatusEditorUiState> = _state.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            runCatching { settingsApi.getStatusList() }
                .onSuccess { resp ->
                    val items = resp.data ?: emptyList()
                    _state.value = _state.value.copy(
                        statuses = items.sortedBy { it.sortOrder },
                        isLoading = false,
                    )
                }
                .onFailure { err ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        errorMessage = "Could not load statuses: ${err.message}",
                    )
                }
        }
    }

    /**
     * Persist an edited status row.
     * [name], [color] (hex), [notifyCustomer], [isClosed], [isCancelled],
     * [waitingCustomer], [awaitingParts] are sent to PUT /settings/statuses/:id.
     *
     * [waitingCustomer] and [awaitingParts] control server-side SLA pause
     * (§4.19 / §19.16): when a ticket moves to a status with either flag set,
     * the SLA countdown is suspended until the status changes again.
     *
     * Optimistic update applied immediately; rolled back on failure.
     */
    fun saveStatus(
        id: Long,
        name: String,
        color: String,
        notifyCustomer: Boolean,
        isClosed: Boolean,
        isCancelled: Boolean,
        waitingCustomer: Boolean,
        awaitingParts: Boolean,
    ) {
        if (name.isBlank()) return
        val original = _state.value.statuses.find { it.id == id } ?: return

        // Optimistic update
        _state.value = _state.value.copy(
            savingId = id,
            statuses = _state.value.statuses.map { s ->
                if (s.id == id) s.copy(
                    name = name,
                    color = color,
                    notifyCustomer = if (notifyCustomer) 1 else 0,
                    isClosed = if (isClosed) 1 else 0,
                    isCancelled = if (isCancelled) 1 else 0,
                    waitingCustomer = if (waitingCustomer) 1 else 0,
                    awaitingParts = if (awaitingParts) 1 else 0,
                ) else s
            },
        )

        viewModelScope.launch {
            runCatching {
                settingsApi.putStatus(
                    id = id,
                    body = buildMap {
                        put("name", name)
                        put("color", color)
                        put("notify_customer", if (notifyCustomer) 1 else 0)
                        put("is_closed", if (isClosed) 1 else 0)
                        put("is_cancelled", if (isCancelled) 1 else 0)
                        put("waiting_customer", if (waitingCustomer) 1 else 0)
                        put("awaiting_parts", if (awaitingParts) 1 else 0)
                    },
                )
            }.onSuccess {
                _state.value = _state.value.copy(
                    savingId = null,
                    snackMessage = "\"$name\" saved",
                )
            }.onFailure { err ->
                // Roll back
                _state.value = _state.value.copy(
                    savingId = null,
                    statuses = _state.value.statuses.map { s ->
                        if (s.id == id) original else s
                    },
                    snackMessage = "Save failed: ${err.message}",
                )
            }
        }
    }

    fun clearSnack() { _state.value = _state.value.copy(snackMessage = null) }
    fun clearError() { _state.value = _state.value.copy(errorMessage = null) }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

/**
 * §19.16 Ticket-status editor.
 *
 * Lists all tenant ticket statuses (GET /settings/statuses).
 * Tapping the Edit icon for a row opens [StatusEditDialog] where staff can:
 *   - Rename the status
 *   - Pick a color from the swatch palette
 *   - Toggle "Notify customer on this transition"
 *   - Toggle "Counts as closed" / "Counts as cancelled"
 *   - Toggle "Pauses SLA — waiting for customer" (§4.19)
 *   - Toggle "Pauses SLA — awaiting parts" (§4.19)
 *
 * Changes are persisted via PUT /settings/statuses/:id (admin-only on server).
 * Optimistic update applied; rolled back on network failure.
 *
 * Does NOT support reorder (drag) or delete — those require a broader UX pass
 * that includes transition-guard matrix. Deferred per §19.16 notes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketStatusEditorScreen(
    onBack: () -> Unit,
    viewModel: TicketStatusEditorViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    // Status row that is currently open in the edit dialog (null = no dialog)
    var editingStatus by remember { mutableStateOf<TicketStatusItem?>(null) }

    LaunchedEffect(state.snackMessage) {
        state.snackMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearSnack()
        }
    }
    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Ticket Statuses") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.statuses.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No statuses found.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        vertical = 8.dp,
                    ),
                ) {
                    items(state.statuses, key = { it.id }) { status ->
                        StatusRow(
                            status = status,
                            isSaving = state.savingId == status.id,
                            onEdit = { editingStatus = status },
                        )
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                    }
                }
            }
        }
    }

    // Edit dialog — shown when a status row's Edit icon is tapped
    editingStatus?.let { target ->
        StatusEditDialog(
            status = target,
            onDismiss = { editingStatus = null },
            onSave = { name, color, notify, closed, cancelled, waitingCust, awaitParts ->
                viewModel.saveStatus(
                    id = target.id,
                    name = name,
                    color = color,
                    notifyCustomer = notify,
                    isClosed = closed,
                    isCancelled = cancelled,
                    waitingCustomer = waitingCust,
                    awaitingParts = awaitParts,
                )
                editingStatus = null
            },
        )
    }
}

// ─── Status list row ──────────────────────────────────────────────────────────

@Composable
private fun StatusRow(
    status: TicketStatusItem,
    isSaving: Boolean,
    onEdit: () -> Unit,
) {
    val dotColor = remember(status.color) {
        runCatching {
            Color(android.graphics.Color.parseColor(status.color ?: "#6b7280"))
        }.getOrElse { Color(0xFF6b7280) }
    }

    ListItem(
        headlineContent = {
            Text(
                status.name,
                fontWeight = FontWeight.Medium,
            )
        },
        supportingContent = {
            val tags = buildList {
                if (status.isClosed == 1) add("Closed")
                if (status.isCancelled == 1) add("Cancelled")
                if (status.notifyCustomer == 1) add("Notifies customer")
                if (status.waitingCustomer == 1) add("SLA paused — waiting customer")
                if (status.awaitingParts == 1) add("SLA paused — awaiting parts")
            }
            if (tags.isNotEmpty()) {
                Text(
                    tags.joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        leadingContent = {
            Box(
                modifier = Modifier
                    .size(18.dp)
                    .clip(CircleShape)
                    .background(dotColor)
                    .semantics {
                        contentDescription = "Status color: ${status.color ?: "gray"}"
                    },
            )
        },
        trailingContent = {
            if (isSaving) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
            } else {
                IconButton(
                    onClick = onEdit,
                    modifier = Modifier.semantics {
                        contentDescription = "Edit status ${status.name}"
                    },
                ) {
                    Icon(Icons.Filled.Edit, contentDescription = null)
                }
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}

// ─── Edit dialog ──────────────────────────────────────────────────────────────

/**
 * [AlertDialog]-based editor for a single [TicketStatusItem].
 *
 * Fields:
 *  - Name (required, ≤ 100 chars)
 *  - Color swatch row (12 pre-set hex swatches)
 *  - "Notify customer on this transition" switch
 *  - "Counts as closed" switch
 *  - "Counts as cancelled" switch
 *  - "Pauses SLA — waiting for customer" switch (§4.19 / §19.16)
 *  - "Pauses SLA — awaiting parts" switch (§4.19 / §19.16)
 *
 * The two SLA-pause flags are persisted via PUT /settings/statuses/:id as
 * `waiting_customer` and `awaiting_parts`.  The server SLA calculator reads
 * these columns directly to suspend the countdown while a ticket holds a
 * matching status.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StatusEditDialog(
    status: TicketStatusItem,
    onDismiss: () -> Unit,
    onSave: (
        name: String,
        color: String,
        notifyCustomer: Boolean,
        isClosed: Boolean,
        isCancelled: Boolean,
        waitingCustomer: Boolean,
        awaitingParts: Boolean,
    ) -> Unit,
) {
    var name by remember { mutableStateOf(status.name) }
    var selectedColor by remember { mutableStateOf(status.color ?: "#6b7280") }
    var notifyCustomer by remember { mutableStateOf(status.notifyCustomer == 1) }
    var isClosed by remember { mutableStateOf(status.isClosed == 1) }
    var isCancelled by remember { mutableStateOf(status.isCancelled == 1) }
    var waitingCustomer by remember { mutableStateOf(status.waitingCustomer == 1) }
    var awaitingParts by remember { mutableStateOf(status.awaitingParts == 1) }

    val nameError = name.isBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit status") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // ── Name ──────────────────────────────────────────────────────
                OutlinedTextField(
                    value = name,
                    onValueChange = { if (it.length <= 100) name = it },
                    label = { Text("Status name") },
                    isError = nameError,
                    supportingText = {
                        if (nameError) Text("Name is required")
                        else Text("${name.length}/100")
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )

                // ── Color swatches ────────────────────────────────────────────
                Text(
                    "Color",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    STATUS_COLOR_SWATCHES.forEach { hex ->
                        val swatchColor = remember(hex) {
                            runCatching {
                                Color(android.graphics.Color.parseColor(hex))
                            }.getOrElse { Color(0xFF6b7280) }
                        }
                        val isSelected = selectedColor.equals(hex, ignoreCase = true)
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(swatchColor)
                                .then(
                                    if (isSelected) Modifier.border(
                                        width = 3.dp,
                                        color = MaterialTheme.colorScheme.onSurface,
                                        shape = CircleShape,
                                    ) else Modifier
                                )
                                .clickable { selectedColor = hex }
                                .semantics {
                                    contentDescription = if (isSelected)
                                        "Color $hex, selected"
                                    else
                                        "Color $hex"
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (isSelected) {
                                Icon(
                                    Icons.Filled.Check,
                                    contentDescription = null,
                                    tint = Color.White,
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                        }
                    }
                }

                HorizontalDivider()

                // ── Toggles ───────────────────────────────────────────────────
                StatusToggleRow(
                    label = "Notify customer on transition",
                    supporting = "Send configured SMS/email when ticket moves to this status",
                    checked = notifyCustomer,
                    onCheckedChange = { notifyCustomer = it },
                )
                StatusToggleRow(
                    label = "Counts as closed",
                    supporting = "Closed tickets are excluded from open-ticket counts",
                    checked = isClosed,
                    onCheckedChange = { isClosed = it },
                )
                StatusToggleRow(
                    label = "Counts as cancelled",
                    supporting = "Cancelled tickets are tracked separately in reports",
                    checked = isCancelled,
                    onCheckedChange = { isCancelled = it },
                )

                HorizontalDivider()

                // ── SLA pause flags (§4.19 / §19.16) ─────────────────────────
                Text(
                    "SLA behaviour",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                StatusToggleRow(
                    label = "Pauses SLA — waiting for customer",
                    supporting = "SLA countdown suspends while ticket holds this status. " +
                        "Use when you are waiting for customer approval or reply.",
                    checked = waitingCustomer,
                    onCheckedChange = { waitingCustomer = it },
                )
                StatusToggleRow(
                    label = "Pauses SLA — awaiting parts",
                    supporting = "SLA countdown suspends while parts are on order. " +
                        "Resume is automatic when status changes.",
                    checked = awaitingParts,
                    onCheckedChange = { awaitingParts = it },
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (!nameError) onSave(
                        name, selectedColor, notifyCustomer,
                        isClosed, isCancelled, waitingCustomer, awaitingParts,
                    )
                },
                enabled = !nameError,
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Reusable toggle row ──────────────────────────────────────────────────────

@Composable
private fun StatusToggleRow(
    label: String,
    supporting: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(
                supporting,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(12.dp))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.semantics { contentDescription = label },
        )
    }
}
