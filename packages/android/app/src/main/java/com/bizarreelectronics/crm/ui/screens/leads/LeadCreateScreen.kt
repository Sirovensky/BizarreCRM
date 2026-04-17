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
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.CreateLeadRequest
import com.bizarreelectronics.crm.data.repository.LeadRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Keep this list in sync with LeadListScreen/LeadDetailScreen. */
private val CREATE_LEAD_STATUSES = listOf(
    "new", "contacted", "scheduled", "qualified", "proposal", "converted", "lost",
)

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
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

@HiltViewModel
class LeadCreateViewModel @Inject constructor(
    private val leadRepository: LeadRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(LeadCreateUiState())
    val state = _state.asStateFlow()

    fun updateFirstName(value: String) {
        _state.value = _state.value.copy(firstName = value)
    }

    fun updateLastName(value: String) {
        _state.value = _state.value.copy(lastName = value)
    }

    fun updatePhone(value: String) {
        _state.value = _state.value.copy(phone = value)
    }

    fun updateEmail(value: String) {
        _state.value = _state.value.copy(email = value)
    }

    fun updateAddress(value: String) {
        _state.value = _state.value.copy(address = value)
    }

    fun updateZipCode(value: String) {
        _state.value = _state.value.copy(zipCode = value)
    }

    fun updateSource(value: String) {
        _state.value = _state.value.copy(source = value)
    }

    fun updateNotes(value: String) {
        _state.value = _state.value.copy(notes = value)
    }

    fun updateStatus(value: String) {
        _state.value = _state.value.copy(status = value)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

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
                )
                val createdId = leadRepository.createLead(request)
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
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
    // U7 fix: dropdown expansion state saved across rotation.
    var statusDropdownExpanded by rememberSaveable { mutableStateOf(false) }
    // D5-6: wire IME Next so tapping the native keyboard "Next" glyph moves
    // focus through the form instead of doing nothing.
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })

    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) {
            onCreated(id)
        }
    }

    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

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
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = state.firstName.isNotBlank() && state.phone.isNotBlank(),
                        ) {
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

            OutlinedTextField(
                value = state.source,
                onValueChange = viewModel::updateSource,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Source") },
                placeholder = { Text("e.g. Website, Walk-in, Google") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            // Status dropdown — no per-option color; theme handles active states
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
                        // decorative — dropdown chevron inside a labeled ExposedDropdownMenuBox TextField; the label "Status" announces the purpose
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
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

            OutlinedTextField(
                value = state.notes,
                onValueChange = viewModel::updateNotes,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Notes") },
                minLines = 3,
                maxLines = 6,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
            )
        }
    }
}
