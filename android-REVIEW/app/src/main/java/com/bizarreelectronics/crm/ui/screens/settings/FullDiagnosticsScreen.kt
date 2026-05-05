package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Context
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
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class FullDiagnosticsState(
    val serverUrl: String = "",
    val appVersion: String = "",
    val buildType: String = "",
    val commitSha: String = "",
    val recentLogs: List<String> = emptyList(),
    val isSyncing: Boolean = false,
    val syncMessage: String? = null,
)

@HiltViewModel
class FullDiagnosticsViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val authPreferences: AuthPreferences,
    private val syncManager: SyncManager,
    private val breadcrumbs: com.bizarreelectronics.crm.util.Breadcrumbs,
) : ViewModel() {

    private val _uiState = MutableStateFlow(FullDiagnosticsState())
    val uiState: StateFlow<FullDiagnosticsState> = _uiState.asStateFlow()

    val isSyncing: StateFlow<Boolean> = syncManager.isSyncing

    init {
        load()
    }

    private fun load() {
        val pkgInfo = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0)
        }.getOrNull()
        _uiState.value = FullDiagnosticsState(
            serverUrl = authPreferences.serverUrl ?: "(not configured)",
            appVersion = "${pkgInfo?.versionName ?: BuildConfig.VERSION_NAME} (${pkgInfo?.longVersionCode ?: BuildConfig.VERSION_CODE})",
            buildType = if (BuildConfig.DEBUG) "debug" else "release",
            // BUILD_COMMIT_SHA is an optional BuildConfig field injected via Gradle.
            // Falls back to empty string when not configured.
            commitSha = runCatching {
                BuildConfig::class.java.getField("BUILD_COMMIT_SHA").get(null) as? String ?: ""
            }.getOrDefault(""),
            recentLogs = breadcrumbs.recent().takeLast(200),
        )
    }

    fun forceSyncNow() {
        viewModelScope.launch {
            try {
                syncManager.syncAll()
                _uiState.value = _uiState.value.copy(syncMessage = "Sync triggered")
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(syncMessage = "Sync failed: ${e.message}")
            }
        }
    }

    fun clearSyncMessage() {
        _uiState.value = _uiState.value.copy(syncMessage = null)
    }

    /** Only callable in debug builds. Forces a crash to test crash reporting. */
    fun forceCrash() {
        if (!BuildConfig.DEBUG) return
        throw RuntimeException("FullDiagnosticsViewModel.forceCrash() — intentional test crash")
    }
}

/**
 * §19.13 — Full diagnostics screen.
 *
 * Shows server URL (read-only outside Shared Device Mode), app version + build
 * + commit SHA, recent breadcrumb logs (last 200, redacted), force sync / flush
 * drafts action, and a force-crash button (debug builds only).
 *
 * DB export lives on [DiagnosticsScreen] (debug-only gate) to avoid conflating
 * the two. A row linking there is shown when `onExportDb` is non-null and we
 * are running a debug build.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullDiagnosticsScreen(
    onBack: () -> Unit,
    onExportDb: (() -> Unit)? = null,
    viewModel: FullDiagnosticsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val isSyncing by viewModel.isSyncing.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.syncMessage) {
        state.syncMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearSyncMessage()
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Diagnostics") },
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
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // App version + build
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Info,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                        Text("Build info", style = MaterialTheme.typography.titleSmall)
                    }
                    DiagRow("Version", state.appVersion)
                    DiagRow("Build type", state.buildType)
                    if (state.commitSha.isNotBlank()) DiagRow("Commit", state.commitSha, mono = true)
                }
            }

            // Server URL (read-only)
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Dns,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                        Text("Server", style = MaterialTheme.typography.titleSmall)
                    }
                    DiagRow("URL", state.serverUrl, mono = true)
                }
            }

            // Force sync
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Sync,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                        Text("Sync", style = MaterialTheme.typography.titleSmall)
                    }
                    FilledTonalButton(
                        onClick = { viewModel.forceSyncNow() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isSyncing,
                    ) {
                        Text(if (isSyncing) "Syncing…" else "Force sync / flush drafts")
                    }
                }
            }

            // Recent logs
            if (state.recentLogs.isNotEmpty()) {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "Recent activity (last ${state.recentLogs.size})",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        state.recentLogs.takeLast(50).forEach { line ->
                            Text(
                                line,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // DB export (debug-only)
            if (BuildConfig.DEBUG && onExportDb != null) {
                FilledTonalButton(
                    onClick = onExportDb,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Export encrypted DB snapshot")
                }
            }

            // Force crash (debug-only)
            if (BuildConfig.DEBUG) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = androidx.compose.material3.CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                    ),
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.Warning,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onErrorContainer,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                "Debug only",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                            )
                        }
                        FilledTonalButton(
                            onClick = { viewModel.forceCrash() },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(
                                Icons.Default.BugReport,
                                contentDescription = "Force crash",
                                modifier = Modifier.padding(end = 8.dp).size(16.dp),
                            )
                            Text("Force crash (test crash reporter)")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DiagRow(label: String, value: String, mono: Boolean = false) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(0.35f),
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = if (mono) FontFamily.Monospace else null,
            modifier = Modifier.weight(0.65f),
        )
    }
}
