package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.clearUserData
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.service.WebSocketEventHandler
import com.bizarreelectronics.crm.service.WebSocketService
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
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
    // AUDIT-AND-024/025: injected so logout can call close() on both.
    private val webSocketService: WebSocketService,
    private val webSocketEventHandler: WebSocketEventHandler,
    syncQueueDao: SyncQueueDao,
    private val pinPreferences: com.bizarreelectronics.crm.data.local.prefs.PinPreferences,
) : ViewModel() {

    /** §2.5 — drives the PIN row label ("Set up PIN" vs "Change PIN"). */
    val pinIsSet: Boolean
        get() = pinPreferences.isPinSet

    val isSyncing: StateFlow<Boolean> = syncManager.isSyncing

    /**
     * AUD-20260414-M5: reactive dead-letter count for the "Sync Issues" tile
     * badge. Collected as a StateFlow so the tile disappears the moment the
     * last dead-letter entry is resurrected from the SyncIssuesScreen.
     */
    val deadLetterCount: StateFlow<Int> = syncQueueDao.getDeadLetterCount()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = 0,
        )

    private val _syncTriggered = MutableStateFlow(false)
    val syncTriggered: StateFlow<Boolean> = _syncTriggered.asStateFlow()

    // CROSS39 + CROSS46: render the raw "YYYY-MM-DD HH:MM:SS" timestamp as
    // "just now" / "5 min ago" / "April 16, 2026 at 9:17 PM". Fresh samples
    // stay relative via the canonical DateFormatter.formatRelative; anything
    // ≥1 day old flips to the canonical absolute + time-of-day composition.
    private fun formatLastSync(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        // Server stores timestamps in UTC ("YYYY-MM-DD HH:MM:SS"). Old code
        // parsed them with the device's local zone, which produced bogus
        // future timestamps for users east of UTC and made
        // DateUtils.getRelativeTimeSpanString render them as "In 5 hr".
        // Anchor at UTC, then convert to epoch-ms before relative-format.
        val epochMs = runCatching {
            val normalized = raw.replace(' ', 'T')
            java.time.LocalDateTime.parse(normalized)
                .atZone(java.time.ZoneOffset.UTC)
                .toInstant()
                .toEpochMilli()
        }.getOrNull() ?: return raw
        val ageSec = (System.currentTimeMillis() - epochMs) / 1000
        return if (ageSec < 86_400) {
            com.bizarreelectronics.crm.util.DateFormatter.formatRelative(epochMs)
        } else {
            val date = com.bizarreelectronics.crm.util.DateFormatter.formatAbsolute(epochMs)
            val time = com.bizarreelectronics.crm.util.DateFormatter.formatTimeOfDay(epochMs)
            "$date at $time"
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
            // AUDIT-AND-024/025: stop WebSocket coroutines BEFORE clearing auth
            // prefs so the reconnect loop cannot fire a reconnection attempt
            // with a now-stale token while we're mid-logout.
            webSocketService.close()
            webSocketEventHandler.close()
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
            // §2.5 — drop PIN metadata on logout so next sign-in starts
            // with a clean slate (server still owns the PIN; this only
            // clears local lockout counters + isPinSet flag).
            pinPreferences.reset()
            onDone()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onLogout: (() -> Unit)? = null,
    onEditProfile: (() -> Unit)? = null,
    // CROSS38b-notif: navigate to the Notifications preferences sub-page.
    // Nullable so previews and any callers that don't want the row can omit
    // the wiring. Rendered as a top-level SettingsRow under SETTINGS.
    onNotificationSettings: (() -> Unit)? = null,
    // AUD-20260414-M5: navigate to the Sync Issues diagnostic screen. Tile
    // is gated on deadLetterCount > 0 so callers never see it unless there
    // is actually something to retry.
    onSyncIssues: (() -> Unit)? = null,
    // §2.5 PIN — opens the PinSetupScreen. Row label flips between
    // "Set up PIN" / "Change PIN" based on PinPreferences.isPinSet.
    onPinSetup: (() -> Unit)? = null,
    // §32.3 — opens the Crash reports diagnostic screen.
    onCrashReports: (() -> Unit)? = null,
    // §28 — opens About + diagnostics screen (copy-bundle for support).
    onAbout: (() -> Unit)? = null,
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
            // CROSS38b: promote Edit Profile to a dedicated top-level row so
            // password/PIN changes aren't buried inside the user-info card.
            // Matches the card-with-clickable-row pattern used elsewhere on
            // this screen. Hidden when no callback is provided (e.g. previews).
            if (onEditProfile != null) {
                SettingsRow(
                    icon = Icons.Default.Person,
                    title = "Edit Profile",
                    onClick = onEditProfile,
                )
            }

            // CROSS38b-notif: Notifications preferences sub-page. Distinct
            // from the Notifications inbox listed under More > SETTINGS per
            // CROSS54 — this configures which events should fire, the inbox
            // lists events that have already fired. Same SettingsRow shape
            // as Edit Profile so both top-level entries read identically.
            if (onNotificationSettings != null) {
                SettingsRow(
                    icon = Icons.Default.Notifications,
                    title = "Notifications",
                    onClick = onNotificationSettings,
                )
            }

            // §2.5 PIN setup / change. Label flips by PIN-set state so the
            // user always sees the action that matters at the moment. Tap
            // routes to PinSetupScreen which handles both flows.
            if (onPinSetup != null) {
                val pinIsSet = viewModel.pinIsSet
                SettingsRow(
                    icon = Icons.Default.Lock,
                    title = if (pinIsSet) "Change PIN" else "Set up PIN",
                    onClick = onPinSetup,
                )
            }

            // §32.3 — Diagnostics → Crash reports. Visible whenever the
            // callback is wired; the screen handles the empty case so the
            // row never lies about "no crashes" before the user opens it.
            if (onCrashReports != null) {
                SettingsRow(
                    icon = Icons.Default.BugReport,
                    title = "Crash reports",
                    onClick = onCrashReports,
                )
            }

            // §28 — About + diagnostics. Copy-bundle for support tickets.
            if (onAbout != null) {
                SettingsRow(
                    icon = Icons.Default.Info,
                    title = "About",
                    onClick = onAbout,
                )
            }

            // AUD-20260414-M5: "Sync Issues" tile with red badge showing the
            // number of dead-letter sync_queue rows. Tile is hidden entirely
            // when the count is zero — the common case — so the user only
            // ever sees it during an actual failure state. A tap lands on
            // the SyncIssuesScreen where each entry can be retried.
            val deadLetterCount by viewModel.deadLetterCount.collectAsState()
            if (onSyncIssues != null && deadLetterCount > 0) {
                SyncIssuesTileRow(
                    count = deadLetterCount,
                    onClick = onSyncIssues,
                )
            }

            // Server info
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Server connection", style = MaterialTheme.typography.titleSmall)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(
                            Icons.Default.Dns,
                            // decorative — non-clickable info row; sibling server URL Text carries the announcement
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
                                // decorative — non-clickable info row; sibling storeName Text carries the announcement
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
                        // CROSS40: Title-case the role label for consistency with
                        // the Employee list role chip (which uses "Admin" / "Manager"
                        // / "Technician"). Underlying stored value is lowercase.
                        "Role: ${(auth.userRole ?: "—").replaceFirstChar { it.uppercase() }}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    // CROSS38b-cleanup: inline Edit-Profile row removed;
                    // the dedicated top-level SettingsRow above is the canonical entry.
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
                            // decorative — OutlinedButton's "Sync now" Text supplies the accessible name
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
                // decorative — Button's "Sign out" Text supplies the accessible name
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

/**
 * AUD-20260414-M5: "Sync Issues" tile. Same shape as [SettingsRow] but the
 * trailing slot is a red badge chip with the failure count instead of a
 * navigation chevron, so it screams "something is wrong" without being an
 * in-your-face error banner. Icon is CloudOff for continuity with the
 * offline/sync iconography used by SyncStatusBadge.
 *
 * Only rendered when count > 0 — the common "healthy" state is zero rows
 * and the caller simply omits the tile.
 */
@Composable
private fun SyncIssuesTileRow(
    count: Int,
    onClick: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onClick() }
                // D5-1: collapse leading icon + title + badge into a single
                // TalkBack focus item announced as "Sync issues, N unresolved,
                // button" (the badge Text carries the count).
                .semantics(mergeDescendants = true) { role = Role.Button }
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                // Cloud-off aligns with the iconography on SyncStatusBadge
                // and the offline banner. The error color below communicates
                // the severity, so the icon itself stays neutral.
                Icons.Default.CloudOff,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.error,
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Sync issues",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = if (count == 1) "1 change failed to sync" else "$count changes failed to sync",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            // Red badge chip with the failure count. Uses a Surface so the
            // shape + color are painted atomically — rolling our own
            // drawBehind would skip the onClick ripple boundary on Android 14+.
            Surface(
                shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError,
            ) {
                Text(
                    text = count.toString(),
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
        }
    }
}

/**
 * Top-level settings row rendered as a Card with a clickable row inside.
 * Mirrors the in-card clickable row pattern already used for the existing
 * Edit-Profile entry under Signed-In-As so the visual weight matches other
 * primary Settings entries (Server connection, Data sync, Device preferences).
 */
@Composable
private fun SettingsRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    onClick: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onClick() }
                // D5-1: collapse leading icon + title Text + trailing chevron
                // into a single TalkBack focus item so the row is announced as
                // "$title, button" instead of three unrelated focus stops.
                .semantics(mergeDescendants = true) { role = Role.Button }
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                icon,
                // decorative — parent Row's mergeDescendants + title Text supplies the accessible name
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
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                // decorative — trailing chevron indicating navigation; parent Row's mergeDescendants + title Text supplies the accessible name
                contentDescription = null,
                tint = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
