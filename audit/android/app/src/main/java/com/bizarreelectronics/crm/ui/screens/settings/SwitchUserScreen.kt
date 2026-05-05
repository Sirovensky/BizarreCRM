package com.bizarreelectronics.crm.ui.screens.settings

// §2.5 Switch User (shared device) — ActionPlan L310.
//
// Flow:
//   1. User arrives from Settings > "Switch user" row.
//   2. Numeric keypad (reuses PinKeypad + PinDots from ui/auth) collects a PIN.
//   3. On PIN length ≥ 4: auto-submit to POST /auth/switch-user.
//   4. On success: save new accessToken + user identity to AuthPreferences,
//      invoke onSwitched() callback → caller navigates to Dashboard.
//   5. On wrong PIN (401): shake dots, haptic REJECT, clear entry, show error.
//   6. On lockout (429): parse Retry-After header (default 900s), show countdown.
//   7. On default-PIN-not-set (403 code=PIN_NOT_SET): show advisory message.
//   8. FLAG_SECURE applied via DisposableEffect (same helper as ChangePasswordScreen).
//
// SECURITY:
//   - PIN digits are NEVER logged (no android.util.Log calls on pin content).
//   - State cleared in ViewModel.onCleared() and on successful switch.
//   - Screen cleared on dispose via DisposableEffect.
//
// Tablet layout: keypad region in a centred ElevatedCard, max 420dp wide
// (same pattern as PinLockScreen / PinGateScaffold — see commit 162cb12).
//
// TODO (deferred): Long-press on avatar in the top-app-bar should also
// navigate to this screen (ActionPlan L310 secondary entry point). The
// Settings row path is the only wired entry for now.

import android.app.Activity
import android.view.WindowManager
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.SwitchUserRequest
import com.bizarreelectronics.crm.ui.auth.PinDots
import com.bizarreelectronics.crm.ui.auth.PinKeypad
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth
import com.bizarreelectronics.crm.util.rememberReduceMotion
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel state
// ---------------------------------------------------------------------------

data class SwitchUserUiState(
    /** Currently entered PIN digits. NEVER logged. Max 6 chars. */
    val entered: String = "",
    val isWorking: Boolean = false,
    /** Non-null → display below dots. */
    val errorMessage: String? = null,
    /** Increments each wrong attempt → triggers PinDots shake animation. */
    val wrongShakes: Int = 0,
    /** Seconds remaining in server-enforced lockout. 0 = not locked out. */
    val lockoutRemainingSeconds: Int = 0,
    /** True once the switch succeeded — triggers navigation in composable. */
    val switched: Boolean = false,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class SwitchUserViewModel @Inject constructor(
    private val authApi: AuthApi,
    private val authPreferences: AuthPreferences,
    /** Exposed for §26.4 ReduceMotion check in [SwitchUserScreen]. */
    val appPreferences: AppPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(SwitchUserUiState())
    val state: StateFlow<SwitchUserUiState> = _state.asStateFlow()

    private val maxPinLength = 6
    /** Min auto-submit length — matches server minimum (1) but we use 4 for UX. */
    private val minSubmitLength = 4

    private var countdownJob: Job? = null

    // ── digit input ──────────────────────────────────────────────────

    fun onDigit(char: Char) {
        val s = _state.value
        if (s.isWorking || s.lockoutRemainingSeconds > 0) return
        if (s.entered.length >= maxPinLength) return
        val next = s.entered + char
        _state.value = s.copy(entered = next, errorMessage = null)
        if (next.length >= minSubmitLength) {
            submit(next)
        }
    }

    fun onBackspace() {
        val s = _state.value
        if (s.isWorking || s.lockoutRemainingSeconds > 0) return
        if (s.entered.isEmpty()) return
        _state.value = s.copy(
            entered = s.entered.dropLast(1),
            errorMessage = null,
        )
    }

    // ── submit ────────────────────────────────────────────────────────

    private fun submit(pin: String) {
        if (pin.isBlank()) return
        _state.value = _state.value.copy(isWorking = true, errorMessage = null)

        viewModelScope.launch {
            try {
                // SECURITY: pin is sent as request body — Retrofit serializes it.
                // We never pass pin into any log call.
                val response = authApi.switchUser(SwitchUserRequest(pin = pin))
                val data = response.data ?: run {
                    _state.value = _state.value.copy(
                        isWorking = false,
                        errorMessage = "Unexpected empty response from server",
                    )
                    return@launch
                }
                // Persist new identity immediately.
                authPreferences.accessToken = data.accessToken
                authPreferences.userId = data.user.id
                authPreferences.username = data.user.username
                authPreferences.userFirstName = data.user.firstName
                authPreferences.userLastName = data.user.lastName
                authPreferences.userRole = data.user.role
                // Clear sensitive entry, signal navigation.
                _state.value = SwitchUserUiState(switched = true)
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    private fun handleError(e: Exception) {
        val s = _state.value
        if (e is retrofit2.HttpException) {
            when (e.code()) {
                401 -> {
                    // Wrong PIN — shake, clear entry.
                    _state.value = s.copy(
                        isWorking = false,
                        entered = "",
                        errorMessage = extractMessage(e) ?: "Incorrect PIN",
                        wrongShakes = s.wrongShakes + 1,
                    )
                }
                403 -> {
                    // Default PIN not changed (PIN_NOT_SET sentinel).
                    val msg = extractMessage(e)
                        ?: "Default PIN must be changed before first use. Open Settings > Change PIN."
                    _state.value = s.copy(
                        isWorking = false,
                        entered = "",
                        errorMessage = msg,
                    )
                }
                429 -> {
                    // Rate-limited. Parse Retry-After header (seconds, default 900).
                    val retryAfter = e.response()
                        ?.headers()
                        ?.get("Retry-After")
                        ?.toLongOrNull()
                        ?: 900L
                    _state.value = s.copy(
                        isWorking = false,
                        entered = "",
                        lockoutRemainingSeconds = retryAfter.toInt(),
                        errorMessage = null,
                    )
                    startLockoutCountdown(retryAfter.toInt())
                }
                else -> {
                    _state.value = s.copy(
                        isWorking = false,
                        entered = "",
                        errorMessage = extractMessage(e) ?: "Server error (${e.code()})",
                    )
                }
            }
        } else {
            _state.value = s.copy(
                isWorking = false,
                entered = "",
                errorMessage = e.message ?: "Connection error",
            )
        }
    }

    private fun startLockoutCountdown(seconds: Int) {
        countdownJob?.cancel()
        countdownJob = viewModelScope.launch {
            var remaining = seconds
            while (remaining > 0) {
                delay(1_000L)
                remaining--
                _state.value = _state.value.copy(lockoutRemainingSeconds = remaining)
            }
        }
    }

    fun clearSensitiveFields() {
        _state.value = SwitchUserUiState()
    }

    override fun onCleared() {
        super.onCleared()
        // Belt-and-suspenders: wipe entered PIN when VM is destroyed.
        _state.value = SwitchUserUiState()
        countdownJob?.cancel()
    }

    // ── helpers ────────────────────────────────────────────────────────

    private fun extractMessage(e: retrofit2.HttpException): String? {
        val body = e.response()?.errorBody()?.string() ?: return null
        return try {
            JSONObject(body).optString("message", "").ifBlank { null }
        } catch (_: Exception) {
            null
        }
    }
}

// ---------------------------------------------------------------------------
// FLAG_SECURE helper (same pattern as ChangePasswordScreen)
// ---------------------------------------------------------------------------

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
 * §2.5 Switch User screen.
 *
 * @param onBack      Navigate back without switching (no side-effects).
 * @param onSwitched  Called after a successful user switch; caller navigates
 *                    to Dashboard, popping up to (and including) it so the
 *                    back stack is clean for the new identity.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SwitchUserScreen(
    onBack: () -> Unit,
    onSwitched: () -> Unit,
    viewModel: SwitchUserViewModel = hiltViewModel(),
) {
    SetSecureWindow()

    val state by viewModel.state.collectAsState()
    val isTablet = isMediumOrExpandedWidth()
    // §26.4 — honour Reduce Motion for the PinDots shake animation.
    val reduceMotion = rememberReduceMotion(viewModel.appPreferences)

    // Success side-effect: trigger navigation.
    LaunchedEffect(state.switched) {
        if (state.switched) onSwitched()
    }

    // Dispose: wipe sensitive state when navigating away.
    DisposableEffect(Unit) {
        onDispose { viewModel.clearSensitiveFields() }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Switch user",
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
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentAlignment = Alignment.Center,
        ) {
            if (isTablet) {
                // Tablet: centred ElevatedCard, max 420dp (matches PinGateScaffold).
                ElevatedCard(
                    modifier = Modifier
                        .widthIn(max = 420.dp)
                        .align(Alignment.Center),
                ) {
                    SwitchUserContent(
                        state = state,
                        onDigit = viewModel::onDigit,
                        onBackspace = viewModel::onBackspace,
                        reduceMotion = reduceMotion,
                        modifier = Modifier.padding(horizontal = 32.dp, vertical = 36.dp),
                    )
                }
            } else {
                // Phone: full-column layout without card chrome.
                SwitchUserContent(
                    state = state,
                    onDigit = viewModel::onDigit,
                    onBackspace = viewModel::onBackspace,
                    reduceMotion = reduceMotion,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp, vertical = 48.dp),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Inner content (shared between phone and tablet layouts)
// ---------------------------------------------------------------------------

@Composable
private fun SwitchUserContent(
    state: SwitchUserUiState,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    /** §26.4 — when true, PinDots shows a static red border instead of the shake animation. */
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Text(
            text = "Enter your PIN",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )

        // Subtitle: lockout state or default hint.
        val subtitle = when {
            state.lockoutRemainingSeconds > 0 ->
                "Too many attempts — wait ${state.lockoutRemainingSeconds}s"
            else -> "Enter the PIN for the account you want to switch to"
        }
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = if (state.lockoutRemainingSeconds > 0)
                MaterialTheme.colorScheme.error
            else
                MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.widthIn(max = 360.dp),
        )

        // PIN dots with shake animation on wrong entry.
        // §26.4: reduceMotion=true swaps shake for a static error border.
        PinDots(
            entered = state.entered.length,
            length = 6,
            shakeTrigger = state.wrongShakes,
            reduceMotion = reduceMotion,
        )

        // Error message (wrong PIN, server errors, default-PIN advisory).
        if (state.errorMessage != null) {
            Text(
                text = state.errorMessage,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(max = 360.dp),
            )
        }

        // Keypad or progress indicator while server call is in-flight.
        if (state.isWorking) {
            // a11y: announce that a verification is in progress so TalkBack users
            //       know why the keypad disappeared.
            CircularProgressIndicator(
                modifier = Modifier
                    .size(32.dp)
                    .semantics { contentDescription = "Verifying PIN, please wait" },
            )
        } else {
            PinKeypad(
                enabled = state.lockoutRemainingSeconds == 0,
                onDigit = onDigit,
                onBackspace = onBackspace,
                modifier = Modifier.widthIn(max = 320.dp),
            )
        }
    }
}
