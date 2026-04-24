package com.bizarreelectronics.crm.ui.screens.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
    viewModel: DiagnosticsViewModel = hiltViewModel(),
) {
    val exportState by viewModel.exportState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

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
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 24.dp, vertical = 32.dp),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Storage,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Text(
                    text = "Export database snapshot",
                    style = MaterialTheme.typography.titleMedium,
                )

                Text(
                    text = "Saves a ZIP of the encrypted local database to a location you choose. " +
                            "The archive requires the SQLCipher passphrase to open — it is for " +
                            "developer inspection only.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                Spacer(Modifier.height(8.dp))

                val isInProgress = exportState is ExportState.InProgress

                Button(
                    onClick = {
                        val timestamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
                            .format(Date())
                        createDocumentLauncher.launch("bizarre-crm-$timestamp.zip")
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isInProgress,
                ) {
                    if (isInProgress) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(18.dp)
                                .padding(end = 8.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                        Text("Exporting…")
                    } else {
                        Text("Export")
                    }
                }

                // Show bytes-written counter while in progress.
                if (isInProgress) {
                    val bytes = (exportState as ExportState.InProgress).bytesWritten
                    Text(
                        text = "${bytes / 1024} KB written…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
