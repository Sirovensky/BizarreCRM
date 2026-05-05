package com.bizarreelectronics.crm.ui.screens.settings

// §2.11 — ViewModel for the Active Sessions screen.
//
// UiState machine:
//   Loading → Content(sessions) | Error(AppError)
//
// revoke(id):
//   1. Validate id is non-empty (guard).
//   2. Optimistic removal from Content list.
//   3. DELETE /auth/sessions/{id}.
//   4. On failure → rollback to pre-removal list + emit snackbar error.
//
// 404 guard:
//   GET /auth/sessions returning 404 is mapped to Content(emptyList) with
//   serverUnsupported=true so the screen renders an informational footer
//   instead of a retry action.

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ActiveSessionDto
import com.bizarreelectronics.crm.util.AppError
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject

// ---------------------------------------------------------------------------
// UI model — decoupled from DTO so the screen never depends on Gson annotations
// ---------------------------------------------------------------------------

data class ActiveSessionUi(
    val id: String,
    val device: String,
    val ip: String?,
    val userAgentShort: String?,
    val createdAt: String?,
    val lastSeenAt: String?,
    val isCurrent: Boolean,
)

private fun ActiveSessionDto.toUi(): ActiveSessionUi = ActiveSessionUi(
    id = id,
    device = device?.takeIf { it.isNotBlank() } ?: "Unknown device",
    ip = ip?.takeIf { it.isNotBlank() },
    userAgentShort = userAgent?.take(60)?.let { if (userAgent.length > 60) "$it…" else it },
    createdAt = createdAt,
    lastSeenAt = lastSeenAt,
    isCurrent = current,
)

// ---------------------------------------------------------------------------
// UiState
// ---------------------------------------------------------------------------

sealed class ActiveSessionsUiState {
    data object Loading : ActiveSessionsUiState()

    /**
     * Sessions loaded successfully.
     *
     * [serverUnsupported] is true when the server responded with 404 —
     * the feature does not exist on this server version. The screen should
     * render an informational footer instead of a retry action in that case.
     */
    data class Content(
        val sessions: List<ActiveSessionUi>,
        val serverUnsupported: Boolean = false,
    ) : ActiveSessionsUiState()

    data class Error(val error: AppError) : ActiveSessionsUiState()
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * §2.11 — HiltViewModel for ActiveSessionsScreen.
 *
 * Exposes [uiState] and [revokeMessage] for the screen to observe.
 *
 * [refresh] loads sessions from GET /auth/sessions. A 404 is treated as
 * "server does not support this feature" and results in an empty Content
 * state with [ActiveSessionsUiState.Content.serverUnsupported] = true.
 *
 * [revoke] performs an optimistic remove of the session from the current
 * list, calls DELETE /auth/sessions/{id}, and rolls back on failure.
 */
@HiltViewModel
class ActiveSessionsViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ActiveSessionsUiState>(ActiveSessionsUiState.Loading)
    val uiState: StateFlow<ActiveSessionsUiState> = _uiState.asStateFlow()

    /** One-shot snackbar message emitted after a revoke success or failure. */
    private val _revokeMessage = MutableStateFlow<String?>(null)
    val revokeMessage: StateFlow<String?> = _revokeMessage.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.value = ActiveSessionsUiState.Loading
        viewModelScope.launch {
            _uiState.value = loadSessions()
        }
    }

    /**
     * Revoke session [id]. Guards against blank id. Optimistically removes
     * the session from the list, then calls the server. On any failure the
     * list is rolled back to its pre-removal state and a message is emitted.
     */
    fun revoke(id: String) {
        if (id.isBlank()) return

        val current = _uiState.value as? ActiveSessionsUiState.Content ?: return
        val snapshot = current.sessions
        val updated = snapshot.filter { it.id != id }

        // Optimistic removal
        _uiState.value = current.copy(sessions = updated)

        viewModelScope.launch {
            try {
                val response = authApi.revokeSession(id)
                if (response.success) {
                    _revokeMessage.value = "Session revoked"
                } else {
                    // Server returned success=false — roll back
                    _uiState.value = current.copy(sessions = snapshot)
                    _revokeMessage.value = response.message
                        ?: "Could not revoke session"
                }
            } catch (e: HttpException) {
                _uiState.value = current.copy(sessions = snapshot)
                _revokeMessage.value = when (e.code()) {
                    404 -> "Session no longer exists"
                    403 -> "Not permitted to revoke this session"
                    else -> "Revoke failed (${e.code()})"
                }
            } catch (e: IOException) {
                _uiState.value = current.copy(sessions = snapshot)
                _revokeMessage.value = "Network error — changes not saved"
            } catch (e: Exception) {
                _uiState.value = current.copy(sessions = snapshot)
                _revokeMessage.value = "Unexpected error revoking session"
            }
        }
    }

    fun clearRevokeMessage() {
        _revokeMessage.value = null
    }

    // ── private helpers ───────────────────────────────────────────────────────

    private suspend fun loadSessions(): ActiveSessionsUiState {
        return try {
            val response = authApi.sessions()
            if (response.success) {
                val sessions = response.data.orEmpty().map { it.toUi() }
                ActiveSessionsUiState.Content(sessions = sessions)
            } else {
                ActiveSessionsUiState.Error(
                    AppError.Server(500, response.message, null)
                )
            }
        } catch (e: HttpException) {
            if (e.code() == 404) {
                // Server does not expose /auth/sessions — present an empty list
                // with the "not supported" footer instead of an error state.
                ActiveSessionsUiState.Content(
                    sessions = emptyList(),
                    serverUnsupported = true,
                )
            } else {
                ActiveSessionsUiState.Error(AppError.from(e))
            }
        } catch (e: IOException) {
            ActiveSessionsUiState.Error(AppError.Network(e))
        } catch (e: Exception) {
            ActiveSessionsUiState.Error(AppError.Unknown(e))
        }
    }
}
