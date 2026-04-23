package com.bizarreelectronics.crm.ui.screens.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.BackupCodeRecoveryRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.util.EmailValidator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

// ─── State ──────────────────────────────────────────────────────────

data class BackupCodeRecoveryUiState(
    val email: String = "",
    val backupCode: String = "",
    val newPassword: String = "",
    val confirmPassword: String = "",
    val isLoading: Boolean = false,
    val error: String? = null,
    val success: Boolean = false,
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class BackupCodeRecoveryViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state = MutableStateFlow(BackupCodeRecoveryUiState())
    val state = _state.asStateFlow()

    fun updateEmail(value: String) {
        _state.value = _state.value.copy(email = value, error = null)
    }

    fun updateBackupCode(value: String) {
        _state.value = _state.value.copy(backupCode = value, error = null)
    }

    fun updateNewPassword(value: String) {
        _state.value = _state.value.copy(newPassword = value, error = null)
    }

    fun updateConfirmPassword(value: String) {
        _state.value = _state.value.copy(confirmPassword = value, error = null)
    }

    fun submit() {
        val s = _state.value
        val email = s.email.trim()
        val code = s.backupCode.trim()

        when (EmailValidator.validate(email)) {
            EmailValidator.Result.Empty -> {
                _state.value = s.copy(error = "Email address is required")
                return
            }
            EmailValidator.Result.Malformed -> {
                _state.value = s.copy(error = "Enter a valid email address")
                return
            }
            EmailValidator.Result.Ok -> Unit
        }
        if (code.isBlank()) {
            _state.value = s.copy(error = "Backup code is required")
            return
        }
        if (s.newPassword.length < 8) {
            _state.value = s.copy(error = "New password must be at least 8 characters")
            return
        }
        if (s.newPassword != s.confirmPassword) {
            _state.value = s.copy(error = "Passwords do not match")
            return
        }

        _state.value = s.copy(isLoading = true, error = null)

        viewModelScope.launch {
            try {
                authApi.recoverWithBackupCode(
                    BackupCodeRecoveryRequest(
                        email = email,
                        backupCode = code,
                        newPassword = s.newPassword,
                    )
                )
                // Server performs the full recovery (resets password, disables 2FA).
                // On success the user should log in fresh — signal success to the nav.
                _state.value = _state.value.copy(isLoading = false, success = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = extractErrorMessage(e),
                )
            }
        }
    }

    private fun extractErrorMessage(e: Exception): String {
        if (e is retrofit2.HttpException) {
            val body = e.response()?.errorBody()?.string()
            if (body != null) {
                try {
                    return JSONObject(body).optString("message", e.message ?: "Request failed")
                } catch (_: Exception) {}
            }
            return "Server error (${e.code()})"
        }
        return e.message ?: "An error occurred"
    }
}

// ─── UI ─────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupCodeRecoveryScreen(
    onBack: () -> Unit,
    onSuccess: () -> Unit,
    viewModel: BackupCodeRecoveryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current
    var showNewPassword by remember { mutableStateOf(false) }
    var showConfirmPassword by remember { mutableStateOf(false) }

    LaunchedEffect(state.success) {
        if (state.success) {
            snackbarHostState.showSnackbar(
                message = "Account recovered. Please sign in with your new password.",
                duration = SnackbarDuration.Long,
            )
            onSuccess()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Backup Code Recovery") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 24.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Spacer(Modifier.height(24.dp))

            Text(
                "Recover with Backup Code",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Enter your email, a backup code from your original setup, and set a new password.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(32.dp))

            OutlinedTextField(
                value = state.email,
                onValueChange = viewModel::updateEmail,
                label = { Text("Email address") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = { Icon(Icons.Default.Email, contentDescription = null) },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
                isError = state.error != null,
            )

            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = state.backupCode,
                onValueChange = viewModel::updateBackupCode,
                label = { Text("Backup code") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = { Icon(Icons.Default.Security, contentDescription = null) },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Text,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
                isError = state.error != null,
            )

            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = state.newPassword,
                onValueChange = viewModel::updateNewPassword,
                label = { Text("New password") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
                visualTransformation = if (showNewPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    IconButton(onClick = { showNewPassword = !showNewPassword }) {
                        Icon(
                            if (showNewPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = "Toggle password visibility",
                        )
                    }
                },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
                isError = state.error != null,
            )

            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = state.confirmPassword,
                onValueChange = viewModel::updateConfirmPassword,
                label = { Text("Confirm new password") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
                visualTransformation = if (showConfirmPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    IconButton(onClick = { showConfirmPassword = !showConfirmPassword }) {
                        Icon(
                            if (showConfirmPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = "Toggle confirm password visibility",
                        )
                    }
                },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = {
                    focusManager.clearFocus()
                    viewModel.submit()
                }),
                isError = state.error != null,
            )

            if (state.error != null) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Spacer(Modifier.height(24.dp))

            BrandPrimaryButton(
                onClick = {
                    focusManager.clearFocus()
                    viewModel.submit()
                },
                enabled = state.email.isNotBlank() && state.backupCode.isNotBlank() &&
                    state.newPassword.isNotBlank() && !state.isLoading,
                modifier = Modifier.fillMaxWidth().height(48.dp),
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Recover Account")
                }
            }
        }
    }
}
