package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.EmployeeApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import javax.inject.Inject

/**
 * §3.11 — dashboard tile that surfaces the signed-in employee's clock
 * status + routes to the dedicated ClockInOutScreen on tap.
 *
 * Pulls `GET /employees/:id` (self) to get [current_clock_entry.clock_in]
 * for the "Since HH:MM" subtitle. Falls back to the list endpoint on
 * failure (offline, permission) — tile still shows clocked-in state,
 * just without the timestamp.
 */
data class ClockInTileState(
    val isClockedIn: Boolean? = null,
    val displayName: String = "",
    /** §3.8 L557 — non-null after a successful toggle; cleared on next tap. */
    val justClockedInAt: String? = null,
    val isLoading: Boolean = false,
    /**
     * §3.11 — "Since h:mm a" label shown as subtitle when clocked in.
     * Null when clocked out, offline, or server omits current_clock_entry.
     */
    val clockedInSince: String? = null,
)

@HiltViewModel
class ClockInTileViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    private val employeeApi: EmployeeApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        ClockInTileState(
            displayName = listOfNotNull(authPreferences.userFirstName, authPreferences.userLastName)
                .joinToString(" ")
                .ifBlank { authPreferences.username.orEmpty() },
        ),
    )
    val state = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        val userId = authPreferences.userId ?: return
        viewModelScope.launch {
            // §3.11 — Prefer the detail endpoint which returns current_clock_entry.clock_in
            // so we can show "Since h:mm a". Fall back to the cheaper list endpoint on error.
            runCatching {
                val detail = employeeApi.getEmployee(userId).data
                val sinceLabel = detail?.currentClockEntry?.clockIn?.let { isoStr ->
                    runCatching {
                        val odt = OffsetDateTime.parse(isoStr)
                        "Since " + odt.format(DateTimeFormatter.ofPattern("h:mm a"))
                    }.getOrNull()
                }
                _state.value = _state.value.copy(
                    isClockedIn = detail?.isClockedIn,
                    clockedInSince = sinceLabel,
                )
            }.onFailure {
                // Fallback: list endpoint has is_clocked_in but not the clock_in time.
                runCatching {
                    val response = settingsApi.getEmployees()
                    val me = response.data?.firstOrNull { it.id == userId }
                    _state.value = _state.value.copy(
                        isClockedIn = me?.isClockedIn,
                        clockedInSince = null,
                    )
                }
            }
        }
    }

    /**
     * §3.8 L557 — One-tap toggle. Calls clock-in or clock-out based on current state.
     *
     * On success:
     * - Clock-in: sets [ClockInTileState.clockedInSince] optimistically from [LocalTime.now].
     * - Clock-out: clears [ClockInTileState.clockedInSince].
     *
     * @param onFallbackToScreen Called when toggle fails (e.g. PIN required) so the
     *   caller can navigate to [ClockInOutScreen] for the full flow.
     * @param onSuccess Callback supplying the Snackbar message string.
     */
    fun toggle(
        onFallbackToScreen: () -> Unit,
        onSuccess: (String) -> Unit,
    ) {
        val currentState = _state.value
        val userId = authPreferences.userId ?: run { onFallbackToScreen(); return }
        val isClockedIn = currentState.isClockedIn

        _state.value = currentState.copy(isLoading = true)

        viewModelScope.launch {
            runCatching {
                if (isClockedIn == true) {
                    settingsApi.clockOut(userId, emptyMap())
                    _state.value = _state.value.copy(
                        isClockedIn = false,
                        clockedInSince = null,
                        isLoading = false,
                    )
                    onSuccess("Clocked out")
                } else {
                    settingsApi.clockIn(userId, emptyMap())
                    val timeStr = LocalTime.now().format(DateTimeFormatter.ofPattern("h:mm a"))
                    _state.value = _state.value.copy(
                        isClockedIn = true,
                        justClockedInAt = timeStr,
                        // §3.11 — optimistic "Since h:mm a" immediately on clock-in
                        clockedInSince = "Since $timeStr",
                        isLoading = false,
                    )
                    onSuccess("Clocked in at $timeStr")
                }
            }.onFailure {
                _state.value = _state.value.copy(isLoading = false)
                android.util.Log.w("ClockInTile", "toggle failed: ${it.message}")
                onFallbackToScreen()
            }
        }
    }
}

@Composable
fun ClockInTile(
    onOpen: () -> Unit,
    snackbarHostState: SnackbarHostState? = null,
    viewModel: ClockInTileViewModel = hiltViewModel(),
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val isOn = state.isClockedIn == true
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()

    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            // §26.1 — merge children so TalkBack reads "Clocked in, Since h:mm a,
            // Button" as one labeled action instead of focusing the icon,
            // title, subtitle, and chevron separately.
            // §22.3 — hand pointer on tablet / desktop hover.
            .semantics(mergeDescendants = true) {
                role = Role.Button
            }
            .pointerHoverIcon(PointerIcon.Hand)
            .clickable {
                // §3.8 L557 — attempt direct toggle with haptic; fall back to screen.
                viewModel.toggle(
                    onFallbackToScreen = onOpen,
                    onSuccess = { message ->
                        // Fire CONTEXT_CLICK haptic on success.
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        if (snackbarHostState != null) {
                            scope.launch {
                                snackbarHostState.showSnackbar(message)
                            }
                        }
                    },
                )
            },
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Status dot — green background when clocked in, neutral otherwise.
            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(
                        if (isOn) SuccessGreen.copy(alpha = 0.18f)
                        else MaterialTheme.colorScheme.surfaceContainerHigh,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Default.AccessTime,
                    contentDescription = null,
                    tint = if (isOn) SuccessGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isOn) "Clocked in" else "Clock in / out",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                // §3.11 — "Since h:mm a" when clocked in and timestamp available;
                // falls back to display name, then generic hint.
                val subtitle = when {
                    isOn && state.clockedInSince != null -> state.clockedInSince ?: ""
                    state.displayName.isNotBlank() -> state.displayName
                    else -> "Tap to open clock screen"
                }
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
