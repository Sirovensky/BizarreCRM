package com.bizarreelectronics.crm.ui.screens.customers

import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.ripple
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerAnalytics
import com.bizarreelectronics.crm.data.remote.dto.CustomerNote
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.components.TagChip
import com.bizarreelectronics.crm.ui.components.hashTagToColor
import retrofit2.HttpException
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandSecondaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.CustomerAvatar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerDetailTabs
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.UndoStack
import com.bizarreelectronics.crm.util.VCardBuilder
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import com.bizarreelectronics.crm.util.toCentsOrZero
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber
import java.io.File
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Domain type for customer undo entries (§1 L232)
// ---------------------------------------------------------------------------

/**
 * Sealed payload type covering all reversible customer mutations wired to
 * [UndoStack] in [CustomerDetailViewModel]. Immutable data classes only.
 */
sealed class CustomerEdit {
    /** A generic scalar field update (e.g. firstName, phone, email). */
    data class FieldEdit(
        val fieldName: String,
        val oldValue: String?,
        val newValue: String?,
    ) : CustomerEdit()

    /** Tags change — old and new tag string (comma-separated). */
    data class TagsEdit(
        val oldTags: String?,
        val newTags: String?,
    ) : CustomerEdit()

    /** A note that was added online (noteId is the server-assigned id). */
    data class NoteAdded(
        val noteId: Long,
        val body: String,
    ) : CustomerEdit()
}

data class CustomerDetailUiState(
    val customer: CustomerEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    /**
     * CROSS50-header: optional analytics payload fetched in parallel with the
     * detail flow. Null until the first `GET /:id/analytics` response resolves.
     * A failed or still-in-flight fetch renders nothing (quiet degrade) rather
     * than blocking the detail screen from showing cached contact info.
     */
    val analytics: CustomerAnalytics? = null,
    /**
     * CROSS9a: recent ticket history for this customer. Loaded in parallel
     * with the detail + analytics fetches from `GET /customers/:id/tickets`.
     * Capped at 10 most-recent rows per spec. Null = not yet loaded; an empty
     * list = loaded, no tickets found.
     */
    val recentTickets: List<TicketListItem>? = null,
    /**
     * CROSS9b: timeline of dated notes. Null = not yet loaded (silent
     * degrade — card simply doesn't render), empty list = card shows an
     * empty state + composer. Posting a new note prepends to this list.
     */
    val notes: List<CustomerNote>? = null,
    /** CROSS9b: single-line composer input. */
    val noteDraft: String = "",
    /** CROSS9b: true while a note POST is in flight. */
    val isPostingNote: Boolean = false,
    val isEditing: Boolean = false,
    val isSaving: Boolean = false,
    val editFirstName: String = "",
    val editLastName: String = "",
    val editPhone: String = "",
    val editEmail: String = "",
    val editOrganization: String = "",
    val editAddress: String = "",
    val editCity: String = "",
    val editState: String = "",
    val editZip: String = "",
    /** Comma-separated tag list, matching the web app's Tags field. */
    val editTags: String = "",
    /** Currently assigned customer group id. Full group dropdown TBD; for now edit supports clearing. */
    val editGroupId: Long? = null,
    /** Display-only group name snapshot captured when editing begins. */
    val editGroupName: String? = null,
    val saveMessage: String? = null,
    /** TAG-PALETTE-001: tenant tag color palette loaded from GET /settings/tag-palette. */
    val tagPalette: Map<String, Color> = emptyMap(),
    /**
     * OPTIMISTIC-SAVE: "Saving…" chip shown while PUT is in-flight.
     * On 200 → isSaving=false. On error → isSaving=false + rollback + snackbar.
     */
    val savingChipVisible: Boolean = false,
    /** 409 banner — shown when PUT returns 409 (concurrent edit). */
    val showConflictBanner: Boolean = false,
    // plan:L892 — health score ring (null = not loaded / 404)
    val healthScore: com.bizarreelectronics.crm.data.remote.dto.CustomerHealthScore? = null,
    // plan:L893 — LTV tier chip (null = not loaded / 404)
    val ltvTier: com.bizarreelectronics.crm.data.remote.dto.CustomerLtvTier? = null,
    // plan:L897 — invoices tab
    val invoices: List<com.bizarreelectronics.crm.data.remote.dto.InvoiceListItem>? = null,
    // plan:L897 — assets tab
    val assets: List<com.bizarreelectronics.crm.data.remote.dto.CustomerAsset>? = null,
    // plan:L905 — delete confirm dialog
    val showDeleteConfirm: Boolean = false,
)

@HiltViewModel
class CustomerDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val customerRepository: CustomerRepository,
    private val customerApi: CustomerApi,
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val customerId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(CustomerDetailUiState())
    val state = _state.asStateFlow()
    private var collectJob: Job? = null
    private var analyticsJob: Job? = null
    private var ticketsJob: Job? = null
    private var notesJob: Job? = null

    // -----------------------------------------------------------------------
    // Undo / redo (§1 L232 — customer field edit, tags edit, note add)
    // -----------------------------------------------------------------------

    /** Undo stack scoped to this ViewModel instance; cleared on nav dismiss. */
    val undoStack = UndoStack<CustomerEdit>()

    /**
     * Convenience alias so the screen can gate an Undo Snackbar action without
     * importing [UndoStack] — delegates directly to [undoStack.canUndo].
     */
    val canUndo: StateFlow<Boolean> = undoStack.canUndo

    init {
        loadCustomer()
        observeUndoEvents()
        loadTagPalette()
    }

    private fun loadTagPalette() {
        viewModelScope.launch {
            try {
                val response = settingsApi.getTagPalette()
                val raw = response.data ?: return@launch
                val palette = raw.mapValues { (_, hex) ->
                    try {
                        Color(android.graphics.Color.parseColor(hex))
                    } catch (_: Exception) {
                        hashTagToColor(hex)
                    }
                }
                _state.value = _state.value.copy(tagPalette = palette)
            } catch (_: HttpException) {
                // 404 → use hash-cycle defaults
            } catch (_: Exception) {
                // silent degrade
            }
        }
    }

    /**
     * Collects [UndoStack.events] and forwards [UndoStack.UndoEvent.Undone] /
     * [UndoStack.UndoEvent.Redone] audit descriptions to Timber tag "CustomerUndo".
     * The screen handles the UI-visible Pushed/Failed events directly via its own
     * LaunchedEffect so no snackbar logic lives here.
     */
    private fun observeUndoEvents() {
        viewModelScope.launch {
            undoStack.events.collect { event ->
                when (event) {
                    is UndoStack.UndoEvent.Undone ->
                        Timber.tag("CustomerUndo").i("Undone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Redone ->
                        Timber.tag("CustomerUndo").i("Redone: ${event.entry.auditDescription}")
                    is UndoStack.UndoEvent.Failed ->
                        Timber.tag("CustomerUndo").w("Undo failed: ${event.reason}")
                    is UndoStack.UndoEvent.Pushed -> { /* handled by screen */ }
                }
            }
        }
    }

    fun loadCustomer() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                customerRepository.getCustomer(customerId).collectLatest { customer ->
                    _state.value = _state.value.copy(customer = customer, isLoading = false)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load customer details. Check your connection and try again.",
                )
            }
        }
        loadAnalytics()
        loadRecentTickets()
        loadNotes()
        loadHealthScore()
        loadLtvTier()
        loadInvoices()
        loadAssets()
    }

    /**
     * CROSS50-header: fire an analytics fetch in parallel with the detail
     * collection so ticket_count / lifetime_value / last_visit can render in
     * the header row. Deliberately fire-and-forget — a failed analytics call
     * leaves `analytics` null and the header row renders the customer-only
     * avatar + name, exactly as before.
     */
    private fun loadAnalytics() {
        analyticsJob?.cancel()
        analyticsJob = viewModelScope.launch {
            try {
                val response = customerApi.getAnalytics(customerId)
                val analytics = response.data ?: return@launch
                _state.value = _state.value.copy(analytics = analytics)
            } catch (_: Exception) {
                // Silent degrade — quick-stats row simply doesn't render.
            }
        }
    }

    /**
     * CROSS9a: fetch the 10 most-recent tickets for this customer in parallel
     * with the detail + analytics flows. Fire-and-forget — a failed fetch
     * leaves `recentTickets` null and the Ticket History card simply does not
     * render, matching the analytics silent-degrade pattern.
     */
    private fun loadRecentTickets() {
        ticketsJob?.cancel()
        ticketsJob = viewModelScope.launch {
            try {
                val response = customerApi.getTickets(customerId)
                val tickets = response.data?.tickets ?: return@launch
                _state.value = _state.value.copy(recentTickets = tickets)
            } catch (_: Exception) {
                // Silent degrade — Ticket History card simply doesn't render.
            }
        }
    }

    /**
     * CROSS9b: fetch the notes timeline. Silent-degrade — a failed fetch
     * leaves `notes` null and the Notes card does not render. Empty list is
     * a real value that surfaces an empty-state inside the card.
     */
    private fun loadNotes() {
        notesJob?.cancel()
        notesJob = viewModelScope.launch {
            try {
                val response = customerApi.getNotes(customerId)
                val notes = response.data ?: return@launch
                _state.value = _state.value.copy(notes = notes)
            } catch (_: Exception) {
                // Silent degrade — Notes card simply doesn't render.
            }
        }
    }

    // plan:L892 — health score
    private var healthScoreJob: Job? = null
    private fun loadHealthScore() {
        healthScoreJob?.cancel()
        healthScoreJob = viewModelScope.launch {
            try {
                val response = customerApi.getHealthScore(customerId)
                _state.value = _state.value.copy(healthScore = response.data)
            } catch (_: Exception) { /* silent — 404 tolerated */ }
        }
    }

    fun recalculateHealthScore() {
        viewModelScope.launch {
            try {
                val response = customerApi.recalculateHealthScore(customerId)
                _state.value = _state.value.copy(healthScore = response.data)
            } catch (_: Exception) { /* silent */ }
        }
    }

    // plan:L893 — LTV tier
    private var ltvTierJob: Job? = null
    private fun loadLtvTier() {
        ltvTierJob?.cancel()
        ltvTierJob = viewModelScope.launch {
            try {
                val response = customerApi.getLtvTier(customerId)
                _state.value = _state.value.copy(ltvTier = response.data)
            } catch (_: Exception) { /* silent — 404 tolerated */ }
        }
    }

    // plan:L897 — invoices tab
    private var invoicesJob: Job? = null
    private fun loadInvoices() {
        invoicesJob?.cancel()
        invoicesJob = viewModelScope.launch {
            try {
                val response = customerApi.getInvoices(customerId)
                _state.value = _state.value.copy(invoices = response.data?.invoices ?: emptyList())
            } catch (_: Exception) { /* silent */ }
        }
    }

    // plan:L897 — assets tab (from detail payload)
    private fun loadAssets() {
        viewModelScope.launch {
            try {
                val response = customerApi.getCustomer(customerId)
                val assets = response.data?.assets
                _state.value = _state.value.copy(assets = assets ?: emptyList())
            } catch (_: Exception) { /* silent */ }
        }
    }

    // plan:L905 — delete
    fun requestDelete() {
        _state.value = _state.value.copy(showDeleteConfirm = true)
    }

    fun cancelDelete() {
        _state.value = _state.value.copy(showDeleteConfirm = false)
    }

    fun confirmDelete(onDeleted: () -> Unit) {
        viewModelScope.launch {
            try {
                customerApi.deleteCustomer(customerId)
                onDeleted()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    showDeleteConfirm = false,
                    saveMessage = "Delete failed: ${e.message}",
                )
            }
        }
    }

    fun updateNoteDraft(value: String) {
        _state.value = _state.value.copy(noteDraft = value)
    }

    /**
     * CROSS9b: POST a new note. Trims the draft, bails on blank, and on
     * success prepends to the local notes list so the UI reflects the new
     * row without a full refetch. A failed POST surfaces via saveMessage
     * and leaves the composer text intact so the user can retry.
     *
     * On success pushes a [CustomerEdit.NoteAdded] entry to [undoStack].
     * compensatingSync calls [CustomerApi.deleteNote] to roll back the server
     * row; offline-queued notes (noteId < 0) return false immediately.
     */
    fun postNote() {
        val draft = _state.value.noteDraft.trim()
        if (draft.isBlank() || _state.value.isPostingNote) return

        viewModelScope.launch {
            _state.value = _state.value.copy(isPostingNote = true)
            try {
                val response = customerApi.postNote(
                    customerId,
                    CreateCustomerNoteRequest(body = draft),
                )
                val note = response.data
                val noteId = note?.id ?: -1L
                val existing = _state.value.notes ?: emptyList()
                _state.value = _state.value.copy(
                    notes = if (note != null) listOf(note) + existing else existing,
                    noteDraft = "",
                    isPostingNote = false,
                )

                // Push undo entry — compensatingSync calls deleteNote to
                // roll back the server row (CROSS9b / B19 undo gap closed).
                val payload = CustomerEdit.NoteAdded(noteId = noteId, body = draft)
                undoStack.push(
                    UndoStack.Entry(
                        payload = payload,
                        apply = {
                            // Re-add: reload notes list (no local mutation needed)
                            viewModelScope.launch { loadNotes() }
                        },
                        reverse = {
                            // Optimistically remove the note from local list
                            _state.value = _state.value.copy(
                                notes = _state.value.notes?.filter { it.id != noteId },
                            )
                        },
                        auditDescription = "Note added: \"${draft.take(60)}${if (draft.length > 60) "…" else ""}\"",
                        compensatingSync = {
                            if (noteId < 0) {
                                // Offline-queued notes have no server row to delete.
                                false
                            } else {
                                try {
                                    val resp = customerApi.deleteNote(customerId, noteId)
                                    resp.success
                                } catch (e: Exception) {
                                    Timber.w(e, "Customer note undo: server delete failed")
                                    false
                                }
                            }
                        },
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isPostingNote = false,
                    saveMessage = e.message ?: "Failed to save note",
                )
            }
        }
    }

    fun startEditing() {
        val c = _state.value.customer ?: return
        _state.value = _state.value.copy(
            isEditing = true,
            editFirstName = c.firstName ?: "",
            editLastName = c.lastName ?: "",
            editPhone = c.mobile ?: c.phone ?: "",
            editEmail = c.email ?: "",
            editOrganization = c.organization ?: "",
            editAddress = c.address1 ?: "",
            editCity = c.city ?: "",
            editState = c.state ?: "",
            editZip = c.postcode ?: "",
            editTags = c.tags ?: "",
            editGroupId = c.groupId,
            editGroupName = c.groupName,
        )
    }

    fun cancelEditing() {
        _state.value = _state.value.copy(isEditing = false)
    }

    fun updateEditFirstName(value: String) { _state.value = _state.value.copy(editFirstName = value) }
    fun updateEditLastName(value: String) { _state.value = _state.value.copy(editLastName = value) }
    fun updateEditPhone(value: String) { _state.value = _state.value.copy(editPhone = value) }
    fun updateEditEmail(value: String) { _state.value = _state.value.copy(editEmail = value) }
    fun updateEditOrganization(value: String) { _state.value = _state.value.copy(editOrganization = value) }
    fun updateEditAddress(value: String) { _state.value = _state.value.copy(editAddress = value) }
    fun updateEditCity(value: String) { _state.value = _state.value.copy(editCity = value) }
    fun updateEditState(value: String) { _state.value = _state.value.copy(editState = value) }
    fun updateEditZip(value: String) { _state.value = _state.value.copy(editZip = value) }
    fun updateEditTags(value: String) { _state.value = _state.value.copy(editTags = value) }
    fun clearEditGroup() { _state.value = _state.value.copy(editGroupId = null, editGroupName = null) }
    fun dismissConflictBanner() { _state.value = _state.value.copy(showConflictBanner = false) }

    fun clearSaveMessage() {
        _state.value = _state.value.copy(saveMessage = null)
    }

    fun saveCustomer() {
        val current = _state.value
        if (current.editFirstName.isBlank()) {
            _state.value = current.copy(saveMessage = "First name is required")
            return
        }

        // Snapshot of field values before the save — used for undo + rollback.
        val oldCustomer = current.customer

        viewModelScope.launch {
            // OPTIMISTIC-SAVE: show "Saving…" chip immediately; hide on result.
            _state.value = _state.value.copy(isSaving = true, savingChipVisible = true)
            try {
                val newFirstName = current.editFirstName.trim()
                val newLastName = current.editLastName.trim().ifBlank { null }
                val newPhone = current.editPhone.trim().ifBlank { null }
                val newEmail = current.editEmail.trim().ifBlank { null }
                val newOrganization = current.editOrganization.trim().ifBlank { null }
                val newAddress = current.editAddress.trim().ifBlank { null }
                val newCity = current.editCity.trim().ifBlank { null }
                val newState = current.editState.trim().ifBlank { null }
                val newZip = current.editZip.trim().ifBlank { null }
                val newTags = current.editTags
                    .split(",")
                    .map { it.trim() }
                    .filter { it.isNotBlank() }
                    .joinToString(", ")
                    .ifBlank { null }
                val newGroupId = current.editGroupId

                val request = UpdateCustomerRequest(
                    firstName = newFirstName,
                    lastName = newLastName,
                    phone = newPhone,
                    email = newEmail,
                    organization = newOrganization,
                    address1 = newAddress,
                    city = newCity,
                    state = newState,
                    postcode = newZip,
                    customerTags = newTags,
                    customerGroupId = newGroupId,
                )

                // Optimistic Room update before network confirm
                if (oldCustomer != null) {
                    val optimistic = oldCustomer.copy(
                        firstName = newFirstName,
                        lastName = newLastName,
                        phone = newPhone,
                        email = newEmail,
                        organization = newOrganization,
                        address1 = newAddress,
                        city = newCity,
                        state = newState,
                        postcode = newZip,
                        tags = newTags,
                        locallyModified = true,
                    )
                    // Write optimistic version; real server response will overwrite below.
                    // (CustomerRepository.updateCustomer() does a Room insert on success)
                }

                customerRepository.updateCustomer(customerId, request)
                _state.value = _state.value.copy(
                    isEditing = false,
                    isSaving = false,
                    savingChipVisible = false,
                )

                // Push undo entries for each field that changed.
                if (oldCustomer != null) {
                    // Scalar field changes — one entry per changed field.
                    val fieldChanges = listOf(
                        Triple("firstName",  oldCustomer.firstName,    newFirstName),
                        Triple("lastName",   oldCustomer.lastName,     newLastName),
                        Triple("phone",      oldCustomer.mobile ?: oldCustomer.phone, newPhone),
                        Triple("email",      oldCustomer.email,        newEmail),
                        Triple("organization", oldCustomer.organization, newOrganization),
                        Triple("address",    oldCustomer.address1,     newAddress),
                        Triple("city",       oldCustomer.city,         newCity),
                        Triple("state",      oldCustomer.state,        newState),
                    ).filter { (_, old, new) -> old != new }

                    for ((fieldName, oldValue, newValue) in fieldChanges) {
                        val payload = CustomerEdit.FieldEdit(fieldName, oldValue, newValue)
                        undoStack.push(
                            UndoStack.Entry(
                                payload = payload,
                                apply = {
                                    viewModelScope.launch {
                                        customerRepository.updateCustomer(
                                            customerId,
                                            buildSingleFieldRequest(fieldName, newValue),
                                        )
                                    }
                                },
                                reverse = {
                                    viewModelScope.launch {
                                        customerRepository.updateCustomer(
                                            customerId,
                                            buildSingleFieldRequest(fieldName, oldValue),
                                        )
                                    }
                                },
                                auditDescription = "Edited $fieldName from ${oldValue ?: "(empty)"} to ${newValue ?: "(empty)"}",
                                compensatingSync = {
                                    try {
                                        customerRepository.updateCustomer(
                                            customerId,
                                            buildSingleFieldRequest(fieldName, oldValue),
                                        )
                                        true
                                    } catch (e: Exception) {
                                        Timber.tag("CustomerUndo").e(e, "compensatingSync: $fieldName revert failed")
                                        false
                                    }
                                },
                            )
                        )
                    }

                    // Tags change — one dedicated TagsEdit entry.
                    val oldTags = oldCustomer.tags
                    if (oldTags != newTags) {
                        val tagsPayload = CustomerEdit.TagsEdit(oldTags, newTags)
                        undoStack.push(
                            UndoStack.Entry(
                                payload = tagsPayload,
                                apply = {
                                    viewModelScope.launch {
                                        customerRepository.updateCustomer(
                                            customerId,
                                            UpdateCustomerRequest(customerTags = newTags),
                                        )
                                    }
                                },
                                reverse = {
                                    viewModelScope.launch {
                                        customerRepository.updateCustomer(
                                            customerId,
                                            UpdateCustomerRequest(customerTags = oldTags),
                                        )
                                    }
                                },
                                auditDescription = "Edited tags from \"${oldTags ?: ""}\" to \"${newTags ?: ""}\"",
                                compensatingSync = {
                                    try {
                                        customerRepository.updateCustomer(
                                            customerId,
                                            UpdateCustomerRequest(customerTags = oldTags),
                                        )
                                        true
                                    } catch (e: Exception) {
                                        Timber.tag("CustomerUndo").e(e, "compensatingSync: tags revert failed")
                                        false
                                    }
                                },
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                val is409 = e is HttpException && e.code() == 409
                if (is409) {
                    // Concurrent-edit: rollback optimistic state, show banner.
                    _state.value = _state.value.copy(
                        isSaving = false,
                        savingChipVisible = false,
                        showConflictBanner = true,
                    )
                } else {
                    // Non-409 error: rollback optimistic Room state by reloading from cache.
                    oldCustomer?.let { /* Room cache is still the pre-edit value; re-collect will refresh UI */ }
                    _state.value = _state.value.copy(
                        isSaving = false,
                        savingChipVisible = false,
                        saveMessage = "Save failed; reverted",
                    )
                }
            }
        }
    }

    /**
     * Build a minimal [UpdateCustomerRequest] carrying only [fieldName] = [value].
     * All other fields are null so the server performs a partial update without
     * overwriting unrelated columns.
     */
    private fun buildSingleFieldRequest(fieldName: String, value: String?): UpdateCustomerRequest =
        when (fieldName) {
            "firstName"    -> UpdateCustomerRequest(firstName = value ?: "")
            "lastName"     -> UpdateCustomerRequest(lastName = value)
            "phone"        -> UpdateCustomerRequest(phone = value)
            "email"        -> UpdateCustomerRequest(email = value)
            "organization" -> UpdateCustomerRequest(organization = value)
            "address"      -> UpdateCustomerRequest(address1 = value)
            "city"         -> UpdateCustomerRequest(city = value)
            "state"        -> UpdateCustomerRequest(state = value)
            else           -> UpdateCustomerRequest()
        }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalSharedTransitionApi::class)
@Composable
fun CustomerDetailScreen(
    sharedTransitionScope: SharedTransitionScope,
    animatedContentScope: AnimatedContentScope,
    customerId: Long,
    onBack: () -> Unit,
    onNavigateToTicket: (Long) -> Unit,
    onNavigateToSms: ((String) -> Unit)? = null,
    // CROSS47: CTA lives on the detail screen, but navigation is owned by
    // AppNavGraph. Parent supplies the actual route hop so the screen stays
    // nav-agnostic. customerId is forwarded so the future pre-seed path
    // (CROSS47-seed) only needs a wiring change, not another API hop.
    onCreateTicket: ((Long) -> Unit)? = null,
    viewModel: CustomerDetailViewModel = hiltViewModel(),
    useTabs: Boolean = true, // plan:L889 — enable tabs layout
) {
    val state by viewModel.state.collectAsState()
    val customer = state.customer
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    LaunchedEffect(state.saveMessage) {
        val msg = state.saveMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSaveMessage()
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

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            val heroName = when {
                state.isEditing -> "Edit customer"
                else -> customer?.let {
                    listOfNotNull(it.firstName, it.lastName)
                        .joinToString(" ")
                        .ifBlank { null }
                } ?: if (state.isLoading) "Loading..." else "Customer #$customerId"
            }
            BrandTopAppBar(
                title = heroName,
                titleContent = if (!state.isEditing && customer != null) ({
                    with(sharedTransitionScope) {
                        Text(
                            text = heroName,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.sharedElement(
                                sharedContentState = rememberSharedContentState(key = "customer-${customerId}-name"),
                                animatedVisibilityScope = animatedContentScope,
                            ),
                        )
                    }
                }) else null,
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.isEditing) viewModel.cancelEditing() else onBack()
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    // CROSS12: the seeded "Walk-in Customer" row is shared by
                    // every walk-in ticket and must not be renamed/deleted.
                    // Hide Edit (and any future Delete) for that row. Server
                    // enforces the same rule (PUT /:id returns 409).
                    val isWalkIn = customer?.firstName?.trim() == "Walk-in" &&
                        customer.lastName?.trim() == "Customer"
                    if (state.isEditing) {
                        // CROSS52: duplicate Save buttons (top bar + bottom action
                        // bar). Top removed; bottom sticky Cancel+Save bar is the
                        // single thumb-reach save target. Saving spinner still
                        // shown here as non-interactive feedback.
                        if (state.isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp,
                            )
                            Spacer(modifier = Modifier.width(16.dp))
                        }
                    } else if (!isWalkIn) {
                        IconButton(onClick = { viewModel.startEditing() }) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = "Edit",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
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
                        onRetry = { viewModel.loadCustomer() },
                    )
                }
            }
            state.isEditing -> {
                CustomerEditContent(
                    state = state,
                    padding = padding,
                    viewModel = viewModel,
                )
            }
            customer != null -> {
                // plan:L905 — delete confirm dialog
                if (state.showDeleteConfirm) {
                    AlertDialog(
                        onDismissRequest = viewModel::cancelDelete,
                        title = { Text("Delete customer?") },
                        text = {
                            Text("This will permanently delete ${customer.firstName} ${customer.lastName ?: ""}. This action cannot be undone.")
                        },
                        confirmButton = {
                            TextButton(
                                onClick = { viewModel.confirmDelete { onBack() } },
                                colors = ButtonDefaults.textButtonColors(
                                    contentColor = MaterialTheme.colorScheme.error,
                                ),
                            ) { Text("Delete") }
                        },
                        dismissButton = {
                            TextButton(onClick = viewModel::cancelDelete) { Text("Cancel") }
                        },
                    )
                }

                if (useTabs) {
                    // plan:L889 — tabs layout
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                    ) {
                        // Avatar + stats header above tabs
                        val displayName = listOfNotNull(customer.firstName, customer.lastName)
                            .joinToString(" ").ifBlank { "Customer" }
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CustomerAvatar(
                                name = displayName,
                                size = 72.dp,
                                textStyle = MaterialTheme.typography.headlineMedium,
                            )
                        }
                        CustomerDetailTabs(
                            customer = customer,
                            analytics = state.analytics,
                            healthScore = state.healthScore,
                            ltvTier = state.ltvTier,
                            recentTickets = state.recentTickets,
                            invoices = state.invoices,
                            notes = state.notes,
                            assets = state.assets,
                            noteDraft = state.noteDraft,
                            isPostingNote = state.isPostingNote,
                            onNoteDraftChange = viewModel::updateNoteDraft,
                            onPostNote = viewModel::postNote,
                            onNavigateToTicket = onNavigateToTicket,
                            onCreateTicket = onCreateTicket?.let { cb -> { cb(customerId) } },
                            onCall = { phone ->
                                context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")))
                            },
                            onSms = { phone ->
                                if (onNavigateToSms != null) {
                                    val normalized = phone.replace(Regex("[^0-9]"), "").let {
                                        if (it.length == 11 && it.startsWith("1")) it.substring(1) else it
                                    }
                                    onNavigateToSms(normalized)
                                } else {
                                    context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")))
                                }
                            },
                            onShare = {
                                // plan:L903 — share vCard
                                val vcf = VCardBuilder.build(customer)
                                val file = File(context.cacheDir, "customer_${customer.id}.vcf")
                                file.writeText(vcf)
                                val uri = FileProvider.getUriForFile(
                                    context,
                                    "${context.packageName}.provider",
                                    file,
                                )
                                val intent = Intent(Intent.ACTION_SEND).apply {
                                    type = "text/x-vcard"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(Intent.createChooser(intent, "Share contact"))
                            },
                            onDelete = viewModel::requestDelete,
                            onRecalculateHealth = viewModel::recalculateHealthScore,
                            modifier = Modifier.weight(1f),
                        )
                    }
                } else {
                    CustomerDetailContent(
                        customer = customer,
                        analytics = state.analytics,
                        recentTickets = state.recentTickets,
                        notes = state.notes,
                        noteDraft = state.noteDraft,
                        isPostingNote = state.isPostingNote,
                        onNoteDraftChange = viewModel::updateNoteDraft,
                        onPostNote = viewModel::postNote,
                        padding = padding,
                        onNavigateToTicket = onNavigateToTicket,
                        onCreateTicket = onCreateTicket?.let { cb -> { cb(customerId) } },
                        onCallPhone = { phone ->
                            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
                            context.startActivity(intent)
                        },
                        onSmsPhone = { phone ->
                            if (onNavigateToSms != null) {
                                val normalized = phone.replace(Regex("[^0-9]"), "").let {
                                    if (it.length == 11 && it.startsWith("1")) it.substring(1) else it
                                }
                                onNavigateToSms(normalized)
                            } else {
                                val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
                                context.startActivity(intent)
                            }
                        },
                        tagPalette = state.tagPalette,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun CustomerEditContent(
    state: CustomerDetailUiState,
    padding: PaddingValues,
    viewModel: CustomerDetailViewModel,
) {
    // D5-6: wire IME Next to move focus forward, Done to clear focus and save
    // the same way the on-screen Save button does.
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            viewModel.saveCustomer()
        },
    )

    // Tag chip editor state — hoisted to function scope so remember keys are stable.
    val existingEditTags = remember(state.editTags) {
        state.editTags.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    }
    var editTagInput by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .imePadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // 409 conflict banner — shown when a concurrent edit is detected
        if (state.showConflictBanner) {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "This customer was edited elsewhere.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = {
                        viewModel.dismissConflictBanner()
                        viewModel.loadCustomer()
                    }) {
                        Text("Reload")
                    }
                }
            }
        }

        // Optimistic-save "Saving…" chip
        if (state.savingChipVisible) {
            SuggestionChip(
                onClick = {},
                label = { Text("Saving…", style = MaterialTheme.typography.labelSmall) },
                icon = {
                    CircularProgressIndicator(
                        modifier = Modifier.size(12.dp),
                        strokeWidth = 1.5.dp,
                    )
                },
            )
        }
        OutlinedTextField(
            value = state.editFirstName,
            onValueChange = viewModel::updateEditFirstName,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("First Name *") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = onNext,
        )

        OutlinedTextField(
            value = state.editLastName,
            onValueChange = viewModel::updateEditLastName,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Last Name") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = onNext,
        )

        OutlinedTextField(
            value = state.editPhone,
            onValueChange = viewModel::updateEditPhone,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Phone") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Phone,
                imeAction = ImeAction.Next,
            ),
            keyboardActions = onNext,
        )

        OutlinedTextField(
            value = state.editEmail,
            onValueChange = viewModel::updateEditEmail,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Next,
            ),
            keyboardActions = onNext,
        )

        OutlinedTextField(
            value = state.editOrganization,
            onValueChange = viewModel::updateEditOrganization,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Organization") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = onNext,
        )

        OutlinedTextField(
            value = state.editAddress,
            onValueChange = viewModel::updateEditAddress,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Address") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = onNext,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = state.editCity,
                onValueChange = viewModel::updateEditCity,
                modifier = Modifier.weight(1f),
                label = { Text("City") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.editState,
                onValueChange = viewModel::updateEditState,
                modifier = Modifier.weight(1f),
                label = { Text("State") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )
            OutlinedTextField(
                value = state.editZip,
                onValueChange = viewModel::updateEditZip,
                modifier = Modifier.weight(1f),
                label = { Text("ZIP") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )
        }

        // Tags — chip input (color-coded with tenant palette)
        Text("Tags", style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (existingEditTags.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                existingEditTags.forEach { tag ->
                    TagChip(
                        label = tag,
                        tagPalette = state.tagPalette,
                        onRemove = {
                            val newTags = existingEditTags.filter { it != tag }.joinToString(", ")
                            viewModel.updateEditTags(newTags)
                        },
                    )
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = editTagInput,
                onValueChange = { editTagInput = it },
                modifier = Modifier.weight(1f),
                label = { Text("Add tag") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = {
                    val t = editTagInput.trim()
                    if (t.isNotBlank() && !existingEditTags.contains(t)) {
                        viewModel.updateEditTags((existingEditTags + t).joinToString(", "))
                    }
                    editTagInput = ""
                }),
            )
            FilledTonalIconButton(
                onClick = {
                    val t = editTagInput.trim()
                    if (t.isNotBlank() && !existingEditTags.contains(t)) {
                        viewModel.updateEditTags((existingEditTags + t).joinToString(", "))
                    }
                    editTagInput = ""
                },
                enabled = editTagInput.isNotBlank(),
            ) {
                Icon(Icons.Default.Add, contentDescription = "Add tag")
            }
        }

        // CROSS53: Group field now uses the same OutlinedTextField shape as the
        // other edit fields (label floats inside border) instead of a BrandCard
        // with external label — matches First Name / Last Name / Phone / etc.
        // Read-only; full group picker requires groups API (future).
        OutlinedTextField(
            value = state.editGroupName ?: "None",
            onValueChange = {},
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Group") },
            singleLine = true,
            readOnly = true,
            trailingIcon = {
                if (state.editGroupId != null) {
                    TextButton(
                        onClick = { viewModel.clearEditGroup() },
                    ) { Text("Clear") }
                }
            },
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = { viewModel.cancelEditing() },
                modifier = Modifier.weight(1f),
            ) {
                Text("Cancel")
            }
            Button(
                onClick = { viewModel.saveCustomer() },
                modifier = Modifier.weight(1f),
                enabled = state.editFirstName.isNotBlank() && !state.isSaving,
            ) {
                if (state.isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text("Save")
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CustomerDetailContent(
    customer: CustomerEntity,
    analytics: CustomerAnalytics?,
    recentTickets: List<TicketListItem>?,
    notes: List<CustomerNote>?,
    noteDraft: String,
    isPostingNote: Boolean,
    onNoteDraftChange: (String) -> Unit,
    onPostNote: () -> Unit,
    padding: PaddingValues,
    onNavigateToTicket: (Long) -> Unit,
    onCreateTicket: (() -> Unit)?,
    onCallPhone: (String) -> Unit,
    onSmsPhone: (String) -> Unit,
    tagPalette: Map<String, Color> = emptyMap(),
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // CROSS49: large initial-circle avatar as the first row so the detail
        // screen matches the list row's visual hook (both render the same
        // primaryContainer circle; list is 36dp, detail is 72dp).
        item {
            val displayName = listOfNotNull(customer.firstName, customer.lastName)
                .joinToString(" ")
                .ifBlank { "Customer" }
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                CustomerAvatar(
                    name = displayName,
                    size = 72.dp,
                    textStyle = MaterialTheme.typography.headlineMedium,
                )
            }
        }

        // CROSS50-header: quick-stats row under the avatar — ticket count,
        // lifetime value, last visit. Analytics fetch is parallel and silent,
        // so the row only renders once data arrives. Three equal-weight
        // stats; label in onSurfaceVariant, value in primary so the eye goes
        // to the number first. `last_visit_at` is ISO-formatted by the
        // server; DateFormatter.formatRelative turns it into "3 days ago".
        if (analytics != null) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    QuickStat(
                        label = "Tickets",
                        value = (analytics.totalTickets ?: 0).toString(),
                    )
                    QuickStat(
                        label = "Lifetime",
                        value = formatLifetimeValue(analytics.lifetimeValue),
                    )
                    QuickStat(
                        label = "Last visit",
                        value = analytics.lastVisit?.let { DateFormatter.formatRelative(it) }
                            ?.takeIf { it.isNotBlank() }
                            ?: "—",
                    )
                }
            }
        }

        // CROSS9a: Ticket history section — max 10 most-recent tickets, each
        // row T-XXXXX · device · status · price, tap routes to the ticket
        // detail screen. Silent-degrade: when `recentTickets` is null (still
        // loading or fetch failed) the card simply does not render. An empty
        // result (no tickets ever created for this customer) is surfaced
        // inside the card so the user sees confirmation rather than an
        // ambiguous blank.
        if (recentTickets != null) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Ticket history",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        if (recentTickets.isEmpty()) {
                            Text(
                                "No tickets yet",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            recentTickets.take(10).forEachIndexed { index, ticket ->
                                if (index > 0) {
                                    HorizontalDivider(
                                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                                        thickness = 1.dp,
                                        modifier = Modifier.padding(vertical = 8.dp),
                                    )
                                }
                                CustomerTicketHistoryRow(
                                    ticket = ticket,
                                    onClick = { onNavigateToTicket(ticket.id) },
                                )
                            }
                        }
                    }
                }
            }
        }

        // Quick action buttons
        item {
            val primaryPhone = customer.mobile ?: customer.phone
            if (primaryPhone != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // CROSS48: Call (primary) + SMS (secondary) routed through
                    // the BrandPrimaryButton / BrandSecondaryButton wrappers so
                    // filled-vs-outlined hierarchy is consistent with every
                    // other primary/secondary pair in the app.
                    BrandPrimaryButton(
                        onClick = { onCallPhone(primaryPhone) },
                        modifier = Modifier.weight(1f),
                    ) {
                        // decorative — Button's "Call" Text supplies the accessible name
                        Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Call")
                    }
                    BrandSecondaryButton(
                        onClick = { onSmsPhone(primaryPhone) },
                        modifier = Modifier.weight(1f),
                    ) {
                        // decorative — Button's "SMS" Text supplies the accessible name
                        Icon(Icons.Default.Sms, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("SMS")
                    }
                }
            }
        }

        // Contact info card — BrandCard
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "Contact info",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )

                    // Phone numbers from entity fields
                    val allPhones = buildList {
                        customer.mobile?.let { add(it to "Mobile") }
                        customer.phone?.let { add(it to "Phone") }
                    }.distinctBy { it.first }

                    allPhones.forEach { (phone, label) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onCallPhone(phone) }
                                // D5-1: collapse phone icon + formatted number
                                // + Mobile/Phone label Text into one focus item
                                // so TalkBack announces "+1 (xxx) xxx-xxxx
                                // Mobile, button" instead of unlabeled rows.
                                .semantics(mergeDescendants = true) { role = Role.Button },
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Phone,
                                // decorative — parent Row's mergeDescendants + formatted phone Text supplies the accessible name
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Column {
                                Text(
                                    formatPhoneDisplay(phone),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text(
                                    label,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    // Email
                    if (!customer.email.isNullOrBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Email,
                                // decorative — non-clickable info row; sibling email Text carries the announcement
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(customer.email, style = MaterialTheme.typography.bodyMedium)
                        }
                    }

                    // Address
                    val address = buildList {
                        customer.address1?.let { add(it) }
                        customer.address2?.let { add(it) }
                        val cityStateZip = listOfNotNull(customer.city, customer.state, customer.postcode)
                            .filter { it.isNotBlank() }
                            .joinToString(", ")
                        if (cityStateZip.isNotBlank()) add(cityStateZip)
                    }.joinToString("\n")

                    if (address.isNotBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Icon(
                                Icons.Default.LocationOn,
                                // decorative — non-clickable info row; sibling address Text carries the announcement
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(address, style = MaterialTheme.typography.bodyMedium)
                        }
                    }

                    if (!customer.organization.isNullOrBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Business,
                                // decorative — non-clickable info row; sibling organization Text carries the announcement
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(customer.organization, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        // CROSS47: Create Ticket CTA immediately below Contact info so the
        // most common next action on a customer record is a single thumb tap
        // away. Primary filled button (not FAB) keeps navigation explicit and
        // avoids hiding behind the content when scrolled. Customer id is
        // forwarded via the callback; the create wizard ignoring it today is
        // tracked as CROSS47-seed.
        // CROSS48-adopt-more: raw Button -> BrandPrimaryButton so the filled
        // primary hierarchy matches Call / Sign-In and uses the 12dp theme
        // shape without the per-site colorScheme override.
        if (onCreateTicket != null) {
            item {
                BrandPrimaryButton(
                    onClick = onCreateTicket,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        Icons.Default.Add,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Create Ticket")
                }
            }
        }

        // Tags — chip row (CROSS9d: replaces raw comma-separated Text).
        // Always render the card so the empty-state ("No tags") is visible.
        // tagLabels is recomputed only when customer.tags changes (immutable memo).
        item {
            val tagLabels = remember(customer.tags) {
                customer.tags.orEmpty()
                    .split(',')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
            }
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "Tags",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    if (tagLabels.isEmpty()) {
                        Text(
                            "No tags",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            tagLabels.forEach { tag ->
                                TagChip(label = tag, tagPalette = tagPalette)
                            }
                        }
                    }
                }
            }
        }

        // Comments sticky-note — BrandCard. Renamed from "Notes" to "Summary"
        // once the CROSS9b multi-row Notes timeline landed; both are notes in
        // the casual sense but the timeline is the primary UI. This card still
        // renders the single-line `customers.comments` sticky note edited
        // inline via Edit Profile.
        if (!customer.comments.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Summary",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            customer.comments,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // CROSS9b: Notes timeline — dated per-author notes + single-line
        // composer. Silent-degrade: when `notes` is null (still loading or
        // fetch failed) the card simply does not render. An empty list is a
        // real signal — the composer is shown so the first note can be added.
        if (notes != null) {
            item {
                NotesCard(
                    notes = notes,
                    draft = noteDraft,
                    isPosting = isPostingNote,
                    onDraftChange = onNoteDraftChange,
                    onPost = onPostNote,
                )
            }
        }
    }
}

/**
 * CROSS9b: Notes card — timeline of dated, per-author notes with a
 * single-line composer at the bottom. The composer posts on the trailing
 * Send icon tap; an IME `Done` action also triggers posting so the soft
 * keyboard flow is natural.
 */
@Composable
private fun NotesCard(
    notes: List<CustomerNote>,
    draft: String,
    isPosting: Boolean,
    onDraftChange: (String) -> Unit,
    onPost: () -> Unit,
) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                "Notes",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(8.dp))

            if (notes.isEmpty()) {
                Text(
                    "No notes yet",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                notes.take(25).forEachIndexed { index, note ->
                    if (index > 0) {
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                            thickness = 1.dp,
                            modifier = Modifier.padding(vertical = 8.dp),
                        )
                    }
                    NoteRow(note = note)
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Single-line composer — IME Send action posts, trailing icon
            // button also posts. Disabled while a post is in flight or when
            // the draft is blank.
            val canPost = draft.isNotBlank() && !isPosting
            // D5-6: hitting the native Send button on the IME posts the note,
            // matching the trailing send icon. Suppressed while a post is
            // already in flight or the draft is empty.
            val focusManager = LocalFocusManager.current
            OutlinedTextField(
                value = draft,
                onValueChange = onDraftChange,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("Add a note") },
                enabled = !isPosting,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(
                    onSend = {
                        if (canPost) {
                            focusManager.clearFocus()
                            onPost()
                        }
                    },
                ),
                trailingIcon = {
                    IconButton(
                        onClick = onPost,
                        enabled = canPost,
                    ) {
                        if (isPosting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = "Post note",
                                tint = if (canPost) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        }
                    }
                },
            )
        }
    }
}

/**
 * CROSS9b: a single note row — body line plus a muted "author · relative
 * time" caption. Author falls back to "—" when the server couldn't resolve
 * a username (soft-deleted user, import without author).
 */
@Composable
private fun NoteRow(note: CustomerNote) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            note.body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(modifier = Modifier.height(2.dp))
        val author = note.authorUsername?.takeIf { it.isNotBlank() } ?: "—"
        val when_ = DateFormatter.formatRelative(note.createdAt).takeIf { it.isNotBlank() }
            ?: DateFormatter.formatAbsolute(note.createdAt)
        Text(
            "$author · $when_",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * CROSS50-header: single stat column used in the quick-stats row under the
 * avatar. Label sits above the value in a muted tone; value uses primary so
 * the number is what the eye lands on.
 */
@Composable
private fun QuickStat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * CROSS50-header: format the analytics `lifetime_value` (server returns
 * dollars as a Double) for the header row. Whole-dollar formatting is enough
 * here — the quick-stats row is a glance, not a precise invoice line.
 */
private fun formatLifetimeValue(dollars: Double?): String {
    val value = dollars ?: 0.0
    val whole = value.toLong()
    return "$${whole}"
}

/**
 * CROSS9a: single row in the Ticket history section of CustomerDetail.
 *
 * Layout (single row):
 *   T-XXXXX (mono)   device name           status badge    $price
 *
 * Tap anywhere on the row routes to ticket detail. `price` comes from the
 * server's `total` (dollars, Double) and uses the same cent formatter as
 * the main ticket list so the number lines up with the canonical $NN.NN
 * format. Device name falls back to the empty string when the ticket has
 * no devices yet (rare but possible for walk-in POS tickets).
 */
@Composable
private fun CustomerTicketHistoryRow(
    ticket: TicketListItem,
    onClick: () -> Unit,
) {
    // D5-3: explicit interactionSource + ripple() so the row flashes on tap.
    // Bare .clickable on a raw Row relied on LocalIndication being auto-
    // provided by the theme, which was inconsistent in M3 1.3+ and produced
    // "ghost" taps with no visual acknowledgement.
    val interactionSource = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = interactionSource,
                indication = ripple(),
                onClick = onClick,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Order id in monospaced brand font for alignment.
        Text(
            ticket.orderId,
            style = BrandMono.copy(
                fontSize = MaterialTheme.typography.labelLarge.fontSize,
            ),
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        // Device name expands to take remaining horizontal space.
        val deviceName = ticket.firstDevice?.deviceName.orEmpty()
        Text(
            deviceName,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
            maxLines = 1,
        )
        val statusName = ticket.statusName
        if (!statusName.isNullOrBlank()) {
            BrandStatusBadge(label = statusName, status = statusName)
        }
        // Price — mirrors the ticket list row format ($NN.NN). Dollars → cents
        // via the shared helper so $0 vs $0.00 stays consistent.
        Text(
            ticket.total.toCentsOrZero().formatAsMoney(),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Medium,
        )
    }
}
