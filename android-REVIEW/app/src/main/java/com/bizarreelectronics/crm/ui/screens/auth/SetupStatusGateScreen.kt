package com.bizarreelectronics.crm.ui.screens.auth

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.SetupStatusResponse
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import javax.inject.Inject

// ─── State ──────────────────────────────────────────────────────────

/** §2.1 — Sealed state for the setup-status gate probe. */
sealed interface SetupGateState {
    data object Loading : SetupGateState
    data class Done(val result: SetupStatusResponse) : SetupGateState
    data class Error(val message: String) : SetupGateState
}

// ─── ViewModel ──────────────────────────────────────────────────────

/**
 * §2.1 — ViewModel for the standalone SetupStatusGateScreen.
 *
 * Calls GET /auth/setup-status once on init. Emits:
 *   Loading → probe in flight (≤5 s timeout enforced by withTimeout)
 *   Done    → probe succeeded; callers inspect result.needsSetup / isMultiTenant
 *   Error   → network failure or timeout; UI shows inline retry
 *
 * Design choice (SAFEST per spec): this VM is used by SetupStatusGateScreen,
 * which is an optional standalone route between server-URL confirmation and
 * the login form. It is NOT mandatory; AppNavGraph wires it only when a
 * serverUrl is already stored and the user is not yet logged in.
 */
@HiltViewModel
class SetupStatusGateViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state: MutableStateFlow<SetupGateState> = MutableStateFlow(SetupGateState.Loading)
    val state: StateFlow<SetupGateState> = _state.asStateFlow()

    init {
        probe()
    }

    fun retry() {
        _state.value = SetupGateState.Loading
        probe()
    }

    private fun probe() {
        viewModelScope.launch {
            try {
                // §2.1 spec: ≤400ms overlay. We allow up to 5 s total before
                // surfacing an error surface so the user is never stuck.
                val response = withTimeout(5_000L) {
                    authApi.getSetupStatus()
                }
                val data = response.data
                if (data == null) {
                    // Null body is unexpected — treat as error so caller can retry
                    _state.value = SetupGateState.Error("Server returned an unexpected response.")
                } else {
                    _state.value = SetupGateState.Done(data)
                }
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                _state.value = SetupGateState.Error("Connection timed out. Check your server URL.")
            } catch (e: Exception) {
                _state.value = SetupGateState.Error(e.message ?: "Could not reach server.")
            }
        }
    }
}

// ─── UI ─────────────────────────────────────────────────────────────

/**
 * §2.1 — Standalone gate screen shown between server-URL confirmation and
 * the login form when the app already has a saved serverUrl but has not
 * yet authenticated.
 *
 * Callbacks:
 *   onNeedsSetup  — server has no users (needsSetup=true). Route to initial
 *                   setup flow (§2.10) when it exists.
 *   onMultiTenant — server is multi-tenant AND no tenant is chosen. Route
 *                   to tenant picker when it exists (TODO §2.10).
 *   onLogin       — server is ready for login (the normal path).
 *   onRetry       — optional: caller wants to handle retry at nav level.
 *                   If null, the gate handles retry internally.
 *
 * UX spec (§2.1 line 276):
 *   - Transparent, ≤400ms overlay CircularProgressIndicator with
 *     "Connecting to your server…" label.
 *   - On failure: inline error + "Retry" button.
 *   - On Done: LaunchedEffect routes to correct callback.
 */
@Composable
fun SetupStatusGateScreen(
    onNeedsSetup: () -> Unit,
    onMultiTenant: () -> Unit,
    onLogin: () -> Unit,
    onRetry: (() -> Unit)? = null,
    viewModel: SetupStatusGateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // §2.1 — route immediately when probe completes (no extra user tap).
    LaunchedEffect(state) {
        if (state is SetupGateState.Done) {
            val result = (state as SetupGateState.Done).result
            when {
                result.needsSetup -> onNeedsSetup()
                // TODO(§2.10): tenant picker doesn't exist yet. Log and fall
                // through to login so the user isn't stuck.
                result.isMultiTenant == true -> onMultiTenant()
                else -> onLogin()
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        contentAlignment = Alignment.Center,
    ) {
        when (state) {
            is SetupGateState.Loading -> {
                // §2.1 spec: ≤400ms overlay, centered progress + label.
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator()
                    Text(
                        "Connecting to your server\u2026",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            is SetupGateState.Error -> {
                // §2.1 spec: fail → inline retry on login screen.
                // Since this IS the gate screen, we show inline retry here.
                Column(
                    modifier = Modifier
                        .widthIn(max = 320.dp)
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(
                        (state as SetupGateState.Error).message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Button(
                        onClick = {
                            if (onRetry != null) {
                                onRetry()
                            } else {
                                viewModel.retry()
                            }
                        },
                    ) {
                        Text("Retry")
                    }
                    // §2.1: failure is non-blocking — user can skip to login.
                    TextButton(onClick = onLogin) {
                        Text(
                            "Continue to sign in",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }

            // Done state is handled by LaunchedEffect above; nothing to render.
            is SetupGateState.Done -> {}
        }
    }
}
