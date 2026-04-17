package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.CreateEmployeeRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * Role options for the create form. Mirrors the server's role column — admin
 * has full access, manager skips financial actions, technician is a frontline
 * repair worker (default). Changes here should track new server roles.
 */
private val ROLE_OPTIONS = listOf("admin", "manager", "technician")

private const val DEFAULT_ROLE = "technician"

data class EmployeeCreateUiState(
    val username: String = "",
    val firstName: String = "",
    val lastName: String = "",
    val email: String = "",
    val role: String = DEFAULT_ROLE,
    val password: String = "",
    val pin: String = "",
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val created: Boolean = false,
)

@HiltViewModel
class EmployeeCreateViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _state = MutableStateFlow(EmployeeCreateUiState())
    val state = _state.asStateFlow()

    fun updateUsername(value: String) {
        _state.value = _state.value.copy(username = value)
    }

    fun updateFirstName(value: String) {
        _state.value = _state.value.copy(firstName = value)
    }

    fun updateLastName(value: String) {
        _state.value = _state.value.copy(lastName = value)
    }

    fun updateEmail(value: String) {
        _state.value = _state.value.copy(email = value)
    }

    fun updateRole(value: String) {
        _state.value = _state.value.copy(role = value)
    }

    fun updatePassword(value: String) {
        _state.value = _state.value.copy(password = value)
    }

    fun updatePin(value: String) {
        // Restrict to digits; trim to 4 so the input cannot overflow a
        // traditional PIN length even if the IME allows longer entries.
        val digits = value.filter { it.isDigit() }.take(4)
        _state.value = _state.value.copy(pin = digits)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun save() {
        val current = _state.value
        val username = current.username.trim()
        val firstName = current.firstName.trim()
        val lastName = current.lastName.trim()
        val email = current.email.trim()
        val password = current.password
        val pin = current.pin.trim()

        // Mirror server validation so users don't pay a round trip to learn
        // about obvious form errors. The server performs the canonical checks
        // in settings.routes.ts:770.
        if (username.isEmpty()) {
            _state.value = current.copy(error = "Username is required")
            return
        }
        if (firstName.isEmpty()) {
            _state.value = current.copy(error = "First name is required")
            return
        }
        if (lastName.isEmpty()) {
            _state.value = current.copy(error = "Last name is required")
            return
        }
        if (password.isNotEmpty() && password.length < 8) {
            _state.value = current.copy(error = "Password must be at least 8 characters")
            return
        }
        if (pin.isNotEmpty() && pin.length != 4) {
            _state.value = current.copy(error = "PIN must be 4 digits")
            return
        }
        if (current.role !in ROLE_OPTIONS) {
            _state.value = current.copy(error = "Select a valid role")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateEmployeeRequest(
                    username = username,
                    email = email.ifBlank { null },
                    password = password.ifBlank { null },
                    firstName = firstName,
                    lastName = lastName,
                    role = current.role,
                    pin = pin.ifBlank { null },
                )
                settingsApi.createEmployee(request)
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    created = true,
                )
            } catch (e: HttpException) {
                // Surface server-side validation / duplicate-username / role
                // errors to the user without leaking raw HTML or stack traces.
                val message = when (e.code()) {
                    400 -> "Check the form for invalid fields"
                    403 -> "You don't have permission to add employees"
                    409 -> "That username is already taken"
                    else -> e.message() ?: "Failed to create employee"
                }
                _state.value = _state.value.copy(isSubmitting = false, error = message)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create employee",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmployeeCreateScreen(
    onBack: () -> Unit,
    onCreated: () -> Unit,
    viewModel: EmployeeCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate back on successful creation — the parent is expected to refresh
    // the employee list after popping this screen.
    LaunchedEffect(state.created) {
        if (state.created) {
            onCreated()
        }
    }

    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    var roleDropdownExpanded by remember { mutableStateOf(false) }
    // D5-6: IME Next advances focus, IME Done on the PIN field submits the
    // same way the toolbar Save button does.
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            viewModel.save()
        },
    )

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "New Employee",
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
                            enabled = state.username.isNotBlank() &&
                                state.firstName.isNotBlank() &&
                                state.lastName.isNotBlank(),
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
            OutlinedTextField(
                value = state.username,
                onValueChange = viewModel::updateUsername,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Username *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.firstName,
                onValueChange = viewModel::updateFirstName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("First name *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.lastName,
                onValueChange = viewModel::updateLastName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Last name *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
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

            // Role dropdown — readOnly text field anchored to an exposed
            // dropdown, mirroring LeadCreateScreen's status picker style.
            ExposedDropdownMenuBox(
                expanded = roleDropdownExpanded,
                onExpandedChange = { roleDropdownExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.role.replaceFirstChar { it.uppercase() },
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Role") },
                    trailingIcon = {
                        // decorative — dropdown chevron inside a labeled ExposedDropdownMenuBox TextField; the label "Role" announces the purpose
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    },
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = roleDropdownExpanded,
                    onDismissRequest = { roleDropdownExpanded = false },
                ) {
                    ROLE_OPTIONS.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option.replaceFirstChar { it.uppercase() }) },
                            onClick = {
                                viewModel.updateRole(option)
                                roleDropdownExpanded = false
                            },
                        )
                    }
                }
            }

            OutlinedTextField(
                value = state.password,
                onValueChange = viewModel::updatePassword,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Password (optional, \u22658 chars)") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
                supportingText = {
                    Text(
                        "Leave blank to let the employee set it on first login.",
                        style = MaterialTheme.typography.labelSmall,
                    )
                },
            )

            OutlinedTextField(
                value = state.pin,
                onValueChange = viewModel::updatePin,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("PIN (optional, 4 digits)") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.NumberPassword,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = onDoneSave,
            )
        }
    }
}
