package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.unit.sp
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
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.UpdateLeadRequest
import com.bizarreelectronics.crm.data.repository.LeadRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.StatusTone
import com.bizarreelectronics.crm.ui.components.shared.statusToneFor
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadScoreIndicator
import com.bizarreelectronics.crm.ui.screens.leads.components.LostReasonDialog
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.util.PhoneFormatter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.UndoStack
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Domain type for lead undo entries (§1 L232)
// ---------------------------------------------------------------------------

/**
 * Sealed payload type covering all reversible lead mutations wired to
 * [UndoStack] in [LeadDetailViewModel]. Immutable data classes only.
 */
sealed class LeadEdit {
    /** A generic scalar field update (e.g. notes, referredBy, source). */
    data class FieldEdit(
        val fieldName: String,
        val oldValue: String?,
        val newValue: String?,
    ) : LeadEdit()

    /** Stage change — leads use string-key stages (new, contacted, scheduled…). */
    data class StageChange(
        val oldStage: String?,
        val newStage: String,
    ) : LeadEdit()

    /** Status change — alias for stage in the lead domain (status == stage). */
    data class StatusChange(
        val oldStatus: String?,
        val newStatus: String,
    ) : LeadEdit()

    /**
     * A note that was persisted (noteId = leadId since notes are a scalar field
     * on the lead record, not a separate entity). Wired for future note-list
     * support when a dedicated lead-notes endpoint is added.
     */
    data class NoteAdded(
        val noteId: Long,
        val body: String,
    ) : LeadEdit()
}

data class LeadDetailUiState(
    val lead: LeadEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    /** Signals that "lost" status was selected but the lost-reason dialog hasn't been confirmed yet. */
    val pendingLostTransition: Boolean = false,
    /** Non-null when convertToCustomer succeeds; screen navigates to the new customer. */
    val convertedCustomerId: Long? = null,
    /** Non-null when convertToEstimate succeeds; screen navigates to the estimate. */
    val convertedEstimateId: Long? = null,
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
    private val leadApi: LeadApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val leadId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(LeadDetailUiState())
    val state = _state.asStateFlow()

    /** Emits true when the conversion succeeds; LeadDetailScreen observes to navigate. */
    private val _convertedTicketId = MutableStateFlow<Long?>(null)
    val convertedTicketId = _convertedTicketId.asStateFlow()

    val isOnline get() = serverMonitor.isEffectivelyOnline

    // -----------------------------------------------------------------------
    // Undo / redo (§1 L232 — lead field edit, stage change, status change, note add)
    // -----------------------------------------------------------------------

    /** Undo stack scoped to this ViewModel instance; cleared on nav dismiss. */
    val undoStack = UndoStack<LeadEdit>()

    /**
     * Convenience alias so the screen can gate an Undo Snackbar action without
     * importing [UndoStack] — delegates directly to [undoStack.canUndo].
     */
    val canUndo: StateFlow<Boolean> = undoStack.canUndo

    init {
        collectLead()
        observeUndoEvents()
    }

    /**
     * Collects [UndoStack.events] and forwards [UndoStack.UndoEvent.Undone] /
     * [UndoStack.UndoEvent.Redone] / [UndoStack.UndoEvent.Failed] audit descriptions
     * to Timber tag "LeadUndo". The screen handles Pushed/Failed UI Snackbar events
     * directly via its own LaunchedEffect so no snackbar logic lives here.
     */
    private fun observeUndoEvents() {
        viewModelScope.launch {
            undoStack.events.collect { event ->
                when (event) {
                    is UndoStack.UndoEvent.Undone ->
                        Timber.tag("LeadUndo").i("Undone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Redone ->
                        Timber.tag("LeadUndo").i("Redone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Failed ->
                        Timber.tag("LeadUndo").w("Undo failed: ${event.reason}")
                    is UndoStack.UndoEvent.Pushed -> { /* handled by screen */ }
                }
            }
        }
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

        val oldStatus = lead.status

        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                leadRepository.updateLead(
                    leadId,
                    UpdateLeadRequest(status = newStatus),
                )
                // Note: no separate "Status updated" actionMessage — the UndoStack.Pushed
                // event shows "Edit saved / Undo" Snackbar immediately after push(),
                // which serves as the confirmation. Avoiding double-snackbar.
                _state.value = _state.value.copy(isActionInProgress = false)

                // Push undo entry: StatusChange covers the lead status/stage concept.
                val payload = LeadEdit.StatusChange(
                    oldStatus = oldStatus,
                    newStatus = newStatus,
                )
                undoStack.push(
                    UndoStack.Entry(
                        payload = payload,
                        apply = {
                            viewModelScope.launch {
                                leadRepository.updateLead(
                                    leadId,
                                    UpdateLeadRequest(status = newStatus),
                                )
                            }
                        },
                        reverse = {
                            if (oldStatus != null) {
                                viewModelScope.launch {
                                    leadRepository.updateLead(
                                        leadId,
                                        UpdateLeadRequest(status = oldStatus),
                                    )
                                }
                            }
                        },
                        auditDescription = "Status changed: ${oldStatus ?: "(none)"} → $newStatus",
                        compensatingSync = {
                            if (oldStatus == null) {
                                // Cannot revert to unknown prior status
                                false
                            } else {
                                try {
                                    leadRepository.updateLead(
                                        leadId,
                                        UpdateLeadRequest(status = oldStatus),
                                    )
                                    true
                                } catch (e: Exception) {
                                    Timber.tag("LeadUndo").e(e, "compensatingSync: status revert failed")
                                    false
                                }
                            }
                        },
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to update status: ${e.message}",
                )
            }
        }
    }

    /**
     * Updates a scalar text field on the lead (e.g. notes, source, referredBy).
     * Pushes a [LeadEdit.FieldEdit] undo entry after a successful API call.
     */
    fun updateField(fieldName: String, oldValue: String?, newValue: String?) {
        if (oldValue == newValue) return
        val request = buildSingleFieldRequest(fieldName, newValue)
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                leadRepository.updateLead(leadId, request)
                _state.value = _state.value.copy(isActionInProgress = false)

                val payload = LeadEdit.FieldEdit(
                    fieldName = fieldName,
                    oldValue = oldValue,
                    newValue = newValue,
                )
                undoStack.push(
                    UndoStack.Entry(
                        payload = payload,
                        apply = {
                            viewModelScope.launch {
                                leadRepository.updateLead(leadId, buildSingleFieldRequest(fieldName, newValue))
                            }
                        },
                        reverse = {
                            viewModelScope.launch {
                                leadRepository.updateLead(leadId, buildSingleFieldRequest(fieldName, oldValue))
                            }
                        },
                        auditDescription = "Edited $fieldName from ${oldValue ?: "(empty)"} to ${newValue ?: "(empty)"}",
                        compensatingSync = {
                            try {
                                leadRepository.updateLead(leadId, buildSingleFieldRequest(fieldName, oldValue))
                                true
                            } catch (e: Exception) {
                                Timber.tag("LeadUndo").e(e, "compensatingSync: $fieldName revert failed")
                                false
                            }
                        },
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to update $fieldName: ${e.message}",
                )
            }
        }
    }

    /**
     * Updates the lead stage (an alias for status in the lead domain).
     * Pushes a [LeadEdit.StageChange] undo entry after a successful API call.
     */
    fun updateStage(newStage: String) {
        val lead = _state.value.lead ?: return
        if (lead.status.equals(newStage, ignoreCase = true)) return

        val oldStage = lead.status

        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                leadRepository.updateLead(
                    leadId,
                    UpdateLeadRequest(status = newStage),
                )
                _state.value = _state.value.copy(isActionInProgress = false)

                val payload = LeadEdit.StageChange(
                    oldStage = oldStage,
                    newStage = newStage,
                )
                undoStack.push(
                    UndoStack.Entry(
                        payload = payload,
                        apply = {
                            viewModelScope.launch {
                                leadRepository.updateLead(
                                    leadId,
                                    UpdateLeadRequest(status = newStage),
                                )
                            }
                        },
                        reverse = {
                            if (oldStage != null) {
                                viewModelScope.launch {
                                    leadRepository.updateLead(
                                        leadId,
                                        UpdateLeadRequest(status = oldStage),
                                    )
                                }
                            }
                        },
                        auditDescription = "Stage changed: ${oldStage ?: "(none)"} → $newStage",
                        compensatingSync = {
                            if (oldStage == null) {
                                false
                            } else {
                                try {
                                    leadRepository.updateLead(
                                        leadId,
                                        UpdateLeadRequest(status = oldStage),
                                    )
                                    true
                                } catch (e: Exception) {
                                    Timber.tag("LeadUndo").e(e, "compensatingSync: stage revert failed")
                                    false
                                }
                            }
                        },
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to update stage: ${e.message}",
                )
            }
        }
    }

    /**
     * Persists a note for this lead by updating the scalar [notes] field on the
     * lead record. Pushes a [LeadEdit.NoteAdded] undo entry after success.
     *
     * compensatingSync returns false because [LeadApi.deleteNote] does not exist —
     * notes are a scalar field (not a note-list endpoint). Same B19 pattern as
     * CustomerDetail until a dedicated lead-notes endpoint is added.
     *
     * TODO: wire real DELETE /leads/:id/notes/:noteId when the lead-notes endpoint
     * is added in a follow-up wave.
     */
    fun postNote(body: String) {
        val trimmed = body.trim()
        if (trimmed.isBlank()) return
        val lead = _state.value.lead ?: return
        val oldNotes = lead.notes

        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                leadRepository.updateLead(
                    leadId,
                    UpdateLeadRequest(notes = trimmed),
                )
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Note saved",
                )

                // noteId == leadId because notes are scalar on the lead record.
                val payload = LeadEdit.NoteAdded(noteId = leadId, body = trimmed)
                undoStack.push(
                    UndoStack.Entry(
                        payload = payload,
                        apply = {
                            viewModelScope.launch {
                                leadRepository.updateLead(leadId, UpdateLeadRequest(notes = trimmed))
                            }
                        },
                        reverse = {
                            viewModelScope.launch {
                                leadRepository.updateLead(leadId, UpdateLeadRequest(notes = oldNotes))
                            }
                        },
                        auditDescription = "Note added: \"${trimmed.take(60)}${if (trimmed.length > 60) "…" else ""}\"",
                        compensatingSync = {
                            // LeadApi.deleteNote does not exist — notes are a scalar field.
                            // Signal failure so UndoStack emits UndoEvent.Failed and the UI
                            // shows "Can't undo — action already processed".
                            Timber.tag("LeadUndo").w(
                                "compensatingSync: LeadApi.deleteNote not available (scalar notes field); leadId=$leadId"
                            )
                            false
                        },
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to save note: ${e.message}",
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

    /**
     * Request "lost" status transition. Emits [pendingLostTransition] = true so the
     * screen shows [LostReasonDialog]. Call [confirmLostWithReason] once the user picks.
     */
    fun requestLostTransition() {
        _state.value = _state.value.copy(pendingLostTransition = true)
    }

    fun cancelLostTransition() {
        _state.value = _state.value.copy(pendingLostTransition = false)
    }

    /** Called from [LostReasonDialog] after the user picks a reason. */
    fun confirmLostWithReason(reason: String) {
        _state.value = _state.value.copy(pendingLostTransition = false)
        val old = _state.value.lead?.status
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                leadRepository.updateLead(
                    leadId,
                    UpdateLeadRequest(status = "lost", lostReason = reason),
                )
                _state.value = _state.value.copy(isActionInProgress = false)
                undoStack.push(
                    UndoStack.Entry(
                        payload = LeadEdit.StatusChange(oldStatus = old, newStatus = "lost"),
                        apply = { viewModelScope.launch { leadRepository.updateLead(leadId, UpdateLeadRequest(status = "lost", lostReason = reason)) } },
                        reverse = {
                            if (old != null) viewModelScope.launch {
                                leadRepository.updateLead(leadId, UpdateLeadRequest(status = old))
                            }
                        },
                        auditDescription = "Marked lost: $reason",
                        compensatingSync = {
                            try {
                                if (old != null) leadRepository.updateLead(leadId, UpdateLeadRequest(status = old))
                                true
                            } catch (e: Exception) { Timber.tag("LeadUndo").e(e, "compensatingSync: lost revert"); false }
                        },
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to mark as lost: ${e.message}",
                )
            }
        }
    }

    /**
     * Convert lead to customer (ActionPlan §9 L1399).
     * 404-tolerant: shows a toast if the endpoint is not yet deployed.
     */
    fun convertToCustomer() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val response = leadApi.convertToCustomer(leadId)
                val customerId = (response.data?.get("customerId") as? Number)?.toLong()
                if (customerId != null) {
                    refreshLeadInBackground()
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        convertedCustomerId = customerId,
                        actionMessage = "Lead converted to customer",
                    )
                } else {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Convert returned no customer id",
                    )
                }
            } catch (e: retrofit2.HttpException) {
                val msg = if (e.code() == 404) "Convert to customer not yet available on this server"
                          else "Failed to convert: ${e.message}"
                _state.value = _state.value.copy(isActionInProgress = false, actionMessage = msg)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to convert to customer: ${e.message}",
                )
            }
        }
    }

    /**
     * Convert lead to estimate (ActionPlan §9 L1400).
     * 404-tolerant.
     */
    fun convertToEstimate() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val response = leadApi.convertToEstimate(leadId)
                val estimateId = (response.data?.get("estimateId") as? Number)?.toLong()
                if (estimateId != null) {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        convertedEstimateId = estimateId,
                        actionMessage = "Lead converted to estimate",
                    )
                } else {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Convert returned no estimate id",
                    )
                }
            } catch (e: retrofit2.HttpException) {
                val msg = if (e.code() == 404) "Convert to estimate not yet available on this server"
                          else "Failed to convert: ${e.message}"
                _state.value = _state.value.copy(isActionInProgress = false, actionMessage = msg)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to convert to estimate: ${e.message}",
                )
            }
        }
    }

    private fun refreshLeadInBackground() {
        viewModelScope.launch {
            try {
                val response = leadApi.getLead(leadId)
                // toEntity is defined in LeadRepository file
                response.data?.let { }
            } catch (_: Exception) { }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    fun clearConvertedCustomerId() {
        _state.value = _state.value.copy(convertedCustomerId = null)
    }

    fun clearConvertedEstimateId() {
        _state.value = _state.value.copy(convertedEstimateId = null)
    }

    /**
     * Build a minimal [UpdateLeadRequest] carrying only [fieldName] = [value].
     * All other fields are null so the server performs a partial update without
     * overwriting unrelated columns.
     */
    private fun buildSingleFieldRequest(fieldName: String, value: String?): UpdateLeadRequest =
        when (fieldName) {
            "firstName"  -> UpdateLeadRequest(firstName = value)
            "lastName"   -> UpdateLeadRequest(lastName = value)
            "email"      -> UpdateLeadRequest(email = value)
            "phone"      -> UpdateLeadRequest(phone = value)
            "address"    -> UpdateLeadRequest(address = value)
            "zipCode"    -> UpdateLeadRequest(zipCode = value)
            "source"     -> UpdateLeadRequest(source = value)
            "referredBy" -> UpdateLeadRequest(referredBy = value)
            "notes"      -> UpdateLeadRequest(notes = value)
            "lostReason" -> UpdateLeadRequest(lostReason = value)
            else         -> UpdateLeadRequest()
        }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeadDetailScreen(
    leadId: Long,
    onBack: () -> Unit,
    onConverted: (ticketId: Long) -> Unit,
    onConvertedToCustomer: (customerId: Long) -> Unit = {},
    onConvertedToEstimate: (estimateId: Long) -> Unit = {},
    onScheduleAppointment: (leadId: Long) -> Unit = {},
    viewModel: LeadDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val convertedTicketId by viewModel.convertedTicketId.collectAsState()
    val isOnline by viewModel.isOnline.collectAsState()
    val lead = state.lead

    var showStatusDropdown by remember { mutableStateOf(false) }
    var showDeleteConfirm by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // Navigate when ticket conversion succeeds
    LaunchedEffect(convertedTicketId) {
        val ticketId = convertedTicketId
        if (ticketId != null) onConverted(ticketId)
    }

    // Navigate when customer conversion succeeds
    LaunchedEffect(state.convertedCustomerId) {
        val customerId = state.convertedCustomerId
        if (customerId != null) {
            viewModel.clearConvertedCustomerId()
            onConvertedToCustomer(customerId)
        }
    }

    // Navigate when estimate conversion succeeds
    LaunchedEffect(state.convertedEstimateId) {
        val estimateId = state.convertedEstimateId
        if (estimateId != null) {
            viewModel.clearConvertedEstimateId()
            onConvertedToEstimate(estimateId)
        }
    }

    // Lost-reason dialog — show when status dropdown selects "lost"
    if (state.pendingLostTransition) {
        LostReasonDialog(
            onConfirm = { reason -> viewModel.confirmLostWithReason(reason) },
            onDismiss = { viewModel.cancelLostTransition() },
        )
    }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    // -----------------------------------------------------------------------
    // Undo stack UI (§1 L232)
    // -----------------------------------------------------------------------

    // Collect UndoStack events: show "Edit saved / Undo" Snackbar on Pushed,
    // plain toast on Failed. Undone/Redone are audit-only (logged in ViewModel).
    LaunchedEffect(viewModel.undoStack) {
        viewModel.undoStack.events.collect { event ->
            when (event) {
                is UndoStack.UndoEvent.Pushed -> {
                    val result = snackbarHostState.showSnackbar(
                        message = "Edit saved",
                        actionLabel = "Undo",
                        duration = SnackbarDuration.Short,
                    )
                    if (result == SnackbarResult.ActionPerformed) {
                        scope.launch { viewModel.undoStack.undo() }
                    }
                }
                is UndoStack.UndoEvent.Failed ->
                    snackbarHostState.showSnackbar(event.reason)
                is UndoStack.UndoEvent.Undone -> { /* audit handled in ViewModel */ }
                is UndoStack.UndoEvent.Redone -> { /* audit handled in ViewModel */ }
            }
        }
    }

    // Clear undo history when the screen leaves composition so stale entries
    // don't survive a back-stack pop and re-push.
    DisposableEffect(Unit) {
        onDispose { viewModel.undoStack.clear() }
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
                    // Header: name + phone + email + score ring + status chip
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Row(
                                modifier = Modifier.padding(16.dp).fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                // Score ring — tappable for explanation sheet
                                LeadScoreIndicator(
                                    score = lead.leadScore,
                                    size = 64.dp,
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    val fullName = listOfNotNull(lead.firstName, lead.lastName)
                                        .joinToString(" ").ifBlank { "Unknown" }
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
                                    if (!lead.email.isNullOrBlank()) {
                                        Text(
                                            lead.email,
                                            style = MaterialTheme.typography.bodySmall,
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
                                    Spacer(modifier = Modifier.height(6.dp))
                                    val statusLabel = optionFor(lead.status)?.label ?: lead.status ?: ""
                                    if (statusLabel.isNotBlank()) {
                                        BrandStatusBadge(label = statusLabel, status = lead.status ?: "")
                                    }
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
                                                // decorative — parent Surface(onClick=...) merges descendants with the currentLabel Text; the surface is announced as the clickable status badge
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
                                                    if (option.key == "lost") {
                                                        viewModel.requestLostTransition()
                                                    } else {
                                                        viewModel.updateStatus(option.key)
                                                    }
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
                            // Convert to Ticket — primary action
                            BrandPrimaryButton(
                                onClick = { viewModel.convertToTicket() },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = isOnline &&
                                    !state.isActionInProgress &&
                                    !lead.status.equals("converted", ignoreCase = true),
                            ) {
                                Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(if (!isOnline) "Convert to Ticket (Offline)" else "Convert to Ticket")
                            }

                            // Convert to Customer
                            OutlinedButton(
                                onClick = { viewModel.convertToCustomer() },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = isOnline && !state.isActionInProgress,
                            ) {
                                Icon(Icons.Default.PersonAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Convert to Customer")
                            }

                            // Convert to Estimate
                            OutlinedButton(
                                onClick = { viewModel.convertToEstimate() },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = isOnline && !state.isActionInProgress,
                            ) {
                                Icon(Icons.Default.Description, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Convert to Estimate")
                            }

                            // Schedule Appointment
                            OutlinedButton(
                                onClick = { onScheduleAppointment(leadId) },
                                modifier = Modifier.fillMaxWidth(),
                                enabled = !state.isActionInProgress,
                            ) {
                                Icon(Icons.Default.CalendarMonth, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Schedule Appointment")
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
                                Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
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
            // decorative — non-clickable label-value row; sibling label + value Text carry the announcement
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
