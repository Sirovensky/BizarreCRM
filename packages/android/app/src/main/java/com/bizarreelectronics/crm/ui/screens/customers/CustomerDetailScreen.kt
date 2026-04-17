package com.bizarreelectronics.crm.ui.screens.customers

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
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
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerAnalytics
import com.bizarreelectronics.crm.data.remote.dto.CustomerNote
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandSecondaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.CustomerAvatar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import com.bizarreelectronics.crm.util.toCentsOrZero
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

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
    /** Comma-separated tag list, matching the web app's Tags field. */
    val editTags: String = "",
    /** Currently assigned customer group id. Full group dropdown TBD; for now edit supports clearing. */
    val editGroupId: Long? = null,
    /** Display-only group name snapshot captured when editing begins. */
    val editGroupName: String? = null,
    val saveMessage: String? = null,
)

@HiltViewModel
class CustomerDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val customerRepository: CustomerRepository,
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val customerId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(CustomerDetailUiState())
    val state = _state.asStateFlow()
    private var collectJob: Job? = null
    private var analyticsJob: Job? = null
    private var ticketsJob: Job? = null
    private var notesJob: Job? = null

    init {
        loadCustomer()
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

    fun updateNoteDraft(value: String) {
        _state.value = _state.value.copy(noteDraft = value)
    }

    /**
     * CROSS9b: POST a new note. Trims the draft, bails on blank, and on
     * success prepends to the local notes list so the UI reflects the new
     * row without a full refetch. A failed POST surfaces via saveMessage
     * and leaves the composer text intact so the user can retry.
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
                val existing = _state.value.notes ?: emptyList()
                _state.value = _state.value.copy(
                    notes = if (note != null) listOf(note) + existing else existing,
                    noteDraft = "",
                    isPostingNote = false,
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
    fun updateEditTags(value: String) { _state.value = _state.value.copy(editTags = value) }
    fun clearEditGroup() { _state.value = _state.value.copy(editGroupId = null, editGroupName = null) }

    fun clearSaveMessage() {
        _state.value = _state.value.copy(saveMessage = null)
    }

    fun saveCustomer() {
        val current = _state.value
        if (current.editFirstName.isBlank()) {
            _state.value = current.copy(saveMessage = "First name is required")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true)
            try {
                val request = UpdateCustomerRequest(
                    firstName = current.editFirstName.trim(),
                    lastName = current.editLastName.trim().ifBlank { null },
                    phone = current.editPhone.trim().ifBlank { null },
                    email = current.editEmail.trim().ifBlank { null },
                    organization = current.editOrganization.trim().ifBlank { null },
                    address1 = current.editAddress.trim().ifBlank { null },
                    city = current.editCity.trim().ifBlank { null },
                    state = current.editState.trim().ifBlank { null },
                    customerTags = current.editTags
                        .split(",")
                        .map { it.trim() }
                        .filter { it.isNotBlank() }
                        .joinToString(", ")
                        .ifBlank { null },
                    customerGroupId = current.editGroupId,
                )
                customerRepository.updateCustomer(customerId, request)
                _state.value = _state.value.copy(
                    isEditing = false,
                    isSaving = false,
                    saveMessage = "Customer updated",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveMessage = e.message ?: "Failed to update customer",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerDetailScreen(
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
) {
    val state by viewModel.state.collectAsState()
    val customer = state.customer
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.saveMessage) {
        val msg = state.saveMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSaveMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = when {
                    state.isEditing -> "Edit customer"
                    else -> customer?.let {
                        listOfNotNull(it.firstName, it.lastName)
                            .joinToString(" ")
                            .ifBlank { null }
                    } ?: if (state.isLoading) "Loading..." else "Customer #$customerId"
                },
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
                )
            }
        }
    }
}

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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .imePadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
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
        }

        // Tags (comma-separated)
        OutlinedTextField(
            value = state.editTags,
            onValueChange = viewModel::updateEditTags,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Tags") },
            // CROSS56: replace dev-placeholder "tag1, tag2, tag3" with
            // tenant-relevant examples so the hint reads as guidance not leftover.
            placeholder = { Text("VIP, corporate, loyalty") },
            supportingText = { Text("Comma-separated") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = onDoneSave,
        )

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

        // Tags — BrandCard
        if (!customer.tags.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Tags",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            customer.tags,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
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
