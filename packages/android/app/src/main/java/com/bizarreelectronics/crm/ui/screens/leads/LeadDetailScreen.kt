package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.data.remote.dto.UpdateLeadRequest
import com.bizarreelectronics.crm.data.repository.LeadRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.StatusTone
import com.bizarreelectronics.crm.ui.components.shared.statusToneFor
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.util.PhoneFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LeadDetailUiState(
    val lead: LeadEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
)

/**
 * Status options — labels only, no hardcoded colors.
 * [BrandStatusBadge] / [statusToneFor] provide the 5-hue discipline.
 */
private data class LeadStatusOption(
    val key: String,
    val label: String,
)

private val LEAD_STATUS_OPTIONS = listOf(
    LeadStatusOption("new", "New"),
    LeadStatusOption("contacted", "Contacted"),
    LeadStatusOption("scheduled", "Scheduled"),
    LeadStatusOption("qualified", "Qualified"),
    LeadStatusOption("proposal", "Proposal"),
    LeadStatusOption("converted", "Converted"),
    LeadStatusOption("lost", "Lost"),
)

private fun optionFor(status: String?): LeadStatusOption? {
    if (status.isNullOrBlank()) return null
    return LEAD_STATUS_OPTIONS.firstOrNull { it.key.equals(status, ignoreCase = true) }
}

@HiltViewModel
class LeadDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val leadRepository: LeadRepository,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val leadId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(LeadDetailUiState())
    val state = _state.asStateFlow()

    /** Emits true when the conversion succeeds; LeadDetailScreen observes to navigate. */
    private val _convertedTicketId = MutableStateFlow<Long?>(null)
    val convertedTicketId = _convertedTicketId.asStateFlow()

    val isOnline get() = serverMonitor.isEffectivelyOnline

    init {
        collectLead()
    }

    private fun collectLead() {
        viewModelScope.launch {
            leadRepository.getLead(leadId).collect { entity ->
                _state.value = _state.value.copy(
                    lead = entity,
                    isLoading = false,
                    error = if (entity == null && !_state.value.isLoading) "Lead not found" else null,
                )
            }
        }
    }

    fun updateStatus(newStatus: String) {
        val lead = _state.value.lead ?: return
        if (lead.status.equals(newStatus, ignoreCase = true)) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                leadRepository.updateLead(
                    leadId,
                    UpdateLeadRequest(status = newStatus),
                )
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Status updated to ${newStatus.replaceFirstChar { it.uppercase() }}",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to update status: ${e.message}",
                )
            }
        }
    }

    fun convertToTicket() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val ticketId = leadRepository.convertLead(leadId)
                if (ticketId != null) {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Lead converted to ticket",
                    )
                    _convertedTicketId.value = ticketId
                } else {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Convert failed: no ticket returned",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to convert: ${e.message}",
                )
            }
        }
    }

    fun delete() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                // Soft-delete by marking isDeleted — the server's delete endpoint
                // isn't wired in the repository yet, so we use updateLead for now.
                leadRepository.updateLead(
                    leadId,
                    UpdateLeadRequest(status = "lost", lostReason = "Deleted by user"),
                )
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Lead marked as lost",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to delete: ${e.message}",
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
fun LeadDetailScreen(
    leadId: Long,
    onBack: () -> Unit,
    onConverted: (ticketId: Long) -> Unit,
    viewModel: LeadDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val convertedTicketId by viewModel.convertedTicketId.collectAsState()
    val isOnline by viewModel.isOnline.collectAsState()
    val lead = state.lead

    // @audit-fixed: showDeleteConfirm previously used remember{} which meant a
    // rotation while the user was deciding whether to delete the lead would
    // silently dismiss the warning dialog. Status dropdown is fine on remember
    // because it's a transient menu, but a destructive confirm must persist.
    var showStatusDropdown by remember { mutableStateOf(false) }
    var showDeleteConfirm by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate when conversion succeeds
    LaunchedEffect(convertedTicketId) {
        val ticketId = convertedTicketId
        if (ticketId != null) {
            onConverted(ticketId)
        }
    }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    // Delete confirmation dialog — migrated to ConfirmDialog(isDestructive = true)
    if (showDeleteConfirm) {
        com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog(
            title = "Delete Lead",
            message = "Mark this lead as lost? This can be reversed by changing the status.",
            confirmLabel = "Delete",
            onConfirm = {
                showDeleteConfirm = false
                viewModel.delete()
            },
            onDismiss = { showDeleteConfirm = false },
            isDestructive = true,
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    val fullName = listOfNotNull(lead?.firstName, lead?.lastName)
                        .joinToString(" ")
                        .ifBlank { lead?.orderId ?: "Lead" }
                    Text(fullName)
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Error",
                        onRetry = null,
                    )
                }
            }
            lead != null -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // Header: name + phone
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                val fullName = listOfNotNull(lead.firstName, lead.lastName)
                                    .joinToString(" ")
                                    .ifBlank { "Unknown" }
                                Text(
                                    fullName,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                if (!lead.phone.isNullOrBlank()) {
                                    Text(
                                        PhoneFormatter.format(lead.phone),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                if (!lead.orderId.isNullOrBlank()) {
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        lead.orderId,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }

                    // Status dropdown
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    "Status",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Spacer(modifier = Modifier.height(6.dp))
                                Box {
                                    val currentOption = optionFor(lead.status)
                                    val currentStatus = lead.status ?: ""
                                    val currentLabel = currentOption?.label ?: currentStatus

                                    // D5-3: Clickable status badge using the
                                    // Surface(onClick = ...) overload so the
                                    // M3 ripple renders on tap. The previous
                                    // Surface + .clickable pairing swallowed
                                    // the ripple indication layer.
                                    Surface(
                                        onClick = { showStatusDropdown = true },
                                        enabled = !state.isActionInProgress,
                                        shape = MaterialTheme.shapes.small,
                                        color = MaterialTheme.colorScheme.surfaceVariant,
                                    ) {
                                        Row(
                                            modifier = Modifier.padding(
                                                horizontal = 12.dp,
                                                vertical = 6.dp,
                                            ),
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            // Brand-colored label text using theme color
                                            val tone = statusToneFor(currentStatus)
                                            val textColor = when (tone) {
                                                StatusTone.Purple -> MaterialTheme.colorScheme.primary
                                                StatusTone.Teal -> MaterialTheme.colorScheme.secondary
                                                StatusTone.Magenta -> MaterialTheme.colorScheme.tertiary
                                                StatusTone.Success -> SuccessGreen
                                                StatusTone.Error -> MaterialTheme.colorScheme.error
                                                StatusTone.Muted -> MaterialTheme.colorScheme.onSurfaceVariant
                                            }
                                            Text(
                                                currentLabel,
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = textColor,
                                                fontWeight = FontWeight.Medium,
                                            )
                                            Spacer(modifier = Modifier.width(4.dp))
                                            Icon(
                                                Icons.Default.ArrowDropDown,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                    DropdownMenu(
                                        expanded = showStatusDropdown,
                                        onDismissRequest = { showStatusDropdown = false },
                                    ) {
                                        LEAD_STATUS_OPTIONS.forEach { option ->
                                            DropdownMenuItem(
                                                text = {
                                                    Row(
                                                        verticalAlignment = Alignment.CenterVertically,
                                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                                    ) {
                                                        // Tiny brand dot replaces colored square
                                                        BrandStatusBadge(
                                                            label = option.label,
                                                            status = option.key,
                                                        )
                                                    }
                                                },
                                                onClick = {
                                                    showStatusDropdown = false
                                                    viewModel.updateStatus(option.key)
                                                },
                                                enabled = !lead.status.equals(
                                                    option.key,
                                                    ignoreCase = true,
                                                ),
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Contact info card
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    "Contact",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                LabelValueRow(
                                    icon = Icons.Default.Phone,
                                    label = "Phone",
                                    value = lead.phone?.let { PhoneFormatter.format(it) },
                                )
                                LabelValueRow(
                                    icon = Icons.Default.Email,
                                    label = "Email",
                                    value = lead.email,
                                )
                                val locationLine = listOfNotNull(
                                    lead.address?.takeIf { it.isNotBlank() },
                                    lead.zipCode?.takeIf { it.isNotBlank() },
                                ).joinToString(", ").ifBlank { null }
                                LabelValueRow(
                                    icon = Icons.Default.LocationOn,
                                    label = "Address",
                                    value = locationLine,
                                )
                            }
                        }
                    }

                    // Source and referral info
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(
                                modifier = Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    "Source",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                LabelValueRow(
                                    icon = Icons.Default.Campaign,
                                    label = "Source",
                                    value = lead.source,
                                )
                                LabelValueRow(
                                    icon = Icons.Default.People,
                                    label = "Referred By",
                                    value = lead.referredBy,
                                )
                                LabelValueRow(
                                    icon = Icons.Default.AssignmentInd,
                                    label = "Assigned To",
                                    value = lead.assignedName,
                                )
                            }
                        }
                    }

                    // Lead score
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        "Lead Score",
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Text(
                                        "${lead.leadScore} / 100",
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                                Spacer(modifier = Modifier.height(8.dp))
                                LinearProgressIndicator(
                                    progress = { (lead.leadScore.coerceIn(0, 100)) / 100f },
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }

                    // Notes section
                    if (!lead.notes.isNullOrBlank()) {
                        item {
                            Card(modifier = Modifier.fillMaxWidth()) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Text(
                                        "Notes",
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Spacer(modifier = Modifier.height(6.dp))
                                    Text(
                                        lead.notes,
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                }
                            }
                        }
                    }

                    // Action buttons
                    item {
                        Column(
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            // CROSS48-adopt-more: Convert to Ticket is the one
                            // positive terminal action on lead detail; filled
                            // primary hierarchy via BrandPrimaryButton (not a
                            // raw Button whose default `primary` fill reads
                            // the same, but intent is now explicit).
                            BrandPrimaryButton(
                                onClick = { viewModel.convertToTicket() },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = isOnline &&
                                    !state.isActionInProgress &&
                                    !lead.status.equals("converted", ignoreCase = true),
                            ) {
                                Icon(
                                    Icons.Default.SwapHoriz,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    if (!isOnline) "Convert to Ticket (Offline)"
                                    else "Convert to Ticket"
                                )
                            }
                            // Delete = outlined error-red (destructive)
                            OutlinedButton(
                                onClick = { showDeleteConfirm = true },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = !state.isActionInProgress,
                                colors = ButtonDefaults.outlinedButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error,
                                ),
                            ) {
                                Icon(
                                    Icons.Default.Delete,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Delete")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LabelValueRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String?,
) {
    if (value.isNullOrBlank()) return
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                value,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}
