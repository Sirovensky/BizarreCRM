package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * §32.3 Crash reports — Settings → Diagnostics surface for the files
 * written by `util/CrashReporter` to `filesDir/crash-reports/`.
 *
 * Lets the user:
 *   - See a list of crashes (timestamp + size)
 *   - Tap a row to view the full stack-trace text
 *   - Share the file via system share-sheet (so they can email it to
 *     support without involving any third-party telemetry SDK)
 *   - Delete an individual report or all of them
 *
 * No network — files stay on the device until the §32.2 TelemetryClient
 * lands a tenant-side upload path.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CrashReportsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val files = remember { mutableStateListOf<File>() }
    var preview by remember { mutableStateOf<File?>(null) }
    var confirmDeleteAll by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        files.clear()
        files.addAll(loadReports(context))
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Crash reports") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // §32.3 dev tool — force a crash to verify the reporter
                    // captures it. Hidden in release builds. The throw runs
                    // off the Compose dispatch loop so the crash log is
                    // attributed to a clean stack and not a Compose frame.
                    if (com.bizarreelectronics.crm.BuildConfig.DEBUG) {
                        IconButton(onClick = {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                throw RuntimeException("Test crash from CrashReportsScreen")
                            }
                        }) {
                            Icon(Icons.Default.BugReport, contentDescription = "Force crash (debug)")
                        }
                    }
                    if (files.isNotEmpty()) {
                        IconButton(onClick = { confirmDeleteAll = true }) {
                            Icon(Icons.Default.Delete, contentDescription = "Delete all")
                        }
                    }
                },
            )
        },
    ) { padding ->
        if (files.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                EmptyState(
                    icon = Icons.Default.BugReport,
                    title = "No crash reports",
                    subtitle = "Nice. Bizarre CRM hasn't crashed on this device.",
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(files, key = { it.absolutePath }) { file ->
                    CrashRow(
                        file = file,
                        onClick = { preview = file },
                        onShare = { shareReport(context, file) },
                        onDelete = {
                            file.delete()
                            files.remove(file)
                        },
                    )
                }
            }
        }
    }

    if (preview != null) {
        CrashReportDialog(file = preview!!, onClose = { preview = null })
    }

    if (confirmDeleteAll) {
        AlertDialog(
            onDismissRequest = { confirmDeleteAll = false },
            title = { Text("Delete all crash reports?") },
            text = { Text("This removes every crash log from this device. The action can't be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    files.forEach { it.delete() }
                    files.clear()
                    confirmDeleteAll = false
                }) { Text("Delete all") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDeleteAll = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun CrashRow(
    file: File,
    onClick: () -> Unit,
    onShare: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                Icons.Default.BugReport,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = formatTimestamp(file.lastModified()),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = "${file.name} · ${file.length()} B",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onShare) {
                Icon(Icons.Default.Share, contentDescription = "Share")
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CrashReportDialog(file: File, onClose: () -> Unit) {
    val text = remember(file.absolutePath) {
        runCatching { file.readText() }.getOrDefault("(failed to read)")
    }
    AlertDialog(
        onDismissRequest = onClose,
        confirmButton = {
            TextButton(onClick = onClose) { Text("Close") }
        },
        title = { Text(file.name, style = MaterialTheme.typography.titleSmall) },
        text = {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceContainer)
                    .padding(8.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        },
    )
}

private fun loadReports(context: Context): List<File> {
    val dir = File(context.filesDir, "crash-reports")
    if (!dir.exists()) return emptyList()
    return dir.listFiles()
        ?.filter { it.isFile && it.extension == "log" }
        ?.sortedByDescending { it.lastModified() }
        ?: emptyList()
}

private fun shareReport(context: Context, file: File) {
    val authority = "${context.packageName}.fileprovider"
    val uri = runCatching {
        FileProvider.getUriForFile(context, authority, file)
    }.getOrNull() ?: return
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "Bizarre CRM crash report — ${file.name}")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share crash report"))
}

private fun formatTimestamp(epochMs: Long): String =
    SimpleDateFormat("MMM d, yyyy · h:mm:ss a", Locale.US).format(Date(epochMs))
