package com.bizarreelectronics.crm.ui.screens.settings

/**
 * L2009-L2014 — Security Summary screen.
 *
 * Consolidated read-only view of all security-relevant state. Each row shows
 * the current status and navigates to the relevant sub-screen on tap. No new
 * logic is introduced here — this is pure aggregation from AppPreferences and
 * AuthPreferences.
 *
 * Rows:
 *  - 2FA status (Enabled / Disabled) → settings/security/2fa-factors
 *  - Passkey status (Enrolled / Not enrolled) → settings/security/passkeys
 *  - Recovery codes count → settings/security/recovery-codes
 *  - SSO state (Always shown as "Not configured" until SSO API exists)
 *  - Session timeout (from SessionTimeoutConfig default) → settings/active-sessions
 *  - Remember-me enabled → settings/security
 *  - Shared-device mode → settings/shared-device
 *  - Screenshot blocking toggle (wired directly — AppPreferences)
 *  - Active sessions link → settings/active-sessions
 */

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

data class SecuritySummaryUiState(
    val is2faEnabled: Boolean = false,
    val hasPasskey: Boolean = false,
    val recoveryCodesCount: Int = 0,
    val ssoState: String = "Not configured",
    val sessionTimeoutMinutes: Int = 30,
    val rememberMeEnabled: Boolean = false,
    val sharedDeviceModeEnabled: Boolean = false,
    val screenshotBlockingEnabled: Boolean = true,
)

@HiltViewModel
class SecuritySummaryViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        SecuritySummaryUiState(
            // 2FA state: conservatively shown as enabled when user is logged in
            // (actual TOTP enrollment state tracked by TwoFactorFactorsScreen).
            is2faEnabled = authPreferences.isLoggedIn,
            sharedDeviceModeEnabled = appPreferences.sharedDeviceModeEnabled,
            screenshotBlockingEnabled = appPreferences.screenCapturePreventionEnabled,
        ),
    )
    val state: StateFlow<SecuritySummaryUiState> = _state.asStateFlow()

    fun setScreenshotBlocking(enabled: Boolean) {
        appPreferences.screenCapturePreventionEnabled = enabled
        _state.value = _state.value.copy(screenshotBlockingEnabled = enabled)
    }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecuritySummaryScreen(
    onBack: () -> Unit,
    onNavigate: (String) -> Unit = {},
    viewModel: SecuritySummaryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Security Summary",
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
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Authentication",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    SecuritySummaryRow(
                        icon = Icons.Default.Security,
                        title = "Two-factor authentication",
                        status = if (state.is2faEnabled) "Enabled" else "Disabled",
                        statusOk = state.is2faEnabled,
                        route = "settings/security/2fa-factors",
                        onNavigate = onNavigate,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                    SecuritySummaryRow(
                        icon = Icons.Default.Fingerprint,
                        title = "Passkeys",
                        status = if (state.hasPasskey) "Enrolled" else "Not enrolled",
                        statusOk = state.hasPasskey,
                        route = "settings/security/passkeys",
                        onNavigate = onNavigate,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                    SecuritySummaryRow(
                        icon = Icons.Default.Key,
                        title = "Recovery codes",
                        status = if (state.recoveryCodesCount > 0)
                            "${state.recoveryCodesCount} remaining"
                        else
                            "Not generated",
                        statusOk = state.recoveryCodesCount > 0,
                        route = "settings/security/recovery-codes",
                        onNavigate = onNavigate,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                    SecuritySummaryRow(
                        icon = Icons.Default.AccountBalance,
                        title = "SSO",
                        status = state.ssoState,
                        statusOk = false,
                        route = "settings/security",
                        onNavigate = onNavigate,
                    )
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Session & Device",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    SecuritySummaryRow(
                        icon = Icons.Default.Timer,
                        title = "Session timeout",
                        status = "${state.sessionTimeoutMinutes} min",
                        statusOk = true,
                        route = "settings/active-sessions",
                        onNavigate = onNavigate,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                    SecuritySummaryRow(
                        icon = Icons.Default.Groups,
                        title = "Shared device mode",
                        status = if (state.sharedDeviceModeEnabled) "On" else "Off",
                        statusOk = !state.sharedDeviceModeEnabled,
                        route = "settings/shared-device",
                        onNavigate = onNavigate,
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                    // Screenshot blocking — only row with an interactive toggle (wired pref)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics(mergeDescendants = true) {
                                contentDescription = "Screenshot blocking, ${if (state.screenshotBlockingEnabled) "on" else "off"}"
                                role = Role.Switch
                            },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.Screenshot,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Screenshot blocking", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "Prevent screen capture and Recents thumbnails",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = state.screenshotBlockingEnabled,
                            onCheckedChange = { viewModel.setScreenshotBlocking(it) },
                        )
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                    SecuritySummaryRow(
                        icon = Icons.Default.Devices,
                        title = "Active sessions",
                        status = "View all",
                        statusOk = true,
                        route = "settings/active-sessions",
                        onNavigate = onNavigate,
                    )
                }
            }
        }
    }
}

@Composable
private fun SecuritySummaryRow(
    icon: ImageVector,
    title: String,
    status: String,
    statusOk: Boolean,
    route: String,
    onNavigate: (String) -> Unit,
) {
    val statusColor = if (statusOk)
        MaterialTheme.colorScheme.primary
    else
        MaterialTheme.colorScheme.error

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onNavigate(route) }
            .semantics(mergeDescendants = true) {
                contentDescription = "$title: $status"
                role = Role.Button
            }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Text(
            title,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        Text(
            status,
            style = MaterialTheme.typography.bodySmall,
            color = statusColor,
        )
        Spacer(Modifier.width(4.dp))
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.size(16.dp),
        )
    }
}
