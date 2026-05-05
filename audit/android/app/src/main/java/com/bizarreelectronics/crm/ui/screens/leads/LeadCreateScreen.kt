package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.CreateLeadRequest
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.repository.LeadRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

/** Keep this list in sync with LeadListScreen/LeadDetailScreen. */
private val CREATE_LEAD_STATUSES = listOf(
    "new", "contacted", "scheduled", "qualified", "proposal", "converted", "lost",
)

/** Source options for the source dropdown. */
private val LEAD_SOURCES = listOf("Web Form", "Phone", "Walk-in", "Referral", "Other")

/** Pipeline stage options. */
private val LEAD_STAGES = listOf("New", "Contacted", "Qualified", "Proposal", "Closed Won", "Closed Lost")

data class LeadCreateUiState(
    val firstName: String = "",
    val lastName: String = "",
    val phone: String = "",
    val email: String = "",
    val address: String = "",
    val zipCode: String = "",
    val source: String = "",
    val notes: String = "",
    val status: String = "new",
    // Extended fields (section 9 batch 1)
    /** Manual score override 0-100. Empty string = not set (server omits the field). */
    val scoreInput: String = "",
    val valueInput: String = "",
    val stage: String = "",
    val assignedTo: Long? = null,
    /** ISO date string "yyyy-MM-dd" or blank. */
    val followUpDate: String = "",
    /** Millis for the DatePickerState; kept in sync with followUpDate. */
    val followUpDateMillis: Long = System.currentTimeMillis(),
    val tags: List<String> = emptyList(),
    val tagInput: String = "",
    /** Fetched employee list for the assignee picker. */
    val employees: List<EmployeeListItem> = emptyList(),
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
    /** True when the create was queued offline. */
    val savedOffline: Boolean = false,
)

@HiltViewModel
class LeadCreateViewModel @Inject constructor(
    private val leadRepository: LeadRepository,
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _state = MutableStateFlow(LeadCreateUiState())
    val state = _state.asStateFlow()

    init {
        // Best-effort fetch of the employee list for the assignee picker.
        // Failure is silent — the dropdown simply shows empty (assignee stays unset).
        viewModelScope.launch {
            try {
                val response = settingsApi.getEmployees()
                val list = response.data ?: emptyList()
                _state.value = _state.value.copy(employees = list)
            } catch (_: Exception) { /* offline or auth — leave employees empty */ }
        }
    }

    fun updateFirstName(value: String) { _state.value = _state.value.copy(firstName = value) }
    fun updateLastName(value: String) { _state.value = _state.value.copy(lastName = value) }
    fun updatePhone(value: String) { _state.value = _state.value.copy(phone = value) }
    fun updateEmail(value: String) { _state.value = _state.value.copy(email = value) }
    fun updateAddress(value: String) { _state.value = _state.value.copy(address = value) }
    fun updateZipCode(value: String) { _state.value = _state.value.copy(zipCode = value) }

    fun updateSource(value: String) { _state.value = _state.value.copy(source = value) }
    fun updateNotes(value: String) { _state.value = _state.value.copy(notes = value) }
    fun updateStatus(value: String) { _state.value = _state.value.copy(status = value) }

    // Extended field updaters ──────────────────────────────────────────────────

    /** Only digits, 0-100. Rejects characters that would make the string invalid. */
    fun updateScoreInput(value: String) {
        if (value.isEmpty() || (value.all { it.isDigit() } && value.toIntOrNull() ?: 0 <= 100)) {
            _state.value = _state.value.copy(scoreInput = value)
        }
    }

    fun updateValueInput(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(valueInput = value)
        }
    }

    fun updateStage(value: String) { _state.value = _state.value.copy(stage = value) }
    fun updateAssignedTo(id: Long?) { _state.value = _state.value.copy(assignedTo = id) }

    /** Called from DatePickerDialog confirmation. */
    fun updateFollowUpDateMillis(millis: Long) {
        val localDate = Instant.ofEpochMilli(millis)
            .atZone(ZoneId.systemDefault())
            .toLocalDate()
        _state.value = _state.value.copy(
            followUpDateMillis = millis,
            followUpDate = localDate.toString(),
        )
    }

    fun updateTagInput(value: String) { _state.value = _state.value.copy(tagInput = value) }

    fun addTag() {
        val tag = _state.value.tagInput.trim()
        if (tag.isBlank()) return
        val current = _state.value
        if (tag !in current.tags) {
            _state.value = current.copy(tags = current.tags + tag, tagInput = "")
        } else {
            _state.value = current.copy(tagInput = "")
        }
    }

    fun removeTag(tag: String) {
        _state.value = _state.value.copy(tags = _state.value.tags - tag)
    }

    // ──────────────────────────────────────────────────────────────────────────

    fun clearError() { _state.value = _state.value.copy(error = null) }
    fun clearSavedOffline() { _state.value = _state.value.copy(savedOffline = false) }

    fun save() {
        val current = _state.value
        if (current.firstName.isBlank()) {
            _state.value = current.copy(error = "First name is required")
            return
        }
        if (current.phone.isBlank()) {
            _state.value = current.copy(error = "Phone is required")
            return
        }
        val scoreValue = current.scoreInput.toIntOrNull()
        if (current.scoreInput.isNotBlank() && (scoreValue == null || scoreValue < 0 || scoreValue > 100)) {
            _state.value = current.copy(error = "Score must be 0–100")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateLeadRequest(
                    firstName = current.firstName.trim(),
                    lastName = current.lastName.trim().ifBlank { null },
                    phone = current.phone.trim(),
                    email = current.email.trim().ifBlank { null },
                    address = current.address.trim().ifBlank { null },
                    zipCode = current.zipCode.trim().ifBlank { null },
                    source = current.source.trim().ifBlank { null },
                    notes = current.notes.trim().ifBlank { null },
                    status = current.status,
                    leadScore = scoreValue,
                    value = current.valueInput.toDoubleOrNull(),
                    stage = current.stage.ifBlank { null },
                    assignedTo = current.assignedTo,
                    followUpDate = current.followUpDate.ifBlank { null },
                    tags = current.tags.ifEmpty { null },
                )
                // LeadRepository.createLead already handles online/offline
                // transparently — offline path writes SyncQueueEntity and
                // returns a negative tempId.
                val createdId = leadRepository.createLead(request)
                val wasOffline = createdId < 0
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                    savedOffline = wasOffline,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create lead",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeadCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: LeadCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })

    // Dropdown expansion states (saved across rotation per U7)
    var statusDropdownExpanded by rememberSaveable { mutableStateOf(false) }
    var sourceDropdownExpanded by rememberSaveable { mutableStateOf(false) }
    var stageDropdownExpanded by rememberSaveable { mutableStateOf(false) }
    var assigneeDropdownExpanded by rememberSaveable { mutableStateOf(false) }

    // Follow-up date picker
    var showFollowUpDatePicker by rememberSaveable { mutableStateOf(false) }
    val followUpDatePickerState = rememberDatePickerState(
        initialSelectedDateMillis = state.followUpDateMillis,
    )

    // Score validation
    val scoreError = state.scoreInput.isNotEmpty() &&
        (state.scoreInput.toIntOrNull() == null ||
            state.scoreInput.toInt() < 0 ||
            state.scoreInput.toInt() > 100)

    val canSave = state.firstName.isNotBlank() && state.phone.isNotBlank() && !scoreError

    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) onCreated(id)
    }

    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    LaunchedEffect(state.savedOffline) {
        if (state.savedOffline) {
            snackbarHostState.showSnackbar("Saved offline; will sync when reconnected")
            viewModel.clearSavedOffline()
        }
    }

    // Follow-up date picker dialog
    if (showFollowUpDatePicker) {
        DatePickerDialog(
            onDismissRequest = { showFollowUpDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    followUpDatePickerState.selectedDateMillis?.let {
                        viewModel.updateFollowUpDateMillis(it)
                    }
                    showFollowUpDatePicker = false
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showFollowUpDatePicker = false }) { Text("Cancel") }
            },
        ) {
            DatePicker(state = followUpDatePickerState)
        }
    }

    // Assignee display name helper
    val assigneeName = state.employees.find { it.id == state.assignedTo }
        ?.let { listOfNotNull(it.firstName, it.lastName).joinToString(" ").ifBlank { it.username } }
        ?: ""

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("New Lead") },
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
                actions = {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(onClick = { viewModel.save() }, enabled = canSave) {
                            Text("Create")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Contact info ──────────────────────────────────────────────
            OutlinedTextField(
                value = state.firstName,
                onValueChange = viewModel::updateFirstName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("First Name *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.lastName,
                onValueChange = viewModel::updateLastName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Last Name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.phone,
                onValueChange = viewModel::updatePhone,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Phone *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Phone,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.email,
                onValueChange = viewModel::updateEmail,
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
                value = state.address,
                onValueChange = viewModel::updateAddress,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Address") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.zipCode,
                onValueChange = viewModel::updateZipCode,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("ZIP Code") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            // ── Status dropdown ────────────────────────────────────────────
            ExposedDropdownMenuBox(
                expanded = statusDropdownExpanded,
                onExpandedChange = { statusDropdownExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.status.replaceFirstChar { it.uppercase() },
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Status") },
                    trailingIcon = {
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    },
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = statusDropdownExpanded,
                    onDismissRequest = { statusDropdownExpanded = false },
                ) {
                    CREATE_LEAD_STATUSES.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option.replaceFirstChar { it.uppercase() }) },
                            onClick = {
                                viewModel.updateStatus(option)
                                statusDropdownExpanded = false
                            },
                        )
                    }
                }
            }

            // ── Source dropdown ────────────────────────────────────────────
            ExposedDropdownMenuBox(
                expanded = sourceDropdownExpanded,
                onExpandedChange = { sourceDropdownExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.source,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Source") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = sourceDropdownExpanded) },
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = sourceDropdownExpanded,
                    onDismissRequest = { sourceDropdownExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("— None —") },
                        onClick = {
                            viewModel.updateSource("")
                            sourceDropdownExpanded = false
                        },
                    )
                    LEAD_SOURCES.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option) },
                            onClick = {
                                viewModel.updateSource(option)
                                sourceDropdownExpanded = false
                            },
                        )
                    }
                }
            }

            // ── Stage dropdown ─────────────────────────────────────────────
            ExposedDropdownMenuBox(
                expanded = stageDropdownExpanded,
                onExpandedChange = { stageDropdownExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.stage,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Stage") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = stageDropdownExpanded) },
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = stageDropdownExpanded,
                    onDismissRequest = { stageDropdownExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("— None —") },
                        onClick = {
                            viewModel.updateStage("")
                            stageDropdownExpanded = false
                        },
                    )
                    LEAD_STAGES.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option) },
                            onClick = {
                                viewModel.updateStage(option)
                                stageDropdownExpanded = false
                            },
                        )
                    }
                }
            }

            // ── Assignee dropdown ──────────────────────────────────────────
            ExposedDropdownMenuBox(
                expanded = assigneeDropdownExpanded,
                onExpandedChange = { assigneeDropdownExpanded = it },
            ) {
                OutlinedTextField(
                    value = assigneeName,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Assignee") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = assigneeDropdownExpanded) },
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = assigneeDropdownExpanded,
                    onDismissRequest = { assigneeDropdownExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text("— Unassigned —") },
                        onClick = {
                            viewModel.updateAssignedTo(null)
                            assigneeDropdownExpanded = false
                        },
                    )
                    state.employees.forEach { emp ->
                        val name = listOfNotNull(emp.firstName, emp.lastName)
                            .joinToString(" ").ifBlank { emp.username ?: "Employee ${emp.id}" }
                        DropdownMenuItem(
                            text = { Text(name) },
                            onClick = {
                                viewModel.updateAssignedTo(emp.id)
                                assigneeDropdownExpanded = false
                            },
                        )
                    }
                }
            }

            // ── Score (manual override 0-100) ──────────────────────────────
            OutlinedTextField(
                value = state.scoreInput,
                onValueChange = viewModel::updateScoreInput,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Lead Score (0–100)") },
                placeholder = { Text("Auto-scored unless overridden") },
                singleLine = true,
                isError = scoreError,
                supportingText = if (scoreError) {
                    { Text("Must be 0–100") }
                } else null,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            // ── Value ($) ──────────────────────────────────────────────────
            OutlinedTextField(
                value = state.valueInput,
                onValueChange = viewModel::updateValueInput,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Estimated Value") },
                leadingIcon = { Text("$", color = MaterialTheme.colorScheme.onSurfaceVariant) },
                placeholder = { Text("0.00") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            // ── Follow-up date ─────────────────────────────────────────────
            OutlinedTextField(
                value = state.followUpDate.ifBlank { "" },
                onValueChange = {},
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Follow-up Date") },
                readOnly = true,
                trailingIcon = {
                    IconButton(onClick = { showFollowUpDatePicker = true }) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = "Pick follow-up date")
                    }
                },
                singleLine = true,
            )

            // ── Notes ──────────────────────────────────────────────────────
            OutlinedTextField(
                value = state.notes,
                onValueChange = viewModel::updateNotes,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Notes") },
                minLines = 3,
                maxLines = 6,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
            )

            // ── Tags chip input ────────────────────────────────────────────
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = state.tagInput,
                        onValueChange = viewModel::updateTagInput,
                        modifier = Modifier.weight(1f),
                        label = { Text("Add Tag") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = {
                            viewModel.addTag()
                            focusManager.clearFocus()
                        }),
                    )
                    FilledTonalButton(
                        onClick = { viewModel.addTag() },
                        enabled = state.tagInput.isNotBlank(),
                    ) {
                        Text("Add")
                    }
                }
                // Chip row for added tags
                if (state.tags.isNotEmpty()) {
                    androidx.compose.foundation.layout.FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        state.tags.forEach { tag ->
                            InputChip(
                                selected = false,
                                onClick = {},
                                label = { Text(tag) },
                                trailingIcon = {
                                    IconButton(
                                        onClick = { viewModel.removeTag(tag) },
                                        modifier = Modifier.size(18.dp),
                                    ) {
                                        Icon(
                                            Icons.Default.Close,
                                            contentDescription = "Remove tag $tag",
                                            modifier = Modifier.size(12.dp),
                                        )
                                    }
                                },
                            )
                        }
                    }
                }
            }

            // TODO: custom fields — skip until server schema is defined
        }
    }
}
