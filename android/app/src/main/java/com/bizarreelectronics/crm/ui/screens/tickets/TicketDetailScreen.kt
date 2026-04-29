package com.bizarreelectronics.crm.ui.screens.tickets

import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import com.bizarreelectronics.crm.data.remote.dto.DeviceHistoryEntry
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.WarrantyResult
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
import com.bizarreelectronics.crm.ui.screens.tickets.components.BenchTimerCard
import com.bizarreelectronics.crm.ui.screens.tickets.components.ConcurrentEditBanner
import com.bizarreelectronics.crm.ui.screens.tickets.components.DeletedBanner
import com.bizarreelectronics.crm.ui.screens.tickets.components.DeviceHistorySheet
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketDetailHeaderRow
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketDetailTabs
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketPhotoGallery
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketPrintActions
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketQrCard
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketRelatedRail
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketWarrantyDialog
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.util.ClipboardUtil
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.ReduceMotion
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import dagger.hilt.android.lifecycle.HiltViewModel
import com.bizarreelectronics.crm.data.remote.api.WaiverApi
import com.bizarreelectronics.crm.util.UndoStack
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.HttpException
import com.bizarreelectronics.crm.ui.screens.tickets.components.QcSignOffDialog
import com.bizarreelectronics.crm.ui.screens.tickets.components.RollbackStatusDialog
import com.bizarreelectronics.crm.ui.screens.tickets.components.StatusNotifyPreviewDialog
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketStatePill
import com.bizarreelectronics.crm.util.MultipartUpload
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Domain type for ticket undo entries (§1 L232)
// ---------------------------------------------------------------------------

/**
 * Sealed payload type covering all reversible ticket mutations wired to
 * [UndoStack] in [TicketDetailViewModel]. Immutable data classes only.
 */
sealed class TicketEdit {
    /** A generic scalar field update (e.g. assignedTo, discount). */
    data class FieldEdit(
        val fieldName: String,
        val oldValue: String?,
        val newValue: String?,
    ) : TicketEdit()

    /** Status change — carries both status ids and display names for audit descriptions. */
    data class StatusChange(
        val oldStatusId: Long?,
        val newStatusId: Long,
        val oldStatusName: String?,
        val newStatusName: String?,
    ) : TicketEdit()

    /** A note that was added online (noteId is the server-assigned id). */
    data class NoteAdded(
        val noteId: Long,
        val noteText: String,
    ) : TicketEdit()
}

/** Strip HTML tags from server-generated descriptions */
private fun stripHtml(html: String?): String {
    if (html.isNullOrBlank()) return ""
    return html.replace(Regex("<[^>]*>"), "").trim()
}

/**
 * Captures a status-change request that is waiting for the notify-preview
 * dialog decision (L742). Held in [TicketDetailUiState.pendingStatusChange]
 * until the user taps Send / Skip / Cancel.
 */
data class PendingStatusChange(
    val newStatusId: Long,
    val notifications: List<com.bizarreelectronics.crm.ui.screens.tickets.components.NotificationSpec>,
)

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
    /** L678 — bench timer running state. */
    val isBenchTimerRunning: Boolean = false,
    /** L680 — true when a background refresh returns 404 (ticket deleted while viewing). */
    val isDeletedWhileViewing: Boolean = false,
    /** L681 — current user role from [AuthPreferences.userRole] for permission gating. */
    val userRole: String? = null,
    // ─── L725 — Warranty ─────────────────────────────────────────────────────
    val showWarrantyDialog: Boolean = false,
    val warrantyLoading: Boolean = false,
    val warrantyResult: com.bizarreelectronics.crm.data.remote.dto.WarrantyResult? = null,
    val warrantyError: String? = null,
    // ─── L726 — Device history ────────────────────────────────────────────────
    val showDeviceHistory: Boolean = false,
    val deviceHistoryLoading: Boolean = false,
    val deviceHistoryEntries: List<com.bizarreelectronics.crm.data.remote.dto.DeviceHistoryEntry> = emptyList(),
    val deviceHistoryError: String? = null,
    // ─── L731 — Employees for @mention ───────────────────────────────────────
    val employees: List<com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem> = emptyList(),
    // ─── L740 — Transition guard inline errors ────────────────────────────────
    val statusTransitionError: String? = null,
    // ─── L741 — QC sign-off ──────────────────────────────────────────────────
    val showQcSignOffDialog: Boolean = false,
    // ─── L742 — Status notify preview ────────────────────────────────────────
    /** Non-null while the status-notify preview dialog is open. */
    val pendingStatusChange: PendingStatusChange? = null,
    // ─── plan:L793 — Rollback status (admin-only) ────────────────────────────
    /** True when the admin-only "Rollback status" dialog is visible. */
    val showRollbackDialog: Boolean = false,
    // ─── L780-L786 — Waivers ─────────────────────────────────────────────────
    /**
     * True when the server confirmed the waiver feature is enabled for this ticket.
     * Determined by probing `GET /tickets/:id/waivers/required` — 404 → false.
     * The "Waivers" overflow action is hidden when false.
     */
    val waiverFeatureEnabled: Boolean = false,
    /** True while the waiver availability check is in-flight. */
    val waiverCheckInProgress: Boolean = false,
    // ─── §4.13 L777 — Concurrent-edit banner (409) ───────────────────────────
    /**
     * True when the server returned HTTP 409 (stale `updated_at`). Drives
     * [ConcurrentEditBanner] — user must tap Reload to re-fetch and merge.
     * Cleared by [TicketDetailViewModel.clearConcurrentEdit] on successful reload.
     */
    val isConcurrentEdit: Boolean = false,
    // ─── §4.13 L776 — Permission-denied ephemeral message ────────────────────
    /**
     * Non-null when a role-gated action was attempted without sufficient privileges.
     * Shown as a one-shot Snackbar; consumed by the UI then cleared via
     * [TicketDetailViewModel.clearPermissionDenied].
     */
    val permissionDeniedMessage: String? = null,
    // ─── §4.22 — Notify customer of delay ────────────────────────────────────
    /**
     * True when the "Notify customer of delay" dialog is open from the overflow
     * menu. The dialog pre-fills a delay template and calls [TicketDetailViewModel.sendDelayNotificationSms]
     * on confirm.
     */
    val showNotifyDelayDialog: Boolean = false,
    /** Non-null while the delay SMS is being sent; drives a progress indicator in the dialog. */
    val isDelaySendInProgress: Boolean = false,
)

@HiltViewModel
class TicketDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val ticketRepository: TicketRepository,
    private val ticketApi: TicketApi,
    private val settingsApi: SettingsApi,
    private val authPreferences: com.bizarreelectronics.crm.data.local.prefs.AuthPreferences,
    private val appPreferences: com.bizarreelectronics.crm.data.local.prefs.AppPreferences,
    private val syncQueueDao: com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao,
    private val serverMonitor: com.bizarreelectronics.crm.util.ServerReachabilityMonitor,
    private val gson: com.google.gson.Gson,
    private val multipartUpload: MultipartUpload,
    private val smsApi: com.bizarreelectronics.crm.data.remote.api.SmsApi,
    private val waiverApi: WaiverApi,
) : ViewModel() {

    private val ticketId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L
    val serverUrl: String get() = authPreferences.serverUrl ?: ""

    // -----------------------------------------------------------------------
    // Undo / redo (§1 L232 — ticket field edit, status change, notes add)
    // -----------------------------------------------------------------------

    /** Undo stack scoped to this ViewModel instance; cleared on nav dismiss. */
    val undoStack = UndoStack<TicketEdit>()

    /**
     * Convenience alias so the screen can gate an Undo Snackbar action without
     * importing [UndoStack] — delegates directly to [undoStack.canUndo].
     */
    val canUndo: StateFlow<Boolean> = undoStack.canUndo

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
        loadEmployees()
        captureRoleInState()
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
                // L680 — detect 404: ticket was deleted while this screen was open
                val is404 = runCatching {
                    (e as? retrofit2.HttpException)?.code() == 404
                }.getOrDefault(false)
                if (is404) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isDeletedWhileViewing = true,
                    )
                    return@launch
                }
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
        val oldStatusId = ticket.statusId
        val oldStatusName = ticket.statusName
        val targetStatus = _state.value.statuses.find { it.id == newStatusId }
        val newStatusName = targetStatus?.name

        // L740 — Client-side transition guard check
        val requirements = targetStatus?.transitionRequirements ?: emptyList()
        val violations = mutableListOf<String>()
        if ("note_added" in requirements && _state.value.notes.isEmpty()) {
            violations += "A note must be added before moving to \"$newStatusName\""
        }
        if ("photos_taken" in requirements && _state.value.photos.isEmpty()) {
            violations += "At least one photo must be attached before moving to \"$newStatusName\""
        }
        if (violations.isNotEmpty()) {
            _state.value = _state.value.copy(statusTransitionError = violations.joinToString("; "))
            return
        }
        _state.value = _state.value.copy(statusTransitionError = null)

        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = UpdateTicketRequest(
                    statusId = newStatusId,
                    updatedAt = ticket.updatedAt,
                )
                ticketRepository.updateTicket(ticketId, request)
                // Note: no separate "Status updated" actionMessage here — the UndoStack.Pushed
                // event will show "Edit saved / Undo" Snackbar immediately after push(), which
                // serves as the confirmation. Avoiding double-snackbar.
                _state.value = _state.value.copy(isActionInProgress = false)

                // Push undo entry after optimistic update succeeds (or is queued offline).
                // apply = re-apply the new status; reverse = restore the old status.
                val payload = TicketEdit.StatusChange(
                    oldStatusId = oldStatusId,
                    newStatusId = newStatusId,
                    oldStatusName = oldStatusName,
                    newStatusName = newStatusName,
                )
                undoStack.push(
                    UndoStack.Entry(
                        payload = payload,
                        apply = {
                            viewModelScope.launch {
                                ticketRepository.updateTicket(
                                    ticketId,
                                    UpdateTicketRequest(statusId = newStatusId),
                                )
                            }
                        },
                        reverse = {
                            if (oldStatusId != null) {
                                viewModelScope.launch {
                                    ticketRepository.updateTicket(
                                        ticketId,
                                        UpdateTicketRequest(statusId = oldStatusId),
                                    )
                                }
                            }
                        },
                        auditDescription = "Status changed: ${oldStatusName ?: oldStatusId} → ${newStatusName ?: newStatusId}",
                        compensatingSync = {
                            if (oldStatusId == null) {
                                false // Cannot revert to unknown prior status
                            } else {
                                try {
                                    ticketRepository.updateTicket(
                                        ticketId,
                                        UpdateTicketRequest(statusId = oldStatusId),
                                    )
                                    true
                                } catch (e: Exception) {
                                    Timber.tag("TicketUndo").e(e, "compensatingSync: status revert failed")
                                    false
                                }
                            }
                        },
                    )
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
                    val response = ticketApi.addNote(ticketId, mapOf("type" to "internal", "content" to text))
                    val noteId = response.data?.id ?: -1L
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Note added",
                    )
                    loadTicketDetail()

                    // Push undo entry — compensatingSync deletes the note server-side via
                    // TicketApi.deleteNote (DELETE /tickets/notes/:noteId). noteId is
                    // captured from the server response above; negative means offline-queued.
                    val payload = TicketEdit.NoteAdded(noteId = noteId, noteText = text)
                    undoStack.push(
                        UndoStack.Entry(
                            payload = payload,
                            apply = {
                                // Re-add: just reload — no local note list mutation needed
                                viewModelScope.launch { loadTicketDetail() }
                            },
                            reverse = {
                                // Remove from local notes list optimistically
                                _state.value = _state.value.copy(
                                    notes = _state.value.notes.filter { it.id != noteId },
                                )
                            },
                            auditDescription = "Note added: \"${text.take(60)}${if (text.length > 60) "…" else ""}\"",
                            compensatingSync = compensatingSyncForNote@{
                                if (noteId < 0L) {
                                    // Note was offline-queued; no server row to delete yet
                                    Timber.tag("TicketUndo").w("compensatingSync: note was offline-queued, cannot server-delete")
                                    false
                                } else {
                                    try {
                                        val resp = ticketApi.deleteNote(noteId)
                                        resp.success
                                    } catch (e: Exception) {
                                        Timber.tag("TicketUndo").w(e, "compensatingSync: server delete of noteId=$noteId failed")
                                        false
                                    }
                                }
                            },
                        )
                    )
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

    fun clearStatusTransitionError() {
        _state.value = _state.value.copy(statusTransitionError = null)
    }

    // -----------------------------------------------------------------------
    // L731 — Employees for @mention
    // -----------------------------------------------------------------------

    private fun loadEmployees() {
        viewModelScope.launch {
            try {
                val response = settingsApi.getEmployees()
                val list = response.data ?: emptyList()
                _state.value = _state.value.copy(employees = list)
            } catch (_: Exception) {
                // Non-critical — mentions will have no suggestions
            }
        }
    }

    // -----------------------------------------------------------------------
    // L725 — Warranty lookup
    // -----------------------------------------------------------------------

    fun showWarrantyDialog() {
        _state.value = _state.value.copy(
            showWarrantyDialog = true,
            warrantyResult = null,
            warrantyError = null,
        )
    }

    fun dismissWarrantyDialog() {
        _state.value = _state.value.copy(showWarrantyDialog = false)
    }

    fun lookupWarranty(query: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(warrantyLoading = true, warrantyError = null, warrantyResult = null)
            try {
                // Server lookup accepts imei/serial/phone as named query args.
                // Caller's `query` is opaque — try imei (most common), fall back
                // to serial if no result. Take the first match (server returns list).
                val response = ticketApi.warrantyLookup(imei = query)
                val first = response.data?.firstOrNull()
                _state.value = if (first != null) {
                    _state.value.copy(warrantyLoading = false, warrantyResult = first)
                } else {
                    _state.value.copy(warrantyLoading = false, warrantyError = "No warranty record found.")
                }
            } catch (e: Exception) {
                val is404 = runCatching { (e as? retrofit2.HttpException)?.code() == 404 }.getOrDefault(false)
                _state.value = _state.value.copy(
                    warrantyLoading = false,
                    warrantyError = if (is404) "No warranty record found." else "Lookup failed: ${e.message}",
                )
            }
        }
    }

    // -----------------------------------------------------------------------
    // L726 — Device history
    // -----------------------------------------------------------------------

    fun showDeviceHistory() {
        _state.value = _state.value.copy(
            showDeviceHistory = true,
            deviceHistoryEntries = emptyList(),
            deviceHistoryError = null,
        )
        // Resolve identifier from first device
        val device = _state.value.devices.firstOrNull()
        val imei = device?.imei
        val serial = device?.serial
        if (imei.isNullOrBlank() && serial.isNullOrBlank()) {
            _state.value = _state.value.copy(
                deviceHistoryLoading = false,
                deviceHistoryError = "No IMEI or serial number on this device.",
            )
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(deviceHistoryLoading = true)
            try {
                val response = ticketApi.getDeviceHistory(imei = imei?.ifBlank { null }, serial = serial?.ifBlank { null })
                val entries = response.data ?: emptyList()
                _state.value = _state.value.copy(
                    deviceHistoryLoading = false,
                    deviceHistoryEntries = entries,
                    deviceHistoryError = if (entries.isEmpty()) "No prior repairs found for this device." else null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    deviceHistoryLoading = false,
                    deviceHistoryError = "Failed to load device history: ${e.message}",
                )
            }
        }
    }

    fun dismissDeviceHistory() {
        _state.value = _state.value.copy(showDeviceHistory = false)
    }

    // -----------------------------------------------------------------------
    // L727 — Pin to dashboard
    // -----------------------------------------------------------------------

    /**
     * Pin this ticket to the Dashboard "Pinned" row. Server call is opportunistic;
     * local [AppPreferences.pinnedTicketIds] is always updated so the pin persists
     * offline (matching the existing pattern from plan:L653).
     */
    fun pinToDashboard() {
        appPreferences.addPinnedTicketId(ticketId)
        _state.value = _state.value.copy(actionMessage = "Ticket pinned to dashboard")
        viewModelScope.launch {
            try {
                ticketApi.pinToDashboard(ticketId)
            } catch (e: Exception) {
                // 404 tolerated — pin is kept locally
                Timber.tag("PinDashboard").w(e, "pinToDashboard: server returned error (local-only fallback)")
            }
        }
    }

    // -----------------------------------------------------------------------
    // L678 — Bench timer
    // -----------------------------------------------------------------------

    /**
     * Start a bench timer session for this ticket. Stub fallback on 404 so the
     * UI timer still runs locally if the server doesn't expose the endpoint.
     */
    fun startBenchTimer() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isBenchTimerRunning = true)
            try {
                ticketApi.startBenchTimer(ticketId)
            } catch (e: Exception) {
                // Stub fallback — timer runs locally even if server returns 404
                Timber.tag("BenchTimer").w(e, "startBenchTimer: server returned error (stub fallback active)")
            }
        }
    }

    /**
     * Stop the active bench timer session for this ticket.
     */
    fun stopBenchTimer() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isBenchTimerRunning = false)
            try {
                ticketApi.stopBenchTimer(ticketId)
            } catch (e: Exception) {
                Timber.tag("BenchTimer").w(e, "stopBenchTimer: server returned error (stub fallback active)")
            }
        }
    }

    // -----------------------------------------------------------------------
    // L669 — Photo delete
    // -----------------------------------------------------------------------

    /**
     * Remove a photo by server ID, updating local state immediately.
     * Stub fallback on 404 (e.g. already deleted on another device).
     */
    fun deletePhoto(photoId: Long) {
        _state.value = _state.value.copy(
            photos = _state.value.photos.filter { it.id != photoId },
        )
        viewModelScope.launch {
            try {
                ticketApi.deletePhoto(photoId)
            } catch (e: Exception) {
                Timber.tag("TicketPhoto").w(e, "deletePhoto id=%d: server error (already removed?)", photoId)
            }
        }
    }

    // -----------------------------------------------------------------------
    // L681 — Role gate
    // -----------------------------------------------------------------------

    /**
     * Returns true when [authPreferences.userRole] is one of the privileged
     * roles that may perform destructive ticket actions (Delete, Void).
     * Defaults to false when role is unknown (fail-safe).
     */
    val isPrivilegedRole: Boolean
        get() = authPreferences.userRole?.lowercase()?.let { role ->
            role == "admin" || role == "owner" || role == "manager"
        } ?: false

    // -----------------------------------------------------------------------
    // Expose userRole for UI state snapshot
    // -----------------------------------------------------------------------

    private fun captureRoleInState() {
        _state.value = _state.value.copy(userRole = authPreferences.userRole)
    }

    // -----------------------------------------------------------------------
    // L780-L786 — Waiver feature availability probe
    // -----------------------------------------------------------------------

    /**
     * Probe `GET /tickets/:id/waivers/required` to determine whether the waiver
     * feature is enabled on the connected server. Called once after [loadTicketDetail]
     * succeeds. 404 → hides the Waivers overflow action (no crash, no error snackbar).
     */
    fun probeWaiverFeature() {
        _state.value = _state.value.copy(waiverCheckInProgress = true)
        viewModelScope.launch {
            try {
                waiverApi.getRequiredTemplates(ticketId)
                _state.value = _state.value.copy(waiverFeatureEnabled = true, waiverCheckInProgress = false)
            } catch (e: HttpException) {
                // 404 = feature not available — hide the action silently
                _state.value = _state.value.copy(waiverFeatureEnabled = false, waiverCheckInProgress = false)
            } catch (e: Exception) {
                // Network error treated the same as not-available for safety
                _state.value = _state.value.copy(waiverFeatureEnabled = false, waiverCheckInProgress = false)
            }
        }
    }

    // -----------------------------------------------------------------------
    // L741 — QC sign-off
    // -----------------------------------------------------------------------

    fun showQcSignOff() {
        _state.value = _state.value.copy(showQcSignOffDialog = true)
    }

    fun dismissQcSignOff() {
        _state.value = _state.value.copy(showQcSignOffDialog = false)
    }

    /**
     * Submit QC sign-off. Attempts `POST /tickets/:id/qc-sign` with the
     * signature PNG as multipart. On 404, falls back to attaching the
     * signature as a photo attachment with tag "signature" via
     * [MultipartUpload], and adds a note with "QC sign-off" flag.
     *
     * @param signatureBitmap  PNG rendered from [SignatureState.capture].
     * @param comments         Optional technician comment.
     * @param multipartUpload  WorkManager upload helper.
     * @param cacheDir         App cache dir for temp file.
     */
    fun submitQcSignOff(
        signatureBitmap: android.graphics.Bitmap,
        comments: String,
        cacheDir: java.io.File,
    ) {
        _state.value = _state.value.copy(showQcSignOffDialog = false, isActionInProgress = true)
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            // Persist bitmap to cache
            val key = java.util.UUID.randomUUID().toString()
            val sigFile = java.io.File(cacheDir, "qc_sig_${key.take(8)}.png")
            try {
                sigFile.outputStream().use { out ->
                    signatureBitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                }

                val pngMediaType = "image/png".toMediaType()
                val textMediaType = "text/plain".toMediaType()
                val sigPart = okhttp3.MultipartBody.Part.createFormData(
                    "signature",
                    sigFile.name,
                    sigFile.asRequestBody(pngMediaType),
                )
                val commentsPart = comments.toRequestBody(textMediaType)

                try {
                    ticketApi.qcSignOff(ticketId, sigPart, commentsPart)
                    withStateOnMain { copy(isActionInProgress = false, actionMessage = "QC sign-off recorded") }
                } catch (e: Exception) {
                    val is404 = runCatching { (e as? retrofit2.HttpException)?.code() == 404 }.getOrDefault(false)
                    if (is404) {
                        // Fallback: attach signature as photo + note
                        multipartUpload.enqueue(
                            localPath = sigFile.absolutePath,
                            targetUrl = "/api/v1/tickets/$ticketId/photos",
                            fields = mapOf(
                                "type" to "signature",
                                "ticket_device_id" to (_state.value.devices.firstOrNull()?.id?.toString() ?: "0"),
                            ),
                            idempotencyKey = key,
                            contentType = "image/png",
                        )
                        // Add note with QC flag
                        val noteText = buildString {
                            append("QC sign-off")
                            if (comments.isNotBlank()) append(": $comments")
                        }
                        try {
                            ticketApi.addNote(
                                ticketId,
                                mapOf("type" to "internal", "content" to noteText, "is_qc_sign_off" to true),
                            )
                        } catch (_: Exception) {}
                        withStateOnMain { copy(isActionInProgress = false, actionMessage = "QC sign-off saved (signature attached)") }
                    } else {
                        Timber.tag("QcSignOff").e(e, "qcSignOff failed")
                        withStateOnMain { copy(isActionInProgress = false, actionMessage = "QC sign-off failed: ${e.message}") }
                    }
                }
            } catch (e: Exception) {
                Timber.tag("QcSignOff").e(e, "bitmap save failed")
                withStateOnMain { copy(isActionInProgress = false, actionMessage = "Failed to save signature") }
            }
        }
    }

    // -----------------------------------------------------------------------
    // L742 — Status notify preview
    // -----------------------------------------------------------------------

    /**
     * Called instead of [changeStatus] when the target status has
     * [TicketStatusItem.notifyCustomer] == 1. Shows [StatusNotifyPreviewDialog]
     * with mock notification specs derived from the server status data.
     *
     * Real notification specs arrive via an extended status payload
     * (`StatusDto.notifications`). Until the server exposes that field,
     * we synthesise a placeholder spec so the UI flow is exercised.
     */
    fun requestStatusChangeWithNotify(newStatusId: Long) {
        val targetStatus = _state.value.statuses.find { it.id == newStatusId }
        val shouldNotify = targetStatus?.notifyCustomer == 1
        if (!shouldNotify) {
            changeStatus(newStatusId)
            return
        }

        // Build a placeholder NotificationSpec so the dialog can preview
        val phone = _state.value.ticketDetail?.customer?.phone
            ?: _state.value.ticketDetail?.customer?.mobile
            ?: _state.value.ticket?.customerPhone
        val specs = buildList {
            if (!phone.isNullOrBlank()) {
                add(
                    com.bizarreelectronics.crm.ui.screens.tickets.components.NotificationSpec(
                        channel = "sms",
                        recipient = phone,
                        body = "Your repair status has been updated to \"${targetStatus?.name}\".",
                    )
                )
            }
        }

        _state.value = _state.value.copy(
            pendingStatusChange = PendingStatusChange(
                newStatusId = newStatusId,
                notifications = specs,
            ),
        )
    }

    fun confirmStatusChangeWithNotify(sendNotifications: Boolean) {
        val pending = _state.value.pendingStatusChange ?: return
        _state.value = _state.value.copy(pendingStatusChange = null)

        // Apply the status change
        changeStatus(pending.newStatusId)

        if (!sendNotifications) return

        // Fire notifications
        val phone = _state.value.ticketDetail?.customer?.phone
            ?: _state.value.ticketDetail?.customer?.mobile
            ?: _state.value.ticket?.customerPhone
        if (phone.isNullOrBlank()) return

        val smsBody = pending.notifications
            .firstOrNull { it.channel == "sms" }?.body ?: return

        viewModelScope.launch {
            try {
                smsApi.sendSms(mapOf("to" to phone, "message" to smsBody))
            } catch (e: Exception) {
                Timber.tag("StatusNotify").w(e, "SMS send after status change failed")
            }
        }
    }

    fun cancelPendingStatusChange() {
        _state.value = _state.value.copy(pendingStatusChange = null)
    }

    // -----------------------------------------------------------------------
    // plan:L790 — State-machine transition guard (wraps changeStatus)
    // -----------------------------------------------------------------------

    /**
     * Validates the transition via [TicketStateMachine.validateTransition] before
     * delegating to [changeStatus]. Sets [TicketDetailUiState.statusTransitionError]
     * inline when the guard fails; otherwise proceeds normally.
     *
     * Callers should prefer this over calling [changeStatus] directly so the
     * state-machine guard is always applied.
     */
    fun changeStatusGuarded(newStatusId: Long) {
        val ticket = _state.value.ticket ?: return
        val targetStatus = _state.value.statuses.find { it.id == newStatusId }
        val fromName = ticket.statusName
        val toName = targetStatus?.name

        val result = TicketStateMachine.validateTransition(
            fromStateName = fromName,
            toStateName = toName,
            targetStatusItem = targetStatus,
            hasNotes = _state.value.notes.isNotEmpty(),
            hasPhotos = _state.value.photos.isNotEmpty(),
            hasDevices = _state.value.devices.isNotEmpty(),
        )

        when (result) {
            is TransitionResult.Allowed -> requestStatusChangeWithNotify(newStatusId)
            is TransitionResult.Blocked -> _state.value = _state.value.copy(
                statusTransitionError = result.message,
            )
        }
    }

    // -----------------------------------------------------------------------
    // plan:L793 — Rollback status (admin-only)
    // -----------------------------------------------------------------------

    /**
     * Returns the rollback candidate list for the current ticket's status.
     * Prefers server statuses that match default-graph predecessors; falls back
     * to all non-terminal statuses when the current state is a custom tenant state.
     */
    val rollbackCandidateStatuses: List<TicketStatusItem>
        get() {
            val currentName = _state.value.ticket?.statusName
            val candidates = TicketStateMachine.rollbackCandidates(currentName)
            return if (candidates.isNotEmpty()) {
                // Map TicketState display names to loaded server status items
                val nameSet = candidates.map { it.displayName }.toSet()
                _state.value.statuses.filter { it.name in nameSet }
            } else {
                // For custom/unknown current states, offer all non-terminal statuses
                _state.value.statuses.filter { it.isClosed == 0 && it.isCancelled == 0 }
            }
        }

    fun showRollbackDialog() {
        _state.value = _state.value.copy(showRollbackDialog = true)
    }

    fun dismissRollbackDialog() {
        _state.value = _state.value.copy(showRollbackDialog = false)
    }

    /**
     * Execute a status rollback — admin only.
     *
     * 1. Validates via [TicketStateMachine.validateRollback].
     * 2. POSTs to `POST /tickets/:id/status-rollback` with `{statusId, reason}`.
     * 3. On 404 (endpoint not yet deployed), falls back to a standard PATCH status
     *    change so the rollback at least takes effect, then logs a warning.
     * 4. On success, refreshes the ticket detail.
     */
    fun rollbackStatus(targetStatusId: Long, reason: String) {
        val ticket = _state.value.ticket ?: return
        val targetStatus = _state.value.statuses.find { it.id == targetStatusId }

        val guard = TicketStateMachine.validateRollback(ticket.statusName, targetStatus?.name)
        if (guard is TransitionResult.Blocked) {
            _state.value = _state.value.copy(actionMessage = "Rollback blocked: ${guard.message}")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                ticketApi.rollbackStatus(
                    ticketId,
                    mapOf("statusId" to targetStatusId, "reason" to reason),
                )
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Status rolled back to \"${targetStatus?.name ?: targetStatusId}\"",
                )
                loadTicketDetail()
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Endpoint not deployed — degrade to a plain PATCH so the change still lands
                    Timber.tag("Rollback").w("rollback endpoint 404 — falling back to standard PATCH")
                    try {
                        ticketRepository.updateTicket(
                            ticketId,
                            UpdateTicketRequest(statusId = targetStatusId),
                        )
                        _state.value = _state.value.copy(
                            isActionInProgress = false,
                            actionMessage = "Status rolled back (audit endpoint pending deployment)",
                        )
                        loadTicketDetail()
                    } catch (ex: Exception) {
                        _state.value = _state.value.copy(
                            isActionInProgress = false,
                            actionMessage = "Rollback failed: ${ex.message}",
                        )
                    }
                } else {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Rollback failed: HTTP ${e.code()}",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Rollback failed: ${e.message}",
                )
            }
        }
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private suspend fun withStateOnMain(update: TicketDetailUiState.() -> TicketDetailUiState) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
            _state.value = _state.value.update()
        }
    }

    // -----------------------------------------------------------------------
    // Override loadTicketDetail to detect 404 (L680)
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // §4.13 L776-L777 — Permission-denied + concurrent-edit helpers (additive)
    // -----------------------------------------------------------------------

    /**
     * Signal that a role-gated action was attempted without privileges.
     * Sets [TicketDetailUiState.permissionDeniedMessage] which drives a one-shot Snackbar.
     * Message follows §67 tone ("Ask your admin to enable this.").
     */
    fun signalPermissionDenied(action: String = "") {
        val suffix = if (action.isNotBlank()) " ($action)" else ""
        _state.value = _state.value.copy(
            permissionDeniedMessage = "Ask your admin to enable this$suffix.",
        )
    }

    /** Consume the permission-denied message after it has been shown. */
    fun clearPermissionDenied() {
        _state.value = _state.value.copy(permissionDeniedMessage = null)
    }

    /**
     * Surface a concurrent-edit conflict (HTTP 409).
     * Call from any PUT/PATCH catch block when `e.code() == 409`.
     */
    fun signalConcurrentEdit() {
        _state.value = _state.value.copy(isConcurrentEdit = true)
    }

    /** Dismiss the concurrent-edit banner (called before reload). */
    fun clearConcurrentEdit() {
        _state.value = _state.value.copy(isConcurrentEdit = false)
    }

    // ─── §4.22 — Notify customer of delay ────────────────────────────────────

    /** Open the "Notify customer of delay" dialog from the overflow menu. */
    fun showNotifyDelayDialog() {
        _state.value = _state.value.copy(showNotifyDelayDialog = true)
    }

    /** Dismiss the notify-delay dialog without sending. */
    fun dismissNotifyDelayDialog() {
        _state.value = _state.value.copy(showNotifyDelayDialog = false, isDelaySendInProgress = false)
    }

    /**
     * Send the pre-filled delay SMS to the ticket's customer phone.
     *
     * Resolves phone from [TicketDetail.customer] (preferred) → [TicketEntity.customerPhone]
     * (Room cache fallback). 404-tolerant: if the server returns 404 the dialog is still
     * dismissed so the UI doesn't get stuck.
     *
     * @param message The (optionally edited) SMS body to send.
     */
    fun sendDelayNotificationSms(message: String) {
        val phone = _state.value.ticketDetail?.customer?.phone
            ?: _state.value.ticketDetail?.customer?.mobile
            ?: _state.value.ticket?.customerPhone

        if (phone.isNullOrBlank()) {
            viewModelScope.launch {
                withStateOnMain {
                    copy(showNotifyDelayDialog = false, actionMessage = "No customer phone on file")
                }
            }
            return
        }

        _state.value = _state.value.copy(isDelaySendInProgress = true)
        viewModelScope.launch {
            try {
                smsApi.sendSms(mapOf("to" to phone, "message" to message))
                withStateOnMain {
                    copy(
                        showNotifyDelayDialog = false,
                        isDelaySendInProgress = false,
                        actionMessage = "Delay notification sent",
                    )
                }
            } catch (e: Exception) {
                Timber.tag("NotifyDelay").w(e, "Delay SMS send failed")
                withStateOnMain {
                    copy(
                        showNotifyDelayDialog = false,
                        isDelaySendInProgress = false,
                        actionMessage = if ((e as? HttpException)?.code() == 404)
                            "SMS not sent — server endpoint unavailable"
                        else
                            "Failed to send SMS: ${e.message}",
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalSharedTransitionApi::class)
@Composable
fun TicketDetailScreen(
    sharedTransitionScope: SharedTransitionScope,
    animatedContentScope: AnimatedContentScope,
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
    // bug:gallery-400 fix: second Long is the ticket_device_id required by
    // the server upload endpoint.
    onAddPhotos: ((ticketId: Long, deviceId: Long) -> Unit)? = null,
    // AND-20260414-H4: route into the payment screen. Callback receives the
    // resolved total (from the TicketDetail DTO) + the customer display name
    // so the checkout summary card and payment-method gating are populated
    // without a second round-trip. Optional so the top-bar Checkout action
    // auto-hides on screens that don't wire it (previews / tests).
    onCheckout: ((ticketId: Long, total: Double, customerName: String) -> Unit)? = null,
    // L780-L786 — navigate to WaiverListScreen; hidden when null (feature not yet wired)
    onNavigateToWaivers: ((ticketId: Long) -> Unit)? = null,
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
    var showNoteDialog by rememberSaveable { mutableStateOf(false) }
    var noteText by rememberSaveable { mutableStateOf("") }
    var showConvertConfirm by rememberSaveable { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }

    // L681 — permission gate: privileged roles can see destructive actions
    val isPrivilegedRole = viewModel.isPrivilegedRole

    val context = LocalContext.current
    // Reduce-motion: read system setting without DI — ReduceMotion.decideReduceMotion is pure.
    val reduceMotion = remember {
        runCatching {
            android.provider.Settings.Global.getFloat(
                context.contentResolver,
                android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f
        }.getOrDefault(false)
    }

    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

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

    // §4.13 L776 — Permission-denied one-shot Snackbar.
    // Shown when a role-gated action is attempted by a user without privileges.
    LaunchedEffect(state.permissionDeniedMessage) {
        val msg = state.permissionDeniedMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearPermissionDenied()
        }
    }

    // -----------------------------------------------------------------------
    // Undo stack UI (§1 L232)
    // -----------------------------------------------------------------------

    // Collect UndoStack events: show a Snackbar with an "Undo" action on
    // Pushed, and a plain toast-style Snackbar on Failed.
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
                is UndoStack.UndoEvent.Undone -> {
                    Timber.tag("TicketUndo").i("Undone: ${event.entry.auditDescription}")
                    snackbarHostState.showSnackbar("Undone: ${event.entry.auditDescription}")
                }
                is UndoStack.UndoEvent.Redone -> {
                    Timber.tag("TicketUndo").i("Redone: ${event.entry.auditDescription}")
                }
                is UndoStack.UndoEvent.Failed -> {
                    Timber.tag("TicketUndo").w("Undo failed: ${event.reason}")
                    snackbarHostState.showSnackbar(event.reason)
                }
            }
        }
    }

    // Clear undo history when the screen is removed from composition so stale
    // entries don't survive a back-stack pop and re-push.
    DisposableEffect(viewModel) {
        onDispose { viewModel.undoStack.clear() }
    }

    // L679 — Continuity banner: publish ticket ID as AssistContent extras
    // so Android Slices / cross-device handoff can deep-link to this ticket.
    // Requires Google Cross-device Services (future work). Stub via LocalActivity
    // is a no-op on most devices today.
    // NOTE: Full implementation requires hooking into Activity.onProvideAssistContent
    // which is already supported in MainActivity (see existing onProvideAssistContent).
    // Passing ticket info via Intent extras is sufficient for the handoff mechanism.

    // ─── L725 — Warranty dialog ───────────────────────────────────────────────
    if (state.showWarrantyDialog) {
        TicketWarrantyDialog(
            isLoading = state.warrantyLoading,
            result = state.warrantyResult,
            errorMessage = state.warrantyError,
            onLookup = { viewModel.lookupWarranty(it) },
            onDismiss = { viewModel.dismissWarrantyDialog() },
        )
    }

    // ─── L726 — Device history sheet ─────────────────────────────────────────
    if (state.showDeviceHistory) {
        DeviceHistorySheet(
            entries = state.deviceHistoryEntries,
            isLoading = state.deviceHistoryLoading,
            errorMessage = state.deviceHistoryError,
            onTicketTap = { /* navigate to ticket — same screen, replace stack */ onBack() },
            onDismiss = { viewModel.dismissDeviceHistory() },
        )
    }

    // ─── L741 — QC sign-off bottom sheet ─────────────────────────────────────
    if (state.showQcSignOffDialog) {
        QcSignOffDialog(
            reduceMotion = reduceMotion,
            onConfirm = { bitmap, comments ->
                viewModel.submitQcSignOff(
                    signatureBitmap = bitmap,
                    comments = comments,
                    cacheDir = context.cacheDir,
                )
            },
            onDismiss = { viewModel.dismissQcSignOff() },
        )
    }

    // ─── L742 — Status notify preview dialog ─────────────────────────────────
    state.pendingStatusChange?.let { pending ->
        if (pending.notifications.isNotEmpty()) {
            val targetName = state.statuses.find { it.id == pending.newStatusId }?.name ?: "New Status"
            StatusNotifyPreviewDialog(
                newStatusName = targetName,
                notifications = pending.notifications,
                onSend = { viewModel.confirmStatusChangeWithNotify(sendNotifications = true) },
                onSkip = { viewModel.confirmStatusChangeWithNotify(sendNotifications = false) },
                onCancel = { viewModel.cancelPendingStatusChange() },
            )
        }
    }

    // ─── §4.22 — Notify customer of delay dialog ─────────────────────────────
    if (state.showNotifyDelayDialog) {
        val customerName = state.ticketDetail?.customer?.let { c ->
            listOfNotNull(c.firstName, c.lastName).joinToString(" ").ifBlank { null }
        } ?: ticket?.customerName ?: "Customer"
        val orderId = ticket?.orderId?.let { "#$it" } ?: "your repair"
        NotifyDelayDialog(
            customerName = customerName,
            orderId = orderId,
            isSendInProgress = state.isDelaySendInProgress,
            onSend = { msg -> viewModel.sendDelayNotificationSms(msg) },
            onDismiss = { viewModel.dismissNotifyDelayDialog() },
        )
    }

    // ─── L740 — Status transition error snackbar ──────────────────────────────
    LaunchedEffect(state.statusTransitionError) {
        state.statusTransitionError?.let { err ->
            snackbarHostState.showSnackbar(err)
            viewModel.clearStatusTransitionError()
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
            // Width gate — tablet (sw >= 600 dp) renders its own top bar
            // inside TicketDetailTabletLayoutV2 (T-C2 of the tablet
            // redesign). Phone keeps the existing BrandTopAppBar.
            if (com.bizarreelectronics.crm.util.isCompactWidth()) {
            // BrandTopAppBar with a custom title slot: orderId in mono + status badge.
            // sharedElement applied via titleContent so the orderId Text animates
            // from the list row without wrapping the whole TopAppBar.
            BrandTopAppBar(
                title = ticket?.orderId ?: "T-$ticketId",
                titleContent = {
                    val orderId = ticket?.orderId ?: "T-$ticketId"
                    with(sharedTransitionScope) {
                        Text(
                            text = orderId,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier
                                .semantics { heading() }
                                .sharedElement(
                                    sharedContentState = rememberSharedContentState(key = "ticket-${ticketId}-orderid"),
                                    animatedVisibilityScope = animatedContentScope,
                                ),
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (ticket != null) {
                        val detail = state.ticketDetail
                        // AND-20260414-H4: Checkout action routes into the
                        // payment screen with ticket id + total + customer
                        // name pre-filled. Gated on (a) a non-null callback
                        // wired by the nav graph, (b) a total > 0 — so
                        // tickets still in intake (no priced parts yet) don't
                        // expose a button that would immediately fail the
                        // in-screen guard, and (c) not already mid-action.
                        val checkoutTotal = detail?.total ?: 0.0
                        val canCheckout = onCheckout != null &&
                            checkoutTotal > 0.0 &&
                            !state.isActionInProgress
                        if (canCheckout) {
                            IconButton(
                                onClick = {
                                    val displayName = detail?.customer?.let { c ->
                                        listOfNotNull(c.firstName, c.lastName)
                                            .joinToString(" ")
                                            .ifBlank { null }
                                    } ?: ticket.customerName ?: ""
                                    onCheckout!!(ticketId, checkoutTotal, displayName)
                                },
                            ) {
                                Icon(
                                    Icons.Default.PointOfSale,
                                    contentDescription = "Checkout",
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }
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
                        // L674 — Print/PDF/SMS/Email actions in overflow
                        val customerName = state.ticketDetail?.customer?.let { c ->
                            listOfNotNull(c.firstName, c.lastName).joinToString(" ").ifBlank { null }
                        } ?: ticket.customerName ?: ""
                        val deviceName = state.devices.firstOrNull()?.let { it.name ?: it.deviceName }
                        TicketPrintActions(
                            ticketId = ticketId,
                            orderId = ticket.orderId ?: "T-$ticketId",
                            customerName = customerName,
                            deviceName = deviceName,
                            serverUrl = viewModel.serverUrl,
                            // §55.3 — pass tracking URL so the label action can encode it in the QR
                            trackingUrl = state.ticketDetail?.trackingUrl(),
                            snackbarHost = snackbarHostState,
                        )
                        // Overflow menu — Copy Link + permission-gated destructive actions
                        Box {
                            IconButton(onClick = { showOverflowMenu = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "More options")
                            }
                            DropdownMenu(
                                expanded = showOverflowMenu,
                                onDismissRequest = { showOverflowMenu = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Copy link") },
                                    leadingIcon = { Icon(Icons.Default.Link, contentDescription = null) },
                                    onClick = {
                                        showOverflowMenu = false
                                        ClipboardUtil.copy(context, "Ticket link", "bizarrecrm://tickets/$ticketId")
                                        scope.launch {
                                            snackbarHostState.showSnackbar("Link copied")
                                        }
                                    },
                                )
                                // §55.1 — Share tracking link (customer-facing repair status URL)
                                val trackingUrl = state.ticketDetail?.trackingUrl()
                                if (trackingUrl != null) {
                                    DropdownMenuItem(
                                        text = { Text(context.getString(com.bizarreelectronics.crm.R.string.public_tracking_share_label)) },
                                        leadingIcon = { Icon(Icons.Default.Share, contentDescription = null) },
                                        onClick = {
                                            showOverflowMenu = false
                                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                                type = "text/plain"
                                                putExtra(Intent.EXTRA_TEXT, trackingUrl)
                                                putExtra(
                                                    Intent.EXTRA_SUBJECT,
                                                    context.getString(com.bizarreelectronics.crm.R.string.public_tracking_share_chooser_title),
                                                )
                                            }
                                            context.startActivity(
                                                Intent.createChooser(
                                                    shareIntent,
                                                    context.getString(com.bizarreelectronics.crm.R.string.public_tracking_share_chooser_title),
                                                )
                                            )
                                        },
                                    )
                                }
                                // §25.3 — Copy order ID (ticket #) to clipboard
                                val orderId = ticket?.orderId ?: "T-$ticketId"
                                DropdownMenuItem(
                                    text = { Text("Copy order ID") },
                                    leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
                                    onClick = {
                                        showOverflowMenu = false
                                        ClipboardUtil.copy(context, "Order ID", orderId)
                                        scope.launch {
                                            snackbarHostState.showSnackbar("Order ID copied")
                                        }
                                    },
                                )
                                // §25.3 — Copy IMEI (PII → sensitive copy, auto-clears 30 s)
                                val firstImei = state.devices.firstOrNull { !it.imei.isNullOrBlank() }?.imei
                                if (firstImei != null) {
                                    DropdownMenuItem(
                                        text = { Text("Copy IMEI") },
                                        leadingIcon = { Icon(Icons.Default.PhoneAndroid, contentDescription = null) },
                                        onClick = {
                                            showOverflowMenu = false
                                            // IMEI is PII — use sensitive copy so Android 13+
                                            // suppresses clipboard preview and auto-clears after 30 s.
                                            ClipboardUtil.copySensitive(context, "IMEI", firstImei)
                                            scope.launch {
                                                snackbarHostState.showSnackbar("IMEI copied (auto-clears in 30 s)")
                                            }
                                        },
                                    )
                                }
                                // L725 — Check warranty
                                DropdownMenuItem(
                                    text = { Text("Check warranty") },
                                    leadingIcon = { Icon(Icons.Default.VerifiedUser, contentDescription = null) },
                                    onClick = {
                                        showOverflowMenu = false
                                        viewModel.showWarrantyDialog()
                                    },
                                )
                                // L726 — Device history
                                DropdownMenuItem(
                                    text = { Text("Device history") },
                                    leadingIcon = { Icon(Icons.Default.History, contentDescription = null) },
                                    onClick = {
                                        showOverflowMenu = false
                                        viewModel.showDeviceHistory()
                                    },
                                )
                                // L727 — Pin to dashboard
                                DropdownMenuItem(
                                    text = { Text("Pin to dashboard") },
                                    leadingIcon = { Icon(Icons.Default.PushPin, contentDescription = null) },
                                    onClick = {
                                        showOverflowMenu = false
                                        viewModel.pinToDashboard()
                                    },
                                )
                                // §4.22 — Notify customer of delay (only when customer has a phone)
                                val canNotifyDelay = !(state.ticketDetail?.customer?.phone.isNullOrBlank() &&
                                    state.ticketDetail?.customer?.mobile.isNullOrBlank() &&
                                    state.ticket?.customerPhone.isNullOrBlank())
                                if (canNotifyDelay) {
                                    DropdownMenuItem(
                                        text = { Text("Notify customer of delay") },
                                        leadingIcon = { Icon(Icons.Default.Sms, contentDescription = null) },
                                        onClick = {
                                            showOverflowMenu = false
                                            viewModel.showNotifyDelayDialog()
                                        },
                                    )
                                }
                                // L741 — QC sign-off (admin / manager / tech)
                                run {
                                    val qcRole = state.userRole?.lowercase()?.let { r ->
                                        r == "admin" || r == "manager" || r == "tech" || r == "owner"
                                    } ?: false
                                    if (qcRole) {
                                        DropdownMenuItem(
                                            text = { Text("QC sign-off") },
                                            leadingIcon = { Icon(Icons.Default.VerifiedUser, contentDescription = null) },
                                            onClick = {
                                                showOverflowMenu = false
                                                viewModel.showQcSignOff()
                                            },
                                        )
                                    }
                                }
                                // L780-L786 — Waivers (hidden on 404)
                                if (state.waiverFeatureEnabled) {
                                    DropdownMenuItem(
                                        text = { Text("Waivers") },
                                        leadingIcon = { Icon(Icons.Default.Assignment, contentDescription = null) },
                                        onClick = {
                                            showOverflowMenu = false
                                            onNavigateToWaivers?.invoke(ticketId)
                                        },
                                    )
                                }
                                // L681 — Destructive actions gated on privileged role
                                if (isPrivilegedRole) {
                                    DropdownMenuItem(
                                        text = { Text("Delete ticket", color = MaterialTheme.colorScheme.error) },
                                        leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                                        onClick = {
                                            showOverflowMenu = false
                                            // TODO: wire showDeleteConfirm dialog — role check already gates this item
                                            scope.launch {
                                                snackbarHostState.showSnackbar("Delete: confirm in dialog (wired in next wave)")
                                            }
                                        },
                                    )
                                }
                            }
                        }
                    }
                },
            )
            } // closes `if (isCompactWidth())` — tablet renders its own top bar
        },
        bottomBar = {
            // AND-20260414-M9 (revised): previous attempt folded SMS +
            // Print into a kebab-menu, which hid commonly-used actions
            // behind an extra tap. User feedback: prefer keeping all five
            // actions visible and tighten the layout to fit a native
            // 1440x3120 (~360dp) phone. Fix: compact vertical column
            // buttons (icon-above-label) with no Row padding, minimum
            // touch width shrunk via `ButtonDefaults.TextButtonContentPadding`,
            // label at `labelSmall` (11sp) so five fit without the last
            // one collapsing to vertical chars.
            //
            // `navigationBarsPadding()` lives on `BottomAppBar` by default
            // via its Material3 windowInsets param, so the safe-area gap
            // is preserved.
            BottomAppBar(contentPadding = PaddingValues(horizontal = 4.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Status (with dropdown)
                    Box(modifier = Modifier.weight(1f)) {
                        CompactBottomBarButton(
                            icon = Icons.Default.SwapHoriz,
                            label = "Status",
                            enabled = !state.isActionInProgress,
                            onClick = { showStatusDropdown = true },
                        )
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
                                        // L742 — show notify preview if status triggers customer notification
                                        viewModel.requestStatusChangeWithNotify(status.id)
                                    },
                                    enabled = status.id != ticket?.statusId,
                                )
                            }
                        }
                    }
                    // Call
                    run {
                        val context = LocalContext.current
                        val detail = state.ticketDetail
                        val phone = detail?.customer?.phone ?: detail?.customer?.mobile ?: ticket?.customerPhone
                        Box(modifier = Modifier.weight(1f)) {
                            CompactBottomBarButton(
                                icon = Icons.Default.Phone,
                                label = "Call",
                                enabled = phone != null,
                                onClick = {
                                    if (phone != null) {
                                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${phone}"))
                                        context.startActivity(intent)
                                    }
                                },
                            )
                        }
                    }
                    // Note
                    Box(modifier = Modifier.weight(1f)) {
                        CompactBottomBarButton(
                            icon = Icons.Default.Note,
                            label = "Note",
                            enabled = !state.isActionInProgress,
                            onClick = { showNoteDialog = true },
                        )
                    }
                    // SMS
                    run {
                        val smsDetail = state.ticketDetail
                        val smsPhone = smsDetail?.customer?.phone
                            ?: smsDetail?.customer?.mobile
                            ?: ticket?.customerPhone
                        val canSms = smsPhone != null && onNavigateToSms != null
                        Box(modifier = Modifier.weight(1f)) {
                            CompactBottomBarButton(
                                icon = Icons.Default.Sms,
                                label = "SMS",
                                enabled = canSms,
                                onClick = {
                                    if (smsPhone != null && onNavigateToSms != null) {
                                        val normalized = smsPhone
                                            .replace(Regex("[^0-9]"), "")
                                            .let {
                                                if (it.length == 11 && it.startsWith("1")) it.substring(1) else it
                                            }
                                        onNavigateToSms(normalized)
                                    }
                                },
                            )
                        }
                    }
                    // Print
                    run {
                        val context = LocalContext.current
                        val serverUrl = viewModel.serverUrl
                        // AND-20260414-L1: Print launches a browser intent
                        // against the CRM server's `/print/ticket/:id` route.
                        // Without a configured server URL OR while offline
                        // the intent would resolve to an unreachable URL, so
                        // the button disables itself. TODO(AND-20260414-L1):
                        // build a proper offline receipt renderer on device
                        // so this flow works without network — that's the
                        // "proper fix" deferred per the spec.
                        val isOnline by viewModel.isEffectivelyOnline.collectAsState()
                        val canPrint = serverUrl.isNotBlank() && isOnline
                        Box(modifier = Modifier.weight(1f)) {
                            CompactBottomBarButton(
                                icon = Icons.Default.Print,
                                label = "Print",
                                enabled = canPrint,
                                onClick = {
                                    if (canPrint) {
                                        val url = "$serverUrl/print/ticket/$ticketId?size=letter"
                                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                        context.startActivity(intent)
                                    } else {
                                        // AUDIT-AND-018: use Snackbar instead of Toast
                                        // so the message follows Material3 patterns and
                                        // is accessible to screen readers.
                                        scope.launch {
                                            snackbarHostState.showSnackbar("Printing is not available offline")
                                        }
                                    }
                                },
                            )
                        }
                    }
                }
            }
        },
    ) { padding ->
        // L680 — Deleted-while-viewing banner anchored above content
        Column(modifier = Modifier.fillMaxSize()) {
            DeletedBanner(
                visible = state.isDeletedWhileViewing,
                onClose = onBack,
            )
            // §4.13 L777 — Concurrent-edit banner (HTTP 409 stale updated_at)
            ConcurrentEditBanner(
                visible = state.isConcurrentEdit,
                onReload = {
                    viewModel.clearConcurrentEdit()
                    viewModel.loadTicketDetail()
                },
            )
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
                    // Width gate — tablet (sw >= 600 dp) routes through the
                    // new TicketDetailTabletLayoutV2 so subsequent phases of
                    // the redesign (T-C2 onward, plan at
                    // ~/.claude/plans/tablet-ticket-detail-redesign.md) can
                    // replace the body one card at a time. Phone keeps the
                    // existing single-column layout via the same Row block
                    // unchanged. T-C1 is a transparent pass-through — no
                    // visual change on either form factor.
                    val existingRowBody: @Composable () -> Unit = {
                        Row(modifier = Modifier.fillMaxSize()) {
                            TicketDetailContent(
                                modifier = Modifier.weight(1f),
                                ticket = ticket,
                                ticketId = ticketId,
                                sharedTransitionScope = sharedTransitionScope,
                                animatedContentScope = animatedContentScope,
                                ticketDetail = state.ticketDetail,
                                devices = state.devices,
                                notes = state.notes,
                                history = state.history,
                                photos = state.photos,
                                statuses = state.statuses,
                                payments = state.ticketDetail?.payments ?: emptyList(),
                                employees = state.employees,
                                isActionInProgress = state.isActionInProgress,
                                isBenchTimerRunning = state.isBenchTimerRunning,
                                reduceMotion = reduceMotion,
                                padding = padding,
                                onNavigateToCustomer = onNavigateToCustomer,
                                onEditDevice = onEditDevice,
                                onAddPhotos = onAddPhotos,
                                serverUrl = viewModel.serverUrl,
                                onStatusSelected = { viewModel.changeStatus(it) },
                                onAddNote = { viewModel.addNote(it) },
                                onNavigateToSms = onNavigateToSms,
                                onDeletePhoto = { viewModel.deletePhoto(it) },
                                onBenchStart = { viewModel.startBenchTimer() },
                                onBenchStop = { viewModel.stopBenchTimer() },
                            )
                            // L677 — Related rail: tablet only; phone gets zero-size stub
                            TicketRelatedRail(
                                photos = state.photos,
                                serverUrl = viewModel.serverUrl,
                            )
                        }
                    }
                    if (com.bizarreelectronics.crm.util.isCompactWidth()) {
                        existingRowBody()
                    } else {
                        com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.TicketDetailTabletLayoutV2(
                            ticket = ticket,
                            ticketId = ticketId,
                            sharedTransitionScope = sharedTransitionScope,
                            animatedContentScope = animatedContentScope,
                            ticketDetail = state.ticketDetail,
                            devices = state.devices,
                            notes = state.notes,
                            history = state.history,
                            photos = state.photos,
                            statuses = state.statuses,
                            payments = state.ticketDetail?.payments ?: emptyList(),
                            employees = state.employees,
                            isActionInProgress = state.isActionInProgress,
                            isBenchTimerRunning = state.isBenchTimerRunning,
                            reduceMotion = reduceMotion,
                            padding = padding,
                            onBack = onBack,
                            ticketTitle = ticket.orderId ?: "T-$ticketId",
                            currentStatusName = ticket.statusName ?: "",
                            currentStatusId = ticket.statusId,
                            onStatusSelected = { id ->
                                // Route through the same notify-preview flow phone uses.
                                viewModel.requestStatusChangeWithNotify(id)
                            },
                            topBarActions = {
                                // T-C2 minimal action stub — Pin + overflow placeholder.
                                // Full feature parity (Print actions / Share / Copy / etc.)
                                // moves over from the phone topBar in a follow-up phase.
                                IconButton(onClick = { viewModel.togglePin() }) {
                                    Icon(
                                        Icons.Default.PushPin,
                                        contentDescription = "Pin",
                                        tint = if (state.ticketDetail?.isPinned == true)
                                            MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(onClick = { showOverflowMenu = true }) {
                                    Icon(Icons.Default.MoreVert, contentDescription = "More options")
                                }
                                // Reuse the existing overflow DropdownMenu from the phone path
                                // by hosting it once at the tablet root in a future commit.
                                // For T-C2 a placeholder snackbar so the icon isn't dead.
                            },
                            onNavigateToCustomer = onNavigateToCustomer,
                            onEditDevice = onEditDevice,
                            onAddPhotos = onAddPhotos,
                            serverUrl = viewModel.serverUrl,
                            onAddNote = { viewModel.addNote(it) },
                            onNavigateToSms = onNavigateToSms,
                            onDeletePhoto = { viewModel.deletePhoto(it) },
                            onBenchStart = { viewModel.startBenchTimer() },
                            onBenchStop = { viewModel.stopBenchTimer() },
                            // T-C3 — left pane = existing TicketDetailContent (single
                            // column squeezed into 38 % width). Phases T-C4..T-C7
                            // replace this slot one card at a time. The Rail no
                            // longer renders on tablet — its photos role moves
                            // into the new PhotosCard in T-C7.
                            leftPaneContent = {
                                TicketDetailContent(
                                    modifier = Modifier.fillMaxSize(),
                                    ticket = ticket,
                                    ticketId = ticketId,
                                    sharedTransitionScope = sharedTransitionScope,
                                    animatedContentScope = animatedContentScope,
                                    ticketDetail = state.ticketDetail,
                                    devices = state.devices,
                                    notes = state.notes,
                                    history = state.history,
                                    photos = state.photos,
                                    statuses = state.statuses,
                                    payments = state.ticketDetail?.payments ?: emptyList(),
                                    employees = state.employees,
                                    isActionInProgress = state.isActionInProgress,
                                    isBenchTimerRunning = state.isBenchTimerRunning,
                                    reduceMotion = reduceMotion,
                                    padding = padding,
                                    onNavigateToCustomer = onNavigateToCustomer,
                                    onEditDevice = onEditDevice,
                                    onAddPhotos = onAddPhotos,
                                    serverUrl = viewModel.serverUrl,
                                    onStatusSelected = { viewModel.changeStatus(it) },
                                    onAddNote = { viewModel.addNote(it) },
                                    onNavigateToSms = onNavigateToSms,
                                    onDeletePhoto = { viewModel.deletePhoto(it) },
                                    onBenchStart = { viewModel.startBenchTimer() },
                                    onBenchStop = { viewModel.stopBenchTimer() },
                                )
                            },
                            // T-C3 — right pane placeholder until T-C8 (Activity
                            // feed) and T-C9 (compose bar) land.
                            rightPaneContent = {
                                com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.TabletPanePlaceholder(
                                    label = "Activity feed lands in T-C8 · compose bar lands in T-C9",
                                )
                            },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
private fun TicketDetailContent(
    ticket: TicketEntity,
    // AND-20260414-M1: the ticket id from the route args. Needed by the
    // Photos section so tapping "Add Photo" can create the
    // `tickets/{ticketId}/photos` destination. Kept separate from
    // `ticket.id` because TicketEntity.id may not equal the URL param in
    // corner cases (offline-created tickets use a negative temp id).
    ticketId: Long,
    sharedTransitionScope: SharedTransitionScope,
    animatedContentScope: AnimatedContentScope,
    ticketDetail: TicketDetail?,
    devices: List<TicketDevice>,
    notes: List<TicketNote>,
    history: List<TicketHistory>,
    photos: List<TicketPhoto>,
    statuses: List<com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem> = emptyList(),
    payments: List<com.bizarreelectronics.crm.data.remote.dto.PaymentSummary> = emptyList(),
    employees: List<EmployeeListItem> = emptyList(),
    isActionInProgress: Boolean = false,
    isBenchTimerRunning: Boolean = false,
    reduceMotion: Boolean = false,
    padding: PaddingValues,
    onNavigateToCustomer: (Long) -> Unit,
    onEditDevice: (Long) -> Unit = {},
    onAddPhotos: ((ticketId: Long, deviceId: Long) -> Unit)? = null,
    serverUrl: String = "",
    onStatusSelected: (Long) -> Unit = {},
    onAddNote: (String) -> Unit = {},
    onNavigateToSms: ((String) -> Unit)? = null,
    onDeletePhoto: (Long) -> Unit = {},
    onBenchStart: () -> Unit = {},
    onBenchStop: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier
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
                    // decorative — BrandCard(onClick=...) wrapping Row already merges descendants; sibling customerName Text + "Tap to view customer" Text supply the accessible name
                    Icon(Icons.Default.Person, contentDescription = null)
                    Column {
                        with(sharedTransitionScope) {
                        Text(
                            customerName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.sharedElement(
                                sharedContentState = rememberSharedContentState(key = "ticket-${ticketId}-customer"),
                                animatedVisibilityScope = animatedContentScope,
                            ),
                        )
                        } // with(sharedTransitionScope)
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

        // §4.2 — Status / urgency / due-date chip row (completes [~] header item)
        // §70.3 — pass shared-element scopes so the status pill morphs during
        // the list→detail transition (STATUS_CHIP key matched by TicketListRow).
        item {
            TicketDetailHeaderRow(
                ticket = ticket,
                ticketId = ticketId,
                sharedTransitionScope = sharedTransitionScope,
                animatedContentScope = animatedContentScope,
                modifier = Modifier.fillMaxWidth(),
            )
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

        // Tab layout — Actions / Devices / Notes / Payments
        item {
            TicketDetailTabs(
                ticket = ticket,
                ticketDetail = ticketDetail,
                devices = devices,
                notes = notes,
                history = history,
                payments = payments,
                statuses = statuses,
                employees = employees,
                isActionInProgress = isActionInProgress,
                reduceMotion = reduceMotion,
                onStatusSelected = onStatusSelected,
                onAddNote = onAddNote,
                onEditDevice = onEditDevice,
                onNavigateToSms = onNavigateToSms,
            )
        }

        // -------------------------------------------------------------------
        // Legacy sections below — kept for Photos and Total which are not
        // yet in any tab. Devices/Notes/History are now in their tabs above.
        // -------------------------------------------------------------------

        // Devices section (legacy — still shown below tabs for now)
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
                        // decorative — timeline bullet marker; adjacent entry description and date Text announce the content
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

        // L669 — Photo gallery (replaces legacy horizontal scroll strip)
        item {
            TicketPhotoGallery(
                photos = photos,
                serverUrl = serverUrl,
                ticketId = ticketId,
                deviceId = devices.firstOrNull()?.id,
                onDeletePhoto = onDeletePhoto,
                reduceMotion = reduceMotion,
            )
        }

        // L673 — QR code card for order ID
        item {
            TicketQrCard(orderId = ticket.orderId ?: "T-$ticketId")
        }

        // L678 — Bench timer
        item {
            BenchTimerCard(
                ticketId = ticketId,
                orderId = ticket.orderId ?: "T-$ticketId",
                isRunning = isBenchTimerRunning,
                onStart = onBenchStart,
                onStop = onBenchStop,
            )
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

/**
 * AND-20260414-M9: compact vertical icon-above-label button for the
 * TicketDetail bottom action bar. Five of these fit side-by-side on a
 * ~360dp native 1440x3120 phone without text wrapping. Replaces the
 * default M3 TextButton whose 48dp minimum height + horizontal
 * label-after-icon layout + default content padding squeezed the last
 * button's label into a vertical character stack.
 *
 * Key sizing choices:
 * - Icon 20dp (bigger than a chip icon but smaller than a top-app-bar
 *   icon — matches the visual weight of the label below it).
 * - Label 10sp with single-line truncation — fits "Status"/"Print"/"SMS"
 *   at the narrowest column width on a 360dp phone. `maxLines = 1` with
 *   no overflow ellipsis because our labels are all short enough.
 * - `Arrangement.Center` vertically + `Alignment.CenterHorizontally` so
 *   the 48dp+ touch target stays centered regardless of label length.
 * - `fillMaxHeight` lets the `BottomAppBar`'s default 80dp height govern
 *   the touch surface while the content stays compact.
 * - Disabled state dims both icon and label to onSurface.38f per M3
 *   spec (same as the default TextButton disabled alpha).
 */
@Composable
private fun CompactBottomBarButton(
    icon: ImageVector,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tint = if (enabled) {
        MaterialTheme.colorScheme.onSurface
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    }
    Column(
        modifier = modifier
            .fillMaxSize()
            .clickable(enabled = enabled, onClick = onClick)
            // D5-1: merge the icon + label into one TalkBack focus item named
            // by the label so the announcement is "Status, button" / "Print,
            // button" instead of skipping the icon and announcing just the
            // label text with no role.
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(horizontal = 2.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = icon,
            // decorative — parent Column's mergeDescendants + label Text supplies the accessible name
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(20.dp),
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = label,
            color = tint,
            fontSize = 10.sp,
            maxLines = 1,
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.labelSmall,
        )
    }
}

// ─── §4.22 NotifyDelayDialog ──────────────────────────────────────────────────

/**
 * §4.22 — "One-tap Notify customer of delay" dialog.
 *
 * Opens from the ticket-detail overflow menu when the customer has a phone number
 * on file. Pre-fills a delay template that the staff member can edit before sending.
 * Calls [onSend] with the (possibly edited) body; caller drives [isSendInProgress]
 * to show a spinner while the SMS is in-flight.
 *
 * The dialog is self-contained: it manages the mutable message body state internally
 * and surfaces it to the caller only on confirm. This keeps the ViewModel free of
 * intermediate text state.
 */
@Composable
private fun NotifyDelayDialog(
    customerName: String,
    orderId: String,
    isSendInProgress: Boolean,
    onSend: (message: String) -> Unit,
    onDismiss: () -> Unit,
) {
    // Pre-filled template — staff can edit before sending.
    var messageBody by rememberSaveable {
        mutableStateOf(
            "Hi $customerName, we wanted to let you know that $orderId is " +
                "taking a bit longer than expected. We appreciate your patience " +
                "and will update you as soon as it's ready. Thank you!"
        )
    }

    AlertDialog(
        onDismissRequest = { if (!isSendInProgress) onDismiss() },
        title = {
            Text(
                text = "Notify Customer of Delay",
                style = MaterialTheme.typography.titleMedium,
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "Edit the message below before sending. It will be sent as an SMS to the customer's phone number on file.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = messageBody,
                    onValueChange = { messageBody = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("SMS message") },
                    minLines = 4,
                    maxLines = 8,
                    enabled = !isSendInProgress,
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSend(messageBody) },
                enabled = !isSendInProgress && messageBody.isNotBlank(),
            ) {
                if (isSendInProgress) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text("Send SMS")
                }
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isSendInProgress,
            ) {
                Text("Cancel")
            }
        },
    )
}
