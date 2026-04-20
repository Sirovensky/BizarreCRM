package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ProfileUiState(
    val username: String = "",
    val firstName: String = "",
    val lastName: String = "",
    val email: String = "",
    val role: String = "",
    val avatarUrl: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val snackbarMessage: String? = null,
    val isSubmitting: Boolean = false,
    // U6 fix: VM drives dialog close by bumping a success counter when a
    // change-password or change-pin mutation succeeds.
    val passwordChangeSuccessCounter: Int = 0,
    val pinChangeSuccessCounter: Int = 0,
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authApi: AuthApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(ProfileUiState())
    val state = _state.asStateFlow()

    init {
        loadProfile()
    }

    private fun loadProfile() {
        // Start with cached prefs for instant display
        _state.value = _state.value.copy(
            username = authPreferences.username.orEmpty(),
            firstName = authPreferences.userFirstName.orEmpty(),
            lastName = authPreferences.userLastName.orEmpty(),
            role = authPreferences.userRole.orEmpty(),
            isLoading = true,
        )

        // Then refresh from server
        viewModelScope.launch {
            try {
                val response = authApi.getMe()
                val user = response.data
                if (user != null) {
                    _state.value = _state.value.copy(
                        username = user.username,
                        firstName = user.firstName.orEmpty(),
                        lastName = user.lastName.orEmpty(),
                        email = user.email.orEmpty(),
                        role = user.role,
                        avatarUrl = user.avatarUrl,
                        isLoading = false,
                    )
                } else {
                    _state.value = _state.value.copy(isLoading = false)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load profile",
                )
            }
        }
    }

    // U6 fix: actually call the change-password endpoint instead of showing a
    // "not implemented yet" toast.
    fun changePassword(currentPassword: String, newPassword: String) {
        if (_state.value.isSubmitting) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true)
            try {
                val response = authApi.changePassword(
                    mapOf(
                        "currentPassword" to currentPassword,
                        "newPassword" to newPassword,
                    ),
                )
                if (response.success) {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = "Password changed successfully",
                        passwordChangeSuccessCounter = _state.value.passwordChangeSuccessCounter + 1,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = response.message ?: "Failed to change password",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    snackbarMessage = "Failed to change password: ${e.message}",
                )
            }
        }
    }

    // U6 fix: same for PIN.
    fun changePin(currentPin: String, newPin: String) {
        if (_state.value.isSubmitting) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true)
            try {
                val response = authApi.changePin(
                    mapOf(
                        "currentPin" to currentPin,
                        "newPin" to newPin,
                    ),
                )
                if (response.success) {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = "PIN changed successfully",
                        pinChangeSuccessCounter = _state.value.pinChangeSuccessCounter + 1,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = response.message ?: "Failed to change PIN",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    snackbarMessage = "Failed to change PIN: ${e.message}",
                )
            }
        }
    }

    fun clearSnackbar() {
        _state.value = _state.value.copy(snackbarMessage = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    onBack: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    var showPasswordDialog by rememberSaveable { mutableStateOf(false) }
    var showPinDialog by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(state.snackbarMessage) {
        val msg = state.snackbarMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSnackbar()
        }
    }

    LaunchedEffect(state.passwordChangeSuccessCounter) {
        if (state.passwordChangeSuccessCounter > 0) {
            showPasswordDialog = false
        }
    }

    LaunchedEffect(state.pinChangeSuccessCounter) {
        if (state.pinChangeSuccessCounter > 0) {
            showPinDialog = false
        }
    }

    if (showPasswordDialog) {
        ChangePasswordDialog(
            isSubmitting = state.isSubmitting,
            onDismiss = { showPasswordDialog = false },
            onSubmit = { current, new ->
                viewModel.changePassword(current, new)
            },
        )
    }

    if (showPinDialog) {
        ChangePinDialog(
            isSubmitting = state.isSubmitting,
            onDismiss = { showPinDialog = false },
            onSubmit = { current, new ->
                viewModel.changePin(current, new)
            },
        )
    }

    Scaffold(
        // D5-8: password / PIN change fields live deep in the scroll and would
        // be hidden under the soft keyboard without explicit imePadding.
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Profile",
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
    ) { padding ->
        if (state.isLoading && state.username.isBlank()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // Avatar placeholder
                Surface(
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.size(80.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        val initials = buildString {
                            state.firstName.firstOrNull()?.let { append(it.uppercase()) }
                            state.lastName.firstOrNull()?.let { append(it.uppercase()) }
                        }.ifBlank { state.username.take(2).uppercase() }

                        Text(
                            initials,
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    }
                }

                val fullName = "${state.firstName} ${state.lastName}".trim()
                if (fullName.isNotBlank()) {
                    Text(
                        fullName,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }

                if (state.role.isNotBlank()) {
                    Text(
                        state.role.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                HorizontalDivider()

                // Profile details
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        ProfileDetailRow(
                            icon = Icons.Default.Person,
                            label = "Username",
                            value = state.username.ifBlank { "-" },
                        )
                        ProfileDetailRow(
                            icon = Icons.Default.Email,
                            label = "Email",
                            value = state.email.ifBlank { "-" },
                        )
                        ProfileDetailRow(
                            icon = Icons.Default.Security,
                            label = "2FA Status",
                            value = "Enabled",
                        )
                    }
                }

                state.error?.let { errorText ->
                    Text(
                        errorText,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                // Actions
                OutlinedButton(
                    onClick = { showPasswordDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    // decorative — OutlinedButton's "Change Password" Text supplies the accessible name
                    Icon(Icons.Default.Lock, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Change Password")
                }

                OutlinedButton(
                    onClick = { showPinDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    // decorative — OutlinedButton's "Change PIN" Text supplies the accessible name
                    Icon(Icons.Default.Pin, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Change PIN")
                }
            }
        }
    }
}

@Composable
private fun ChangePasswordDialog(
    isSubmitting: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (currentPassword: String, newPassword: String) -> Unit,
) {
    var currentPassword by rememberSaveable { mutableStateOf("") }
    var newPassword by rememberSaveable { mutableStateOf("") }
    var confirmPassword by rememberSaveable { mutableStateOf("") }

    val passwordsMatch = newPassword == confirmPassword
    val newIsLongEnough = newPassword.length >= 8
    val canSubmit = currentPassword.isNotBlank() &&
        newIsLongEnough &&
        passwordsMatch &&
        !isSubmitting

    AlertDialog(
        onDismissRequest = {
            if (!isSubmitting) onDismiss()
        },
        title = { Text("Change Password") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Current password") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                )
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("New password (min 8 chars)") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = newPassword.isNotEmpty() && !newIsLongEnough,
                    supportingText = {
                        if (newPassword.isNotEmpty() && !newIsLongEnough) {
                            Text(
                                "Password must be at least 8 characters",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
                OutlinedTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Confirm new password") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = confirmPassword.isNotEmpty() && !passwordsMatch,
                    supportingText = {
                        if (confirmPassword.isNotEmpty() && !passwordsMatch) {
                            Text(
                                "Passwords do not match",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (canSubmit) onSubmit(currentPassword, newPassword)
                },
                enabled = canSubmit,
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Saving...")
                } else {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSubmitting) {
                Text("Cancel")
            }
        },
    )
}

@Composable
private fun ChangePinDialog(
    isSubmitting: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (currentPin: String, newPin: String) -> Unit,
) {
    var currentPin by rememberSaveable { mutableStateOf("") }
    var newPin by rememberSaveable { mutableStateOf("") }
    var confirmPin by rememberSaveable { mutableStateOf("") }

    val newIsValid = newPin.length in 4..8 && newPin.all { it.isDigit() }
    val pinsMatch = newPin == confirmPin
    val canSubmit = currentPin.isNotBlank() && newIsValid && pinsMatch && !isSubmitting

    AlertDialog(
        onDismissRequest = {
            if (!isSubmitting) onDismiss()
        },
        title = { Text("Change PIN") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = currentPin,
                    onValueChange = { value ->
                        if (value.length <= 8 && value.all { it.isDigit() }) currentPin = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Current PIN") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                )
                OutlinedTextField(
                    value = newPin,
                    onValueChange = { value ->
                        if (value.length <= 8 && value.all { it.isDigit() }) newPin = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("New PIN (4-8 digits)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = newPin.isNotEmpty() && !newIsValid,
                    supportingText = {
                        if (newPin.isNotEmpty() && !newIsValid) {
                            Text(
                                "PIN must be 4-8 digits",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
                OutlinedTextField(
                    value = confirmPin,
                    onValueChange = { value ->
                        if (value.length <= 8 && value.all { it.isDigit() }) confirmPin = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Confirm new PIN") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = confirmPin.isNotEmpty() && !pinsMatch,
                    supportingText = {
                        if (confirmPin.isNotEmpty() && !pinsMatch) {
                            Text(
                                "PINs do not match",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (canSubmit) onSubmit(currentPin, newPin)
                },
                enabled = canSubmit,
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Saving...")
                } else {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSubmitting) {
                Text("Cancel")
            }
        },
    )
}

@Composable
private fun ProfileDetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // decorative — non-clickable label-value row; sibling label + value Text carry the announcement
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Column {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
