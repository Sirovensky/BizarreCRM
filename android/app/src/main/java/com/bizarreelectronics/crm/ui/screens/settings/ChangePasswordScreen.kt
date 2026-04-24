package com.bizarreelectronics.crm.ui.screens.settings

// §2.9 Change-password screen (ActionPlan L340).
//
// Flow:
//   1. User fills currentPassword, newPassword, confirmNewPassword.
//   2. Strength meter under newPassword shows live checklist (min 8, upper, lower,
//      digit, symbol). "Update password" button stays disabled until all rules pass
//      AND confirmNewPassword matches.
//   3. Optional "Sign out other sessions" Switch (default off). Sends
//      signOutOtherSessions=true in the request body — server currently always
//      revokes ALL sessions on change-password anyway, so this flag is best-effort
//      documentation for the user rather than a distinct server behavior.
//   4. On success: Snackbar "Password updated", 1 s delay, then onPasswordChanged()
//      (caller pops back to Security).
//   5. On error: inline error message under the button from the response body.
//   6. FLAG_SECURE applied via DisposableEffect so screenshots/recents are blocked.
//
// Body keys sent to POST /api/v1/auth/change-password:
//   current_password, new_password  (snake_case — matches server auth.routes.ts:2054)
//   signOutOtherSessions            (camelCase key — server ignores unknown fields)
//
// SECURITY: currentPassword and newPassword are NEVER logged or written to disk.
//           Fields are cleared from state in ViewModel.onCleared() and on success.

import android.app.Activity
import android.view.WindowManager
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Password strength rules
// ---------------------------------------------------------------------------

/**
 * Immutable snapshot of which strength rules are satisfied.
 * Rules match the server minimum (≥ 8 chars) plus additional UX guidance
 * (upper, lower, digit, symbol) even though the server does not enforce them.
 */
data class PasswordStrength(
    val hasMinLength: Boolean = false,
    val hasUppercase: Boolean = false,
    val hasLowercase: Boolean = false,
    val hasDigit: Boolean = false,
    val hasSymbol: Boolean = false,
) {
    /** True when every rule is satisfied — enables the submit button. */
    val allPassed: Boolean
        get() = hasMinLength && hasUppercase && hasLowercase && hasDigit && hasSymbol

    /** 0.0 – 1.0 progress for the LinearProgressIndicator. */
    val progress: Float
        get() {
            val count = listOf(hasMinLength, hasUppercase, hasLowercase, hasDigit, hasSymbol)
                .count { it }
            return count / 5f
        }

    companion object {
        fun evaluate(password: String) = PasswordStrength(
            hasMinLength = password.length >= 8,
            hasUppercase = password.any { it.isUpperCase() },
            hasLowercase = password.any { it.isLowerCase() },
            hasDigit = password.any { it.isDigit() },
            hasSymbol = password.any { !it.isLetterOrDigit() },
        )
    }
}

// ---------------------------------------------------------------------------
// ViewModel state
// ---------------------------------------------------------------------------

data class ChangePasswordUiState(
    /** Current (existing) password — cleared after submit / on leave. NEVER logged. */
    val currentPassword: String = "",
    /** Proposed new password. NEVER logged. */
    val newPassword: String = "",
    /** Confirmation of newPassword. NEVER logged. */
    val confirmPassword: String = "",
    val signOutOtherSessions: Boolean = false,
    val strength: PasswordStrength = PasswordStrength(),
    val isLoading: Boolean = false,
    /** Non-null → show inline error under submit button. */
    val error: String? = null,
    /** Flips to true on successful API call. */
    val success: Boolean = false,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class ChangePasswordViewModel @Inject constructor(
    private val authApi: AuthApi,
    @Suppress("UnusedPrivateMember")
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(ChangePasswordUiState())
    val state: StateFlow<ChangePasswordUiState> = _state.asStateFlow()

    // ── field updates (immutable copies) ──────────────────────────────

    fun updateCurrentPassword(value: String) {
        _state.value = _state.value.copy(
            currentPassword = value,
            error = null,
        )
    }

    fun updateNewPassword(value: String) {
        _state.value = _state.value.copy(
            newPassword = value,
            strength = PasswordStrength.evaluate(value),
            error = null,
        )
    }

    fun updateConfirmPassword(value: String) {
        _state.value = _state.value.copy(
            confirmPassword = value,
            error = null,
        )
    }

    fun updateSignOutOtherSessions(value: Boolean) {
        _state.value = _state.value.copy(signOutOtherSessions = value)
    }

    // ── validation ─────────────────────────────────────────────────────

    val canSubmit: Boolean
        get() {
            val s = _state.value
            return s.currentPassword.isNotBlank()
                    && s.strength.allPassed
                    && s.newPassword == s.confirmPassword
                    && !s.isLoading
        }

    // ── submit ─────────────────────────────────────────────────────────

    fun submit() {
        val s = _state.value
        if (s.currentPassword.isBlank()) {
            _state.value = s.copy(error = "Current password is required")
            return
        }
        if (!s.strength.allPassed) {
            _state.value = s.copy(error = "New password does not meet all requirements")
            return
        }
        if (s.newPassword != s.confirmPassword) {
            _state.value = s.copy(error = "Passwords do not match")
            return
        }

        _state.value = s.copy(isLoading = true, error = null)

        viewModelScope.launch {
            try {
                // Body keys match server auth.routes.ts:2054 exactly.
                // SECURITY: these string values are never written to a log.
                val body = buildMap<String, String> {
                    put("current_password", s.currentPassword)
                    put("new_password", s.newPassword)
                    if (s.signOutOtherSessions) {
                        put("signOutOtherSessions", "true")
                    }
                }
                authApi.changePassword(body)
                // Clear sensitive fields immediately after server accepts.
                _state.value = ChangePasswordUiState(success = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = extractErrorMessage(e),
                )
            }
        }
    }

    /** Clears sensitive field values — called on screen dispose and on cancel. */
    fun clearSensitiveFields() {
        _state.value = ChangePasswordUiState()
    }

    override fun onCleared() {
        super.onCleared()
        // Belt-and-suspenders: wipe sensitive state when VM is destroyed.
        _state.value = ChangePasswordUiState()
    }

    // ── helpers ────────────────────────────────────────────────────────

    private fun extractErrorMessage(e: Exception): String {
        if (e is retrofit2.HttpException) {
            val body = e.response()?.errorBody()?.string()
            if (body != null) {
                try {
                    val msg = JSONObject(body).optString("message", "")
                    if (msg.isNotBlank()) return msg
                } catch (_: Exception) { /* fall through */ }
            }
            return "Server error (${e.code()})"
        }
        return e.message ?: "An error occurred"
    }
}

// ---------------------------------------------------------------------------
// Composable helpers
// ---------------------------------------------------------------------------

/**
 * Applies FLAG_SECURE to the host window for the lifetime of this composition.
 * Prevents the screen from appearing in the Recents thumbnail or being captured
 * in screenshots — important because all three fields contain password text.
 */
@Composable
private fun SetSecureWindow() {
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

// ---------------------------------------------------------------------------
// Screen composable
// ---------------------------------------------------------------------------

/**
 * §2.9 Change-password screen.
 *
 * @param onBack           Navigate back without committing (no side-effects).
 * @param onPasswordChanged Called after a successful password change + 1 s Snackbar
 *                          delay; caller should pop back to Security.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChangePasswordScreen(
    onBack: () -> Unit,
    onPasswordChanged: () -> Unit,
    viewModel: ChangePasswordViewModel = hiltViewModel(),
) {
    SetSecureWindow()

    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current
    val context = LocalContext.current

    // Eye-toggle visibility states (UI-only, not part of ViewModel state).
    var showCurrent by remember { mutableStateOf(false) }
    var showNew by remember { mutableStateOf(false) }
    var showConfirm by remember { mutableStateOf(false) }

    // Success side-effect: show snackbar, wait 1 s, invoke callback.
    LaunchedEffect(state.success) {
        if (state.success) {
            snackbarHostState.showSnackbar(
                message = "Password updated",
                duration = SnackbarDuration.Short,
            )
            delay(1_000L)
            onPasswordChanged()
        }
    }

    // Dispose: clear sensitive state when navigating away (back or success).
    DisposableEffect(Unit) {
        onDispose { viewModel.clearSensitiveFields() }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Change Password",
                navigationIcon = {
                    IconButton(onClick = {
                        viewModel.clearSensitiveFields()
                        onBack()
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
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
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Spacer(Modifier.height(8.dp))

            // ── current password ──────────────────────────────────────
            OutlinedTextField(
                value = state.currentPassword,
                onValueChange = viewModel::updateCurrentPassword,
                label = { Text("Current password") },
                leadingIcon = {
                    Icon(Icons.Default.Lock, contentDescription = null)
                },
                trailingIcon = {
                    val desc = if (showCurrent) "Hide current password" else "Show current password"
                    IconButton(
                        onClick = { showCurrent = !showCurrent },
                        modifier = Modifier.semantics {
                            contentDescription = desc
                        },
                    ) {
                        Icon(
                            if (showCurrent) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = null, // description is on the button
                        )
                    }
                },
                visualTransformation = if (showCurrent) VisualTransformation.None
                else PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        // a11y: contentDescription surfaces hide/show state to TalkBack;
                        //       Role.Switch was incorrect here (this is a TextField, not a toggle).
                        contentDescription = "Current password, ${if (showCurrent) "shown" else "hidden"}"
                    },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { focusManager.moveFocus(FocusDirection.Down) },
                ),
                isError = state.error != null && state.currentPassword.isBlank(),
            )

            // ── new password ──────────────────────────────────────────
            OutlinedTextField(
                value = state.newPassword,
                onValueChange = viewModel::updateNewPassword,
                label = { Text("New password") },
                leadingIcon = {
                    Icon(Icons.Default.Lock, contentDescription = null)
                },
                trailingIcon = {
                    val desc = if (showNew) "Hide new password" else "Show new password"
                    IconButton(
                        onClick = { showNew = !showNew },
                        modifier = Modifier.semantics {
                            contentDescription = desc
                        },
                    ) {
                        Icon(
                            if (showNew) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = null,
                        )
                    }
                },
                visualTransformation = if (showNew) VisualTransformation.None
                else PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "New password, ${if (showNew) "shown" else "hidden"}"
                    },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { focusManager.moveFocus(FocusDirection.Down) },
                ),
            )

            // ── strength meter ────────────────────────────────────────
            if (state.newPassword.isNotEmpty()) {
                PasswordStrengthMeter(strength = state.strength)
            }

            // ── confirm new password ──────────────────────────────────
            val confirmMismatch = state.confirmPassword.isNotEmpty()
                    && state.newPassword != state.confirmPassword
            OutlinedTextField(
                value = state.confirmPassword,
                onValueChange = viewModel::updateConfirmPassword,
                label = { Text("Confirm new password") },
                leadingIcon = {
                    Icon(Icons.Default.Lock, contentDescription = null)
                },
                trailingIcon = {
                    val desc = if (showConfirm) "Hide confirm password" else "Show confirm password"
                    IconButton(
                        onClick = { showConfirm = !showConfirm },
                        modifier = Modifier.semantics {
                            contentDescription = desc
                        },
                    ) {
                        Icon(
                            if (showConfirm) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = null,
                        )
                    }
                },
                visualTransformation = if (showConfirm) VisualTransformation.None
                else PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Confirm new password, ${if (showConfirm) "shown" else "hidden"}"
                    },
                isError = confirmMismatch,
                supportingText = if (confirmMismatch) {
                    { Text("Passwords do not match") }
                } else null,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(
                    onDone = {
                        focusManager.clearFocus()
                        if (viewModel.canSubmit) viewModel.submit()
                    },
                ),
            )

            // ── sign-out other sessions ───────────────────────────────
            Card(modifier = Modifier.fillMaxWidth()) {
                // a11y: mergeDescendants collapses label + subtitle + Switch into one node
                //       so TalkBack reads the full context before announcing the toggle state.
                val sessionsToggleState = if (state.signOutOtherSessions) "toggled on" else "toggled off"
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics(mergeDescendants = true) {
                            contentDescription = "Sign out other sessions, $sessionsToggleState. " +
                                "Revoke access on all other devices"
                        }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Sign out other sessions",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Text(
                            "Revoke access on all other devices (best-effort)",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = state.signOutOtherSessions,
                        onCheckedChange = viewModel::updateSignOutOtherSessions,
                    )
                }
            }

            // ── inline error ──────────────────────────────────────────
            if (state.error != null) {
                Text(
                    text = state.error!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // ── submit button ─────────────────────────────────────────
            Button(
                onClick = {
                    focusManager.clearFocus()
                    viewModel.submit()
                },
                enabled = viewModel.canSubmit,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
                    // a11y: explicit contentDescription so TalkBack announces the action
                    //       regardless of whether the button child is text or a spinner.
                    .semantics { contentDescription = "Update password" },
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Update password")
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Strength meter
// ---------------------------------------------------------------------------

/**
 * Visual checklist + progress bar that evaluates password strength in real time.
 * Shown only when newPassword is non-empty.
 */
@Composable
private fun PasswordStrengthMeter(strength: PasswordStrength) {
    val progressColor = when {
        strength.allPassed -> MaterialTheme.colorScheme.primary
        strength.progress >= 0.6f -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.error
    }

    // a11y: derive a human-readable strength label and list unmet criteria
    //       so screen-reader users know exactly what the bar represents.
    val strengthLabel = when {
        strength.allPassed          -> "strong"
        strength.progress >= 0.6f   -> "medium"
        else                         -> "weak"
    }
    val missing = buildList {
        if (!strength.hasMinLength) add("at least 8 characters")
        if (!strength.hasUppercase) add("uppercase letter")
        if (!strength.hasLowercase) add("lowercase letter")
        if (!strength.hasDigit)     add("number")
        if (!strength.hasSymbol)    add("symbol")
    }
    val strengthDesc = if (missing.isEmpty()) {
        "Password strength: $strengthLabel"
    } else {
        "Password strength: $strengthLabel. Missing: ${missing.joinToString(", ")}"
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        LinearProgressIndicator(
            progress = { strength.progress },
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .semantics { contentDescription = strengthDesc },
            color = progressColor,
        )

        StrengthCheckRow(passed = strength.hasMinLength, label = "At least 8 characters")
        StrengthCheckRow(passed = strength.hasUppercase, label = "Uppercase letter (A–Z)")
        StrengthCheckRow(passed = strength.hasLowercase, label = "Lowercase letter (a–z)")
        StrengthCheckRow(passed = strength.hasDigit, label = "Number (0–9)")
        StrengthCheckRow(passed = strength.hasSymbol, label = "Symbol (!@#\$…)")
    }
}

@Composable
private fun StrengthCheckRow(passed: Boolean, label: String) {
    val color = if (passed) MaterialTheme.colorScheme.primary
    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.semantics(mergeDescendants = true) {},
    ) {
        Text(
            text = if (passed) "✓" else "○",
            style = MaterialTheme.typography.bodySmall,
            color = color,
            fontWeight = if (passed) FontWeight.Bold else FontWeight.Normal,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = color,
        )
    }
}
