package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.clearUserData
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    val authPreferences: AuthPreferences,
    val appPreferences: AppPreferences,
    val biometricAuth: BiometricAuth,
    private val syncManager: SyncManager,
    private val authApi: AuthApi,
    private val database: BizarreDatabase,
) : ViewModel() {

    val isSyncing: StateFlow<Boolean> = syncManager.isSyncing

    private val _syncTriggered = MutableStateFlow(false)
    val syncTriggered: StateFlow<Boolean> = _syncTriggered.asStateFlow()

    // CROSS39: render the raw "YYYY-MM-DD HH:MM:SS" timestamp as "a moment ago"
    // / "5 minutes ago" / "April 16 at 9:17 PM". Pure helper — no DI, no flow.
    private fun formatLastSync(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val instant = runCatching {
            val normalized = raw.replace(' ', 'T')
            java.time.LocalDateTime.parse(normalized)
                .atZone(java.time.ZoneId.systemDefault())
                .toInstant()
        }.getOrNull() ?: return raw
        val ageSec = (System.currentTimeMillis() - instant.toEpochMilli()) / 1000
        return when {
            ageSec < 60 -> "just now"
            ageSec < 3600 -> "${ageSec / 60} min ago"
            ageSec < 86_400 -> "${ageSec / 3600} hr ago"
            else -> java.time.format.DateTimeFormatter.ofPattern("LLLL d 'at' h:mm a")
                .format(instant.atZone(java.time.ZoneId.systemDefault()))
        }
    }

    private val _lastSyncDisplay = MutableStateFlow(formatLastSync(appPreferences.lastFullSyncAt))
    val lastSyncDisplay: StateFlow<String?> = _lastSyncDisplay.asStateFlow()

    // Field-use enrichment toggles (section 46). Stored in SharedPreferences
    // directly — see AppPreferences.biometricEnabled / hapticEnabled. These
    // StateFlows mirror the prefs so the UI observes updates reactively.
    private val _biometricEnabled = MutableStateFlow(appPreferences.biometricEnabled)
    val biometricEnabled: StateFlow<Boolean> = _biometricEnabled.asStateFlow()

    private val _hapticEnabled = MutableStateFlow(appPreferences.hapticEnabled)
    val hapticEnabled: StateFlow<Boolean> = _hapticEnabled.asStateFlow()

    // Dark-mode toggle: surfaces the existing AppPreferences.darkMode key ("system" | "light" | "dark").
    // Wave 1 wired darkMode to AppPreferences; we expose a boolean for simple on/off.
    // true = "dark", false = "light" (system preference ignored when user has set explicitly).
    private val _darkModeEnabled = MutableStateFlow(appPreferences.darkMode == "dark")
    val darkModeEnabled: StateFlow<Boolean> = _darkModeEnabled.asStateFlow()

    fun setBiometricEnabled(enabled: Boolean) {
        appPreferences.biometricEnabled = enabled
        _biometricEnabled.value = enabled
        // When the user turns the biometric gate OFF, any cached "unlocked"
        // state must be invalidated so the next cold start doesn't silently
        // skip the prompt if the pref flips back ON in the same process.
        // Today the only unlock state lives in MainActivity.isLocked (process-
        // local) and there is no persisted "unlockedAt" key — so there is
        // literally nothing to wipe. This is documented here so future
        // changes that DO introduce a persisted unlock ticket (e.g. an
        // auto-relock timer) remember to clear it from this branch.
        // if (!enabled) { appPreferences.biometricUnlockedAt = null }
    }

    fun setHapticEnabled(enabled: Boolean) {
        appPreferences.hapticEnabled = enabled
        _hapticEnabled.value = enabled
    }

    fun setDarkModeEnabled(enabled: Boolean) {
        appPreferences.darkMode = if (enabled) "dark" else "light"
        _darkModeEnabled.value = enabled
    }

    fun syncNow() {
        viewModelScope.launch {
            try {
                syncManager.syncAll()
                // Refresh the displayed timestamp after sync completes
                _lastSyncDisplay.value = formatLastSync(appPreferences.lastFullSyncAt)
                _syncTriggered.value = true
                kotlinx.coroutines.delay(100)
                _syncTriggered.value = false
            } catch (_: Exception) {
                _syncTriggered.value = false
            }
        }
    }

    fun logout(onDone: () -> Unit) {
        viewModelScope.launch {
            try {
                authApi.logout()
            } catch (_: Exception) {
                // Server may be unreachable — proceed with local clear regardless
            }
            // IMPORTANT: wipe the local Room cache BEFORE clearing auth prefs.
            // Another user signing in on the same device must not see the
            // previous user's customers, tickets, invoices, or SMS history.
            // clearUserData() runs in a transaction and is resilient to
            // partial failures; we still swallow exceptions so logout always
            // completes from the user's perspective.
            try {
                database.clearUserData()
            } catch (e: Exception) {
                android.util.Log.e(
                    "SettingsViewModel",
                    "clearUserData failed during logout — local cache may still contain previous user's data",
                    e,
                )
            }
            authPreferences.clear()
            onDone()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onLogout: (() -> Unit)? = null,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val auth = viewModel.authPreferences
    val isSyncing by viewModel.isSyncing.collectAsState()
    val syncTriggered by viewModel.syncTriggered.collectAsState()
    var showLogoutConfirm by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    LaunchedEffect(syncTriggered) {
        if (syncTriggered) {
            snackbarHostState.showSnackbar("Sync started")
        }
    }

    Scaffold(
        topBar = { BrandTopAppBar(title = "Settings") },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Server info
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Server connection", style = MaterialTheme.typography.titleSmall)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(
                            Icons.Default.Dns,
                            contentDescription = null,
                            tint = SuccessGreen,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(auth.serverUrl ?: "Not configured", style = MaterialTheme.typography.bodyMedium)
                    }
                    if (auth.storeName != null) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(
                                Icons.Default.Store,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(16.dp),
                            )
                            Text(auth.storeName ?: "", style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }

            // User info
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Signed in as", style = MaterialTheme.typography.titleSmall)
                    Text(
                        buildString {
                            append(auth.userFirstName ?: "")
                            if (!auth.userLastName.isNullOrBlank()) append(" ${auth.userLastName}")
                            if (isBlank()) append(auth.username ?: "Unknown")
                        },
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Text(
                        "Role: ${auth.userRole ?: "—"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Sync
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Data sync", style = MaterialTheme.typography.titleSmall)
                    val lastSync by viewModel.lastSyncDisplay.collectAsState()
                    Text(
                        "Last sync: ${lastSync ?: "Never"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(
                        onClick = { viewModel.syncNow() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isSyncing,
                    ) {
                        if (isSyncing) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text("Syncing...")
                        } else {
                            Icon(Icons.Default.Sync, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Sync now")
                        }
                    }
                }
            }

            // Device preferences: biometric, haptic, dark mode.
            // All three write straight through to SharedPreferences — no server round-trip.
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "Device preferences",
                        style = MaterialTheme.typography.titleSmall,
                    )

                    val biometricEnabled by viewModel.biometricEnabled.collectAsState()
                    val canUseBiometric = remember(context) {
                        viewModel.biometricAuth.canAuthenticate(context)
                    }
                    PreferenceRow(
                        icon = Icons.Default.Fingerprint,
                        iconDescription = "Biometric unlock",
                        title = "Biometric unlock",
                        subtitle = if (canUseBiometric)
                            "Require fingerprint or face when opening the app"
                        else
                            "No biometric enrolled on this device",
                        checked = biometricEnabled,
                        onCheckedChange = { viewModel.setBiometricEnabled(it) },
                        enabled = canUseBiometric,
                    )

                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                    )

                    val hapticEnabled by viewModel.hapticEnabled.collectAsState()
                    PreferenceRow(
                        icon = Icons.Default.Vibration,
                        iconDescription = "Haptic feedback",
                        title = "Haptic feedback",
                        subtitle = "Short vibration on save, scan, and errors",
                        checked = hapticEnabled,
                        onCheckedChange = { viewModel.setHapticEnabled(it) },
                    )

                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                    )

                    val darkModeEnabled by viewModel.darkModeEnabled.collectAsState()
                    PreferenceRow(
                        icon = Icons.Default.DarkMode,
                        iconDescription = "Dark mode",
                        title = "Dark mode",
                        subtitle = "Use dark theme (default on)",
                        checked = darkModeEnabled,
                        onCheckedChange = { viewModel.setDarkModeEnabled(it) },
                    )
                }
            }

            // CROSS38: About card — app version + build for support.
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("About", style = MaterialTheme.typography.titleSmall)
                    val pkgInfo = remember(context) {
                        try {
                            context.packageManager.getPackageInfo(context.packageName, 0)
                        } catch (_: Exception) {
                            null
                        }
                    }
                    Text(
                        "BizarreCRM Android ${pkgInfo?.versionName ?: "?"} (build ${pkgInfo?.longVersionCode ?: 0})",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            // WaveDivider — one sanctioned break above the danger zone (sign-out group).
            WaveDivider()

            Button(
                onClick = { showLogoutConfirm = true },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
            ) {
                Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Sign out")
            }
        }
    }

    // Migrate from hand-rolled AlertDialog to shared ConfirmDialog(isDestructive = true).
    if (showLogoutConfirm) {
        ConfirmDialog(
            title = "Sign out",
            message = "Are you sure? Any unsynced changes will be lost.",
            confirmLabel = "Sign out",
            onConfirm = {
                showLogoutConfirm = false
                viewModel.logout { onLogout?.invoke() }
            },
            onDismiss = { showLogoutConfirm = false },
            isDestructive = true,
        )
    }
}

/**
 * Reusable preference toggle row used within the Device Preferences card.
 * Icon tint is muted (onSurfaceVariant) per the TODO spec; purple lives on
 * the Switch thumb automatically via the theme.
 */
@Composable
private fun PreferenceRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconDescription: String,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = iconDescription,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled,
        )
    }
}
