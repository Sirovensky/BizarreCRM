package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class DataSettingsEvent {
    data object CacheCleared : DataSettingsEvent()
    data object DefaultsReset : DataSettingsEvent()
    data class Error(val message: String) : DataSettingsEvent()
}

@HiltViewModel
class DataSettingsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val database: BizarreDatabase,
    private val appPreferences: AppPreferences,
    @Suppress("UnusedPrivateMember") private val syncManager: SyncManager,
) : ViewModel() {

    private val _event = MutableStateFlow<DataSettingsEvent?>(null)
    val event: StateFlow<DataSettingsEvent?> = _event.asStateFlow()

    /**
     * Clear the local Coil image disk cache and recent-search history.
     * Does NOT clear Room DB — that would require a full re-sync.
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                // Coil's disk cache lives under cacheDir by default.
                // Delete sub-directories other than code_cache (system-managed).
                context.cacheDir.listFiles()
                    ?.filter { it.name != "code_cache" }
                    ?.forEach { it.deleteRecursively() }
                appPreferences.clearRecentSearches()
                _event.value = DataSettingsEvent.CacheCleared
            } catch (e: Exception) {
                _event.value = DataSettingsEvent.Error("Failed to clear cache: ${e.message}")
            }
        }
    }

    /**
     * Reset local-only AppPreferences to their defaults.
     * Does NOT clear credentials, PIN, or session tokens.
     * Does NOT delete Room data — that requires re-auth (see logout).
     */
    fun resetToDefaults() {
        viewModelScope.launch {
            try {
                appPreferences.darkMode = "system"
                appPreferences.dynamicColorEnabled = false
                appPreferences.reduceMotionEnabled = false
                appPreferences.hapticEnabled = true
                appPreferences.keepScreenOn = false
                appPreferences.clearRecentSearches()
                _event.value = DataSettingsEvent.DefaultsReset
            } catch (e: Exception) {
                _event.value = DataSettingsEvent.Error("Reset failed: ${e.message}")
            }
        }
    }

    fun consumeEvent() {
        _event.value = null
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataSettingsScreen(
    onBack: () -> Unit,
    onImport: (() -> Unit)? = null,
    onExport: (() -> Unit)? = null,
    viewModel: DataSettingsViewModel = hiltViewModel(),
) {
    val snackbarHostState = remember { SnackbarHostState() }
    var showClearCacheConfirm by remember { mutableStateOf(false) }
    var showResetDefaultsConfirm by remember { mutableStateOf(false) }
    val event by viewModel.event.collectAsStateWithLifecycle()

    LaunchedEffect(event) {
        event?.let { e ->
            when (e) {
                is DataSettingsEvent.CacheCleared -> snackbarHostState.showSnackbar("Cache cleared")
                is DataSettingsEvent.DefaultsReset -> snackbarHostState.showSnackbar("Settings reset to defaults")
                is DataSettingsEvent.Error -> snackbarHostState.showSnackbar(e.message)
            }
            viewModel.consumeEvent()
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Data") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (onImport != null || onExport != null) {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column {
                        Text(
                            "Import & Export",
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
                        )
                        if (onImport != null) {
                            DataSettingsRow(
                                icon = { Icon(Icons.Default.CloudUpload, contentDescription = "Import data") },
                                title = "Import data",
                                subtitle = "Upload CSV / JSON files",
                                onClick = onImport,
                            )
                        }
                        if (onExport != null) {
                            DataSettingsRow(
                                icon = { Icon(Icons.Default.CloudDownload, contentDescription = "Export data") },
                                title = "Export data",
                                subtitle = "Download tickets, customers, invoices",
                                onClick = onExport,
                            )
                        }
                    }
                }
            }

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column {
                    Text(
                        "Maintenance",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
                    )
                    DataSettingsRow(
                        icon = { Icon(Icons.Default.DeleteSweep, contentDescription = "Clear cache") },
                        title = "Clear cache",
                        subtitle = "Remove cached images and recent searches",
                        onClick = { showClearCacheConfirm = true },
                    )
                    DataSettingsRow(
                        icon = { Icon(Icons.Default.Restore, contentDescription = "Reset to defaults") },
                        title = "Reset to defaults",
                        subtitle = "Restore appearance and device preferences",
                        onClick = { showResetDefaultsConfirm = true },
                    )
                }
            }
        }
    }

    if (showClearCacheConfirm) {
        ConfirmDialog(
            title = "Clear cache",
            message = "Cached images and recent searches will be removed. Repair data is not affected.",
            confirmLabel = "Clear",
            onConfirm = {
                showClearCacheConfirm = false
                viewModel.clearCache()
            },
            onDismiss = { showClearCacheConfirm = false },
            isDestructive = true,
        )
    }

    if (showResetDefaultsConfirm) {
        ConfirmDialog(
            title = "Reset to defaults",
            message = "Theme, density, motion, and other device preferences will return to defaults. Your data and credentials are not affected.",
            confirmLabel = "Reset",
            onConfirm = {
                showResetDefaultsConfirm = false
                viewModel.resetToDefaults()
            },
            onDismiss = { showResetDefaultsConfirm = false },
            isDestructive = true,
        )
    }
}

@Composable
private fun DataSettingsRow(
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .semantics(mergeDescendants = true) { role = Role.Button }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant) {
            icon()
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.secondary,
            modifier = Modifier.size(20.dp),
        )
    }
}
