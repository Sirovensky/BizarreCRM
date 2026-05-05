package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import android.content.Context
import com.bizarreelectronics.crm.R
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.service.ClockInTileService
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.widget.glance.publishClockState
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import javax.inject.Inject

/**
 * §3.11 — dashboard tile that surfaces the signed-in employee's clock
 * status + routes to the dedicated ClockInOutScreen on tap.
 *
 * Pulls `GET /employees`, finds the row matching `AuthPreferences.userId`,
 * reads `isClockedIn`. If the lookup fails (offline, role doesn't see
 * employees, etc.) the tile renders a neutral "Open clock in/out" state
 * — the screen itself is the source of truth on action.
 */
data class ClockInTileState(
    val isClockedIn: Boolean? = null,
    val displayName: String = "",
    /** §3.8 L557 — non-null after a successful toggle; cleared on next tap. */
    val justClockedInAt: String? = null,
    val isLoading: Boolean = false,
)

@HiltViewModel
class ClockInTileViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    private val authPreferences: AuthPreferences,
    @ApplicationContext private val appContext: Context,
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
        viewModelScope.launch {
            runCatching {
                val response = settingsApi.getEmployees()
                val me = response.data?.firstOrNull { it.id == authPreferences.userId }
                _state.value = _state.value.copy(isClockedIn = me?.isClockedIn)
            }
        }
    }

    /**
     * §3.8 L557 — One-tap toggle. Calls clock-in or clock-out based on current state.
     *
     * On success, sets [ClockInTileState.justClockedInAt] to the current HH:MM so
     * the Composable can show a Snackbar. On failure, silently falls back to [onOpen].
     *
     * @param onFallbackToScreen Called when toggle fails (e.g. PIN required) so the
     *   caller can navigate to [ClockInOutScreen] for the full flow.
     * @param onSuccess Callback supplying the clock-in time string ("Clocked in at HH:MM").
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
                    _state.value = _state.value.copy(isClockedIn = false, isLoading = false)
                    // §14.10 — sync QS tile + Glance widget
                    broadcastClockState(isClockedIn = false)
                    onSuccess("Clocked out")
                } else {
                    settingsApi.clockIn(userId, emptyMap())
                    val timeStr = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
                    _state.value = _state.value.copy(isClockedIn = true, justClockedInAt = timeStr, isLoading = false)
                    // §14.10 — sync QS tile + Glance widget
                    broadcastClockState(isClockedIn = true)
                    onSuccess("Clocked in at $timeStr")
                }
            }.onFailure {
                _state.value = _state.value.copy(isLoading = false)
                android.util.Log.w("ClockInTile", "toggle failed: ${it.message}")
                onFallbackToScreen()
            }
        }
    }

    /**
     * §14.10 — Writes the clock state to both the Quick Settings tile's
     * SharedPreferences and the Glance home-screen widget DataStore so both
     * surfaces reflect the new state without requiring the user to open the app.
     *
     * Failures are logged and swallowed — the QS tile and widget are decorative;
     * a failure here should never block the clock-in/out action itself.
     */
    private suspend fun broadcastClockState(isClockedIn: Boolean) {
        val displayName = buildString {
            append(authPreferences.userFirstName.orEmpty())
            val last = authPreferences.userLastName.orEmpty()
            if (last.isNotBlank()) {
                if (isNotEmpty()) append(" ")
                append(last)
            }
        }.ifBlank { authPreferences.username.orEmpty() }

        runCatching {
            ClockInTileService.persistClockState(
                context = appContext,
                isClockedIn = isClockedIn,
            )
        }.onFailure { android.util.Log.w("ClockInTile", "tile persist failed: ${it.message}") }

        runCatching {
            publishClockState(
                context = appContext,
                isClockedIn = isClockedIn,
                employeeName = displayName,
            )
        }.onFailure { android.util.Log.w("ClockInTile", "widget publish failed: ${it.message}") }
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
    val context = LocalContext.current

    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            // §26.1 — merge children so TalkBack reads the tile as one labeled action.
            // stateDescription announces the clocked-in/out state change when it
            // flips so TalkBack users do not have to navigate back to the tile.
            // §22.3 — hand pointer on tablet / desktop hover.
            .semantics(mergeDescendants = true) {
                role = Role.Button
                // §26.1 — stateDescription for toggle-like rows
                contentDescription = when (state.isClockedIn) {
                    true -> context.getString(
                        R.string.a11y_clock_in_tile_on,
                        state.displayName.ifBlank { "employee" },
                    )
                    false -> context.getString(
                        R.string.a11y_clock_in_tile_off,
                        state.displayName.ifBlank { "employee" },
                    )
                    null -> context.getString(
                        R.string.a11y_clock_in_tile_unknown,
                        state.displayName.ifBlank { "employee" },
                    )
                }
                stateDescription = if (isOn) context.getString(R.string.a11y_toggle_on)
                                   else context.getString(R.string.a11y_toggle_off)
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
            // Status dot pulses green when clocked in, neutral otherwise.
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
                Text(
                    text = if (state.displayName.isNotBlank()) state.displayName else "Tap to open clock screen",
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
