package com.bizarreelectronics.crm.ui.screens.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lock
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
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ResetPasswordRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

// ─── State ──────────────────────────────────────────────────────────

data class ResetPasswordUiState(
    val newPassword: String = "",
    val confirmPassword: String = "",
    val isLoading: Boolean = false,
    val error: String? = null,
    val success: Boolean = false,
    /** true when server responded 410 (token expired / already used) */
    val tokenExpired: Boolean = false,
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class ResetPasswordViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val authApi: AuthApi,
) : ViewModel() {

    private val token: String = savedStateHandle.get<String>("token") ?: ""

    private val _state = MutableStateFlow(ResetPasswordUiState())
    val state = _state.asStateFlow()

    fun updateNewPassword(value: String) {
        _state.value = _state.value.copy(newPassword = value, error = null)
    }

    fun updateConfirmPassword(value: String) {
        _state.value = _state.value.copy(confirmPassword = value, error = null)
    }

    fun submit() {
        val s = _state.value
        if (s.newPassword.length < 8) {
            _state.value = s.copy(error = "Password must be at least 8 characters")
            return
        }
        if (s.newPassword != s.confirmPassword) {
            _state.value = s.copy(error = "Passwords do not match")
            return
        }
        if (token.isBlank()) {
            _state.value = s.copy(error = "Invalid reset link — no token found")
            return
        }

        _state.value = s.copy(isLoading = true, error = null)

        viewModelScope.launch {
            try {
                authApi.resetPassword(ResetPasswordRequest(token = token, password = s.newPassword))
                _state.value = _state.value.copy(isLoading = false, success = true)
            } catch (e: Exception) {
                val (msg, expired) = classifyError(e)
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = msg,
                    tokenExpired = expired,
                )
            }
        }
    }

    /** Returns (errorMessage, isExpired). 410 or "expired" message → isExpired = true. */
    private fun classifyError(e: Exception): Pair<String, Boolean> {
        if (e is retrofit2.HttpException) {
            if (e.code() == 410) {
                return "This reset link has expired or already been used." to true
            }
            val body = e.response()?.errorBody()?.string()
            if (body != null) {
                try {
                    val msg = JSONObject(body).optString("message", "")
                    if (msg.contains("expired", ignoreCase = true) ||
                        msg.contains("invalid", ignoreCase = true)
                    ) {
                        return msg to true
                    }
                    if (msg.isNotBlank()) return msg to false
                } catch (_: Exception) {}
            }
            return "Server error (${e.code()})" to false
        }
        return (e.message ?: "An error occurred") to false
    }
}

// ─── UI ─────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ResetPasswordScreen(
    onBack: () -> Unit,
    onSuccess: () -> Unit,
    onExpired: () -> Unit,
    viewModel: ResetPasswordViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current
    var showNewPassword by remember { mutableStateOf(false) }
    var showConfirmPassword by remember { mutableStateOf(false) }

    LaunchedEffect(state.success) {
        if (state.success) {
            snackbarHostState.showSnackbar(
                message = "Password reset successfully. Please sign in.",
                duration = SnackbarDuration.Short,
            )
            onSuccess()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Reset Password") },
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
                "Set a New Password",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Enter and confirm your new password. Minimum 8 characters.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(32.dp))

            // Expired token surface — shown in place of the form
            if (state.tokenExpired) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "This reset link has expired or has already been used.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            fontWeight = FontWeight.Medium,
                        )
                        Spacer(Modifier.height(12.dp))
                        OutlinedButton(
                            onClick = onExpired,
                            colors = ButtonDefaults.outlinedButtonColors(
                                contentColor = MaterialTheme.colorScheme.onErrorContainer,
                            ),
                        ) {
                            Text("Request a New Reset Link")
                        }
                    }
                }
            } else {
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
                    label = { Text("Confirm password") },
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
                    enabled = state.newPassword.isNotBlank() && state.confirmPassword.isNotBlank() && !state.isLoading,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    if (state.isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    } else {
                        Text("Reset Password")
                    }
                }
            }
        }
    }
}
