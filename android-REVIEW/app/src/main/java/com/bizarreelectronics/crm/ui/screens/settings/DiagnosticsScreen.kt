package com.bizarreelectronics.crm.ui.screens.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.BuildConfig
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Settings → Diagnostics screen.
 *
 * Provides a single action: export the local SQLCipher-encrypted database as
 * a ZIP archive to a user-chosen location via the Storage Access Framework.
 *
 * **Debug-only gate** — this composable is only reachable from [SettingsScreen]
 * when `BuildConfig.DEBUG` is true. A production build will never navigate here
 * because [SettingsScreen] guards the "Diagnostics" row behind that flag.
 *
 * The export is raw + encrypted (passphrase required to open the DB). A `!READ_ME.txt`
 * entry inside the ZIP documents this. See [com.bizarreelectronics.crm.util.DbExporter]
 * for the zipping logic.
 *
 * [plan:L185] — ActionPlan §1.3 line 185.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiagnosticsScreen(
    onBack: () -> Unit,
    onViewReleaseLogs: () -> Unit = {},
    viewModel: DiagnosticsViewModel = hiltViewModel(),
) {
    val exportState by viewModel.exportState.collectAsStateWithLifecycle()
    val syncRunning by viewModel.syncRunning.collectAsStateWithLifecycle()
    val syncMessage by viewModel.syncMessage.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var showLogs by remember { mutableStateOf(false) }
    val logs = remember(showLogs) { if (showLogs) viewModel.recentLogs() else emptyList() }

    // SAF document-creation launcher. MIME type = application/zip so the system
    // file picker pre-selects appropriate storage locations.
    val createDocumentLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/zip"),
    ) { uri: Uri? ->
        viewModel.export(uri)
    }

    // Show snackbar on terminal states (success / error), then reset.
    LaunchedEffect(exportState) {
        when (val state = exportState) {
            is ExportState.Success -> {
                val kb = state.sizeBytes / 1024
                snackbarHostState.showSnackbar("Exported — ${kb} KB written")
                viewModel.resetState()
            }
            is ExportState.Error -> {
                snackbarHostState.showSnackbar(state.error.message)
                viewModel.resetState()
            }
            else -> { /* Idle / InProgress — no snackbar */ }
        }
    }

    LaunchedEffect(syncMessage) {
        val msg = syncMessage
        if (msg != null) snackbarHostState.showSnackbar(msg)
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
            // §19.13 — App info (build + commit)
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Build info", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "Version: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "Build type: ${if (BuildConfig.DEBUG) "debug" else "release"}",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    // Telemetry counter (breadcrumb proxy)
                    Text(
                        "Breadcrumb entries: ${viewModel.telemetryCount}",
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // §19.13 — Force sync
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Sync", style = MaterialTheme.typography.titleSmall)
                    OutlinedButton(
                        onClick = { viewModel.forceSyncNow() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !syncRunning,
                    ) {
                        if (syncRunning) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.size(8.dp))
                            Text("Syncing…")
                        } else {
                            Icon(Icons.Default.Sync, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.size(8.dp))
                            Text("Force sync / flush drafts")
                        }
                    }
                }
            }

            // §19.13 — View logs
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Recent activity log", style = MaterialTheme.typography.titleSmall)
                        androidx.compose.material3.TextButton(onClick = { showLogs = !showLogs }) {
                            Text(if (showLogs) "Hide" else "Show last 200")
                        }
                    }
                    if (showLogs) {
                        if (logs.isEmpty()) {
                            Text(
                                "No breadcrumbs yet.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            logs.takeLast(200).forEach { line ->
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
            }

            // §32.4 — Release log viewer (Error + Warn ring buffer with search + filter)
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Release logs", style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = "Error and Warn entries captured in release builds. Searchable, filterable, shareable.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(
                        onClick = onViewReleaseLogs,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Article, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(8.dp))
                        Text("View release logs")
                    }
                }
            }

            // §19.13 — DB export (debug only)
            val isInProgress = exportState is ExportState.InProgress
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Export database snapshot", style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = "Saves a ZIP of the encrypted local database. Requires SQLCipher passphrase to open — developer use only.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(
                        onClick = {
                            val timestamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
                            createDocumentLauncher.launch("bizarre-crm-$timestamp.zip")
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isInProgress,
                    ) {
                        if (isInProgress) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp).padding(end = 8.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                            Text("Exporting…")
                        } else {
                            Icon(Icons.Default.Storage, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.size(8.dp))
                            Text("Export")
                        }
                    }
                    if (isInProgress) {
                        val bytes = (exportState as ExportState.InProgress).bytesWritten
                        Text("${bytes / 1024} KB written…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            // §19.13 — Force crash (debug only)
            if (BuildConfig.DEBUG) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Developer tools", style = MaterialTheme.typography.titleSmall)
                        Button(
                            onClick = { viewModel.forceCrash() },
                            modifier = Modifier.fillMaxWidth(),
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                        ) {
                            Icon(Icons.Default.BugReport, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.size(8.dp))
                            Text("Force crash (test CrashReporter)")
                        }
                    }
                }
            }

            // §19.13 — Feature flags note
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Feature flags", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "Feature flags viewer (admin) — deferred. Server has no GET /settings/feature-flags endpoint.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
