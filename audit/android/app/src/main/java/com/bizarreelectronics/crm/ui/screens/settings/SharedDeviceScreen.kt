package com.bizarreelectronics.crm.ui.screens.settings

/**
 * §2.14 [plan:L369-L378] — Shared-Device Mode settings sub-screen.
 *
 * ## Navigation entry point
 * Settings > "Shared Device Mode" row → [SharedDeviceScreen].
 * The row is gated behind a manager-PIN prompt at the navigation call site
 * (AppNavGraph passes [requiresManagerPin] = true; the route guard checks
 * whether the current session role == "admin" and if not, shows a
 * [SwitchUserScreen]-style PIN dialog before composing this screen).
 *
 * ## What this screen does
 *  1. Master switch — enable/disable shared-device mode.
 *  2. Device-secure check — disables the switch + shows an info card when
 *     [KeyguardManager.isDeviceSecure] is false.
 *  3. Inactivity slider — {5 / 10 / 15 / 30 min / 4 h}. Default 10 min.
 *  4. Info card — explains the counter/kiosk contract to the admin.
 *
 * ## Single-user safety
 * When [SharedDeviceUiState.sharedDeviceEnabled] is false, only this screen is
 * affected. All other authentication flows remain on the §2.5 single-user path.
 */

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.SessionTimeoutConfig

/**
 * §2.14 Shared-Device Mode screen composable.
 *
 * @param onBack Navigate back to Settings.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SharedDeviceScreen(
    onBack: () -> Unit,
    viewModel: SharedDeviceViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Shared Device Mode",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {

            // ── Info card ─────────────────────────────────────────────────────
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                ),
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        Icons.Default.Info,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSecondaryContainer,
                        modifier = Modifier
                            .size(20.dp)
                            .padding(top = 2.dp),
                    )
                    Text(
                        text = "When enabled, the app locks to a user-picker screen after " +
                            "inactivity. Staff swap by tapping their avatar and entering their PIN.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }

            // ── Device-secure warning (shown when screen lock is absent) ──────
            if (!state.isDeviceSecure) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                    ),
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            Icons.Default.Security,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier
                                .size(20.dp)
                                .padding(top = 2.dp),
                        )
                        Text(
                            text = "Enable a device lock screen to use shared mode. " +
                                "Go to Settings > Security > Screen lock.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }

            // ── Master toggle ─────────────────────────────────────────────────
            Card(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.Groups,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Shared Device Mode",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        val subtitle = when {
                            !state.isDeviceSecure ->
                                "Requires a device screen lock"
                            state.hasEnoughStaff == false ->
                                "Requires at least 2 staff accounts"
                            state.hasEnoughStaff == null && state.isLoadingStaff ->
                                "Checking staff accounts…"
                            else ->
                                if (state.sharedDeviceEnabled) "On — staff picker active"
                                else "Off — single-user mode"
                        }
                        Text(
                            subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    // Status badge (On/Off) next to the switch
                    val badgeText = if (state.sharedDeviceEnabled) "On" else "Off"
                    val badgeColor = if (state.sharedDeviceEnabled)
                        MaterialTheme.colorScheme.primary
                    else
                        MaterialTheme.colorScheme.outline
                    Surface(
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
                        color = badgeColor.copy(alpha = 0.15f),
                        modifier = Modifier.padding(end = 8.dp),
                    ) {
                        Text(
                            badgeText,
                            style = MaterialTheme.typography.labelSmall,
                            color = badgeColor,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        )
                    }
                    Switch(
                        checked = state.sharedDeviceEnabled,
                        onCheckedChange = { viewModel.setSharedDeviceEnabled(it) },
                        enabled = state.isDeviceSecure && state.hasEnoughStaff != false,
                        modifier = Modifier.semantics {
                            contentDescription = "Shared device mode toggle, currently " +
                                if (state.sharedDeviceEnabled) "on" else "off"
                        },
                    )
                }
            }

            // ── Inactivity slider (only shown when mode is on) ────────────────
            if (state.sharedDeviceEnabled) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.Lock,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text(
                                    "Lock after inactivity",
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    inactivityLabel(state.inactivityMinutes),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }
                        }

                        // Discrete slider — steps = allowed options
                        val options = SessionTimeoutConfig.ALLOWED_INACTIVITY_MINUTES
                        val currentIndex = options.indexOf(state.inactivityMinutes)
                            .coerceAtLeast(0)
                        val sliderSteps = options.size - 2 // steps = n-2 for n positions

                        Slider(
                            value = currentIndex.toFloat(),
                            onValueChange = { raw ->
                                val idx = raw.toInt().coerceIn(0, options.lastIndex)
                                viewModel.setInactivityMinutes(options[idx])
                            },
                            valueRange = 0f..(options.lastIndex.toFloat()),
                            steps = sliderSteps,
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics {
                                    contentDescription = "Inactivity timeout: ${inactivityLabel(state.inactivityMinutes)}"
                                },
                        )

                        // Tick labels
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            options.forEach { min ->
                                Text(
                                    inactivityLabel(min),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (min == state.inactivityMinutes)
                                        MaterialTheme.colorScheme.primary
                                    else
                                        MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }

            // ── Staff count warning (visible when check failed or indeterminate) ──
            if (state.staffLoadError != null) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f),
                    ),
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Could not verify staff accounts",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                            )
                        }
                        TextButton(onClick = { viewModel.loadStaffCount() }) {
                            Text("Retry", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Human-readable label for an inactivity duration in minutes.
 * 240 minutes is displayed as "4 h" for readability on the tick row.
 */
private fun inactivityLabel(minutes: Int): String = when (minutes) {
    5    -> "5 min"
    10   -> "10 min"
    15   -> "15 min"
    30   -> "30 min"
    240  -> "4 h"
    else -> "$minutes min"
}
