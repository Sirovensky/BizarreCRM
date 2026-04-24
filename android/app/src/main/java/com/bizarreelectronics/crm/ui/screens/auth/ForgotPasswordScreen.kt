package com.bizarreelectronics.crm.ui.screens.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ForgotPasswordRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.util.EmailValidator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

// ─── State ──────────────────────────────────────────────────────────

data class ForgotPasswordUiState(
    val email: String = "",
    val isLoading: Boolean = false,
    val error: String? = null,
    val success: Boolean = false,
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class ForgotPasswordViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state = MutableStateFlow(ForgotPasswordUiState())
    val state = _state.asStateFlow()

    fun updateEmail(value: String) {
        _state.value = _state.value.copy(email = value, error = null)
    }

    fun submit() {
        val s = _state.value
        val email = s.email.trim()

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

        _state.value = s.copy(isLoading = true, error = null)

        viewModelScope.launch {
            try {
                authApi.forgotPassword(ForgotPasswordRequest(email = email))
                // Always show success — server returns 200 regardless of whether
                // the email exists (SEC: enumeration prevention).
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
fun ForgotPasswordScreen(
    onBack: () -> Unit,
    viewModel: ForgotPasswordViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current

    // Show snackbar on success then navigate back
    LaunchedEffect(state.success) {
        if (state.success) {
            snackbarHostState.showSnackbar(
                message = "If an account exists for that email, a reset link has been sent.",
                duration = SnackbarDuration.Long,
            )
            onBack()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Forgot Password") },
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
                "Reset Your Password",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Enter your account email address and we'll send you a link to reset your password.",
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
                enabled = state.email.isNotBlank() && !state.isLoading,
                modifier = Modifier.fillMaxWidth().height(48.dp),
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Send Reset Link")
                }
            }
        }
    }
}
