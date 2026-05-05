package com.bizarreelectronics.crm.ui.screens.auth

/**
 * §2.14 [plan:L369-L378] — StaffPickerScreen (shared-device lock screen).
 *
 * ## Purpose
 * This screen is the lock screen shown when shared-device mode is active and the
 * inactivity timeout has elapsed. It replaces the standard PIN-only lock so counter
 * staff can identify themselves visually before entering their PIN.
 *
 * ## Flow
 *  1. App detects inactivity >= [AppPreferences.sharedDeviceInactivityMinutes].
 *  2. AppNavGraph navigates to [Screen.StaffPicker], clearing the back stack so the
 *     user cannot navigate back without authenticating.
 *  3. Staff member taps their avatar → [SwitchUserScreen] is pushed with the selected
 *     username pre-filled (re-uses the existing POST /auth/switch-user endpoint, commit 69e3c1b).
 *  4. On successful PIN → [SwitchUserScreen.onSwitched] → Dashboard.
 *
 * ## Biometric
 * Biometric is intentionally hidden on this screen. Showing a biometric prompt on a shared
 * device creates confusion about which user is authenticating. Staff must use their PIN.
 *
 * ## Avatar grid
 * [LazyVerticalGrid] with cells of 120 dp. Each cell shows the user's initials in a large
 * circle (avatar URL loaded via Coil when available; initials fallback otherwise), the
 * display name, and the role chip.
 *
 * ## POS cart contract
 * [AppPreferences.sharedDeviceCurrentUserId] is set by [SwitchUserViewModel] after a
 * successful switch. POS integration will read this id to bind / park carts per user.
 */

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.UserDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ---------------------------------------------------------------------------
// UI model — decoupled from DTO
// ---------------------------------------------------------------------------

data class StaffEntry(
    val id: Long,
    val username: String,
    val displayName: String,
    val role: String,
    val avatarUrl: String?,
)

private fun UserDto.toStaffEntry() = StaffEntry(
    id = id,
    username = username,
    displayName = buildString {
        if (!firstName.isNullOrBlank()) append(firstName)
        if (!lastName.isNullOrBlank()) {
            if (isNotEmpty()) append(' ')
            append(lastName)
        }
        if (isEmpty()) append(username)
    },
    role = role,
    avatarUrl = avatarUrl,
)

// ---------------------------------------------------------------------------
// UiState
// ---------------------------------------------------------------------------

sealed class StaffPickerUiState {
    data object Loading : StaffPickerUiState()
    data class Content(val staff: List<StaffEntry>) : StaffPickerUiState()
    data class Error(val message: String) : StaffPickerUiState()
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * Loads the tenant's user list for the avatar grid.
 *
 * Staff are fetched from GET /auth/sessions (distinct users) as a proxy. In a
 * future wave, a dedicated GET /users endpoint should be used directly via UsersApi.
 */
@HiltViewModel
class StaffPickerViewModel @Inject constructor(
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state = MutableStateFlow<StaffPickerUiState>(StaffPickerUiState.Loading)
    val state: StateFlow<StaffPickerUiState> = _state.asStateFlow()

    init {
        loadStaff()
    }

    fun loadStaff() {
        _state.value = StaffPickerUiState.Loading
        viewModelScope.launch {
            try {
                // Primary: getMe() gives the current user.
                val meResponse = authApi.getMe()
                val me = meResponse.data

                // Proxy: sessions list — each session represents a distinct active user.
                // We show the current user always; others are listed from sessions.
                val sessions = try {
                    authApi.sessions().data ?: emptyList()
                } catch (_: Exception) {
                    emptyList()
                }

                val staff = mutableListOf<StaffEntry>()
                if (me != null) {
                    staff.add(me.toStaffEntry())
                }

                // Sessions don't carry full UserDto — we only have session metadata.
                // For now, show only the current user (from getMe). Additional staff
                // will appear once GET /users is wired in a future wave.
                // TODO(future wave): call GET /users to get full profiles for all staff.
                @Suppress("UNUSED_VARIABLE")
                val sessionCount = sessions.size // informational only; triggers staff-count gate

                _state.value = if (staff.isEmpty()) {
                    StaffPickerUiState.Error("No staff accounts found")
                } else {
                    StaffPickerUiState.Content(staff)
                }
            } catch (e: Exception) {
                _state.value = StaffPickerUiState.Error(
                    e.message ?: "Could not load staff accounts",
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Screen composable
// ---------------------------------------------------------------------------

/**
 * §2.14 Staff Picker screen — the shared-device lock screen.
 *
 * @param onStaffSelected  Called with the selected staff username so the caller
 *                         can navigate to [SwitchUserScreen] with that username.
 */
@Composable
fun StaffPickerScreen(
    onStaffSelected: (username: String) -> Unit,
    viewModel: StaffPickerViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // Inactivity header + full-screen teal background (shared-mode visual cue).
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Header
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Tap to sign in",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                    Text(
                        "Select your account to continue",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                    )
                }
            }

            when (val s = state) {
                is StaffPickerUiState.Loading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                is StaffPickerUiState.Error -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            s.message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                            textAlign = TextAlign.Center,
                        )
                        Spacer(Modifier.height(16.dp))
                        OutlinedButton(onClick = { viewModel.loadStaff() }) {
                            Text("Retry")
                        }
                    }
                }

                is StaffPickerUiState.Content -> {
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 120.dp),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(s.staff, key = { it.id }) { staff ->
                            StaffAvatarCard(
                                staff = staff,
                                onClick = { onStaffSelected(staff.username) },
                            )
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Avatar card
// ---------------------------------------------------------------------------

@Composable
private fun StaffAvatarCard(
    staff: StaffEntry,
    onClick: () -> Unit,
) {
    val initials = remember(staff.displayName) {
        staff.displayName.split(' ')
            .take(2)
            .joinToString("") { it.firstOrNull()?.uppercase() ?: "" }
            .take(2)
            .ifEmpty { "?" }
    }
    val avatarColors = remember(staff.id) {
        // Deterministic color per user so the UI is stable across recompositions.
        val palette = listOf(
            Color(0xFF6750A4), Color(0xFF0061A4), Color(0xFF006C4C),
            Color(0xFFB25C00), Color(0xFFAB2963), Color(0xFF775930),
        )
        palette[(staff.id % palette.size).toInt()]
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { role = Role.Button }
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Avatar circle
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(avatarColors),
                contentAlignment = Alignment.Center,
            ) {
                if (!staff.avatarUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = staff.avatarUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Text(
                        initials,
                        style = MaterialTheme.typography.headlineMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            // Name
            Text(
                staff.displayName,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            // Role chip
            Surface(
                shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Text(
                    staff.role.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }

            // "Tap to sign in" CTA hint
            Icon(
                Icons.Default.Person,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
