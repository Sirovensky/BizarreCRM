package com.bizarreelectronics.crm.ui.screens.customers

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CustomerCreateUiState(
    val firstName: String = "",
    val lastName: String = "",
    val phone: String = "",
    val email: String = "",
    val organization: String = "",
    val address: String = "",
    val city: String = "",
    val state: String = "",
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

@HiltViewModel
class CustomerCreateViewModel @Inject constructor(
    private val customerRepository: CustomerRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomerCreateUiState())
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

    fun updateOrganization(value: String) {
        _state.value = _state.value.copy(organization = value)
    }

    fun updateAddress(value: String) {
        _state.value = _state.value.copy(address = value)
    }

    fun updateCity(value: String) {
        _state.value = _state.value.copy(city = value)
    }

    fun updateState(value: String) {
        _state.value = _state.value.copy(state = value)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun save() {
        val current = _state.value
        // N7 fix: mirror server-side validation so users get a clear error
        // BEFORE a round trip to a server that will reject the payload.
        // - firstName: required, non-blank after trim, max 255 chars
        // - email: if provided, must match the server's regex
        // - phone: if provided, must be 10–15 digits after stripping symbols
        val trimmedFirstName = current.firstName.trim()
        if (trimmedFirstName.isEmpty()) {
            _state.value = current.copy(error = "First name is required")
            return
        }
        if (trimmedFirstName.length > 255) {
            _state.value = current.copy(error = "First name is too long (max 255 characters)")
            return
        }

        val trimmedEmail = current.email.trim()
        if (trimmedEmail.isNotEmpty()) {
            if (trimmedEmail.length > 254) {
                _state.value = current.copy(error = "Email is too long")
                return
            }
            // Match server regex (packages/server/src/utils/validate.ts).
            val emailRegex = Regex(
                "^[^\\s@.]+(?:\\.[^\\s@.]+)*@[^\\s@.]+(?:\\.[^\\s@.]+)*\\.[^\\s@.]{2,}$",
            )
            if (!emailRegex.matches(trimmedEmail.lowercase())) {
                _state.value = current.copy(error = "Enter a valid email address")
                return
            }
        }

        val trimmedPhone = current.phone.trim()
        if (trimmedPhone.isNotEmpty()) {
            val digits = trimmedPhone.filter { it.isDigit() }
            if (digits.length !in 10..15) {
                _state.value = current.copy(
                    error = "Phone number must be 10-15 digits",
                )
                return
            }
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateCustomerRequest(
                    firstName = current.firstName.trim(),
                    lastName = current.lastName.trim().ifBlank { null },
                    phone = current.phone.trim().ifBlank { null },
                    email = current.email.trim().ifBlank { null },
                    organization = current.organization.trim().ifBlank { null },
                    address1 = current.address.trim().ifBlank { null },
                    city = current.city.trim().ifBlank { null },
                    state = current.state.trim().ifBlank { null },
                )
                val createdId = customerRepository.createCustomer(request)
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create customer",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: CustomerCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate on successful creation
    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) {
            onCreated(id)
        }
    }

    // Show error via snackbar
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
            BrandTopAppBar(
                title = "New Customer",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                            enabled = state.firstName.isNotBlank(),
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.primary,
                                disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            ),
                        ) {
                            Text("Save")
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
            // OutlinedTextFields inherit purple focus ring from theme — no per-field overrides needed.

            OutlinedTextField(
                value = state.firstName,
                onValueChange = viewModel::updateFirstName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("First Name *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )

            OutlinedTextField(
                value = state.lastName,
                onValueChange = viewModel::updateLastName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Last Name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )

            OutlinedTextField(
                value = state.phone,
                onValueChange = viewModel::updatePhone,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Phone") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Phone,
                    imeAction = ImeAction.Next,
                ),
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
            )

            OutlinedTextField(
                value = state.organization,
                onValueChange = viewModel::updateOrganization,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Organization") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )

            OutlinedTextField(
                value = state.address,
                onValueChange = viewModel::updateAddress,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Address") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = state.city,
                    onValueChange = viewModel::updateCity,
                    modifier = Modifier.weight(1f),
                    label = { Text("City") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                )

                OutlinedTextField(
                    value = state.state,
                    onValueChange = viewModel::updateState,
                    modifier = Modifier.weight(1f),
                    label = { Text("State") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                )
            }
        }
    }
}
