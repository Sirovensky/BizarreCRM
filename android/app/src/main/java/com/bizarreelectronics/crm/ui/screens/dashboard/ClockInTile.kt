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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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
)

@HiltViewModel
class ClockInTileViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
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
        viewModelScope.launch {
            runCatching {
                val response = settingsApi.getEmployees()
                val me = response.data?.firstOrNull { it.id == authPreferences.userId }
                _state.value = _state.value.copy(isClockedIn = me?.isClockedIn)
            }
        }
    }
}

@Composable
fun ClockInTile(
    onOpen: () -> Unit,
    viewModel: ClockInTileViewModel = hiltViewModel(),
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    val isOn = state.isClockedIn == true

    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            // §26.1 — merge children so TalkBack reads "Clocked in, <name>,
            // Button" as one labeled action instead of focusing the icon,
            // title, subtitle, and chevron separately.
            // §22.3 — hand pointer on tablet / desktop hover.
            .semantics(mergeDescendants = true) {
                role = Role.Button
            }
            .pointerHoverIcon(PointerIcon.Hand)
            .clickable(onClick = onOpen),
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

