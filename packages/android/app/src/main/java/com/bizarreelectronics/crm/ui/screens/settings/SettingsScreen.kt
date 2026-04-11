package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
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
import com.bizarreelectronics.crm.data.sync.SyncWorker
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
    private val syncManager: SyncManager,
    private val authApi: AuthApi,
    private val database: BizarreDatabase,
) : ViewModel() {

    val isSyncing: StateFlow<Boolean> = syncManager.isSyncing

    private val _syncTriggered = MutableStateFlow(false)
    val syncTriggered: StateFlow<Boolean> = _syncTriggered.asStateFlow()

    private val _lastSyncDisplay = MutableStateFlow(appPreferences.lastFullSyncAt)
    val lastSyncDisplay: StateFlow<String?> = _lastSyncDisplay.asStateFlow()

    fun syncNow() {
        viewModelScope.launch {
            try {
                syncManager.syncAll()
                // Refresh the displayed timestamp after sync completes
                _lastSyncDisplay.value = appPreferences.lastFullSyncAt
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
        topBar = { TopAppBar(title = { Text("Settings") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Server info
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Server Connection", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Dns, null, tint = SuccessGreen, modifier = Modifier.size(16.dp))
                        Text(auth.serverUrl ?: "Not configured", style = MaterialTheme.typography.bodyMedium)
                    }
                    if (auth.storeName != null) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Default.Store, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                            Text(auth.storeName ?: "", style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }

            // User info
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Signed in as", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text(
                        buildString {
                            append(auth.userFirstName ?: "")
                            if (!auth.userLastName.isNullOrBlank()) append(" ${auth.userLastName}")
                            if (isBlank()) append(auth.username ?: "Unknown")
                        },
                        style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium,
                    )
                    Text("Role: ${auth.userRole ?: "—"}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            // Sync
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Data Sync", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
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
                            Icon(Icons.Default.Sync, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Sync Now")
                        }
                    }
                }
            }

            Spacer(Modifier.weight(1f))

            Button(
                onClick = { showLogoutConfirm = true },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
            ) {
                Icon(Icons.AutoMirrored.Filled.Logout, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Sign Out")
            }
        }
    }

    if (showLogoutConfirm) {
        AlertDialog(
            onDismissRequest = { showLogoutConfirm = false },
            title = { Text("Sign Out") },
            text = { Text("Are you sure? Any unsynced changes will be lost.") },
            confirmButton = {
                Button(
                    onClick = {
                        showLogoutConfirm = false
                        viewModel.logout { onLogout?.invoke() }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                ) { Text("Sign Out") }
            },
            dismissButton = { TextButton(onClick = { showLogoutConfirm = false }) { Text("Cancel") } },
        )
    }
}
