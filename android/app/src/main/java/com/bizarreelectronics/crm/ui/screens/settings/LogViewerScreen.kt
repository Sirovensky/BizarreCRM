package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.CenterAlignedTopAppBar
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.util.ReleaseTree
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

data class LogViewerUiState(
    val entries: List<String> = emptyList(),
    /** Non-null while a share-sheet is being prepared (flush in progress). */
    val shareFile: File? = null,
    val shareError: String? = null,
)

/**
 * §32.4 — ViewModel for [LogViewerScreen].
 *
 * Reads the in-memory ring buffer from [ReleaseTree] for display and
 * orchestrates [ReleaseTree.flushToDisk] when the user taps "Share logs".
 *
 * Release builds: shows real Error+Warn entries.
 * Debug builds: the ring is empty because [BizarreCrmApp] plants DebugTree
 * (full logcat) rather than [ReleaseTree] — the screen shows a placeholder
 * explaining this.
 */
@HiltViewModel
class LogViewerViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val releaseTree: ReleaseTree,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LogViewerUiState())
    val uiState: StateFlow<LogViewerUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        val lines = releaseTree.snapshot().map { it.format() }
        _uiState.value = _uiState.value.copy(entries = lines)
    }

    /** Re-read the ring buffer (user-triggered refresh). */
    fun refresh() = load()

    /**
     * Flush the ring buffer to disk, then surface the [File] so the
     * composable can fire a share-sheet intent.
     */
    fun prepareShare() {
        viewModelScope.launch {
            val file = withContext(Dispatchers.IO) {
                val logDir = File(context.filesDir, ReleaseTree.LOG_DIR_NAME)
                runCatching { releaseTree.flushToDisk(logDir) }
                    .onFailure { t -> Timber.w(t, "LogViewer: flush failed") }
                    .getOrNull()
            }
            if (file != null) {
                _uiState.value = _uiState.value.copy(shareFile = file, shareError = null)
            } else {
                _uiState.value = _uiState.value.copy(
                    shareError = "Nothing to share — log buffer is empty.",
                )
            }
        }
    }

    fun clearShareState() {
        _uiState.value = _uiState.value.copy(shareFile = null, shareError = null)
    }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/**
 * §32.4 — Settings → Diagnostics → View logs.
 *
 * Displays the last [ReleaseTree.MAX_ENTRIES] Error+Warn entries from the
 * in-memory ring buffer and exposes a share action that flushes the buffer
 * to a dated file under `filesDir/diagnostics-logs/` and opens the system
 * share-sheet (FileProvider, no third-party upload).
 *
 * In debug builds the ring buffer is always empty (DebugTree is planted
 * instead of ReleaseTree) so an informational placeholder is shown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogViewerScreen(
    onBack: () -> Unit,
    viewModel: LogViewerViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // Share-sheet side-effect: fires when shareFile becomes non-null, then resets.
    LaunchedEffect(state.shareFile) {
        val file = state.shareFile ?: return@LaunchedEffect
        shareLogs(context, file)
        viewModel.clearShareState()
    }

    // Snackbar for flush errors.
    LaunchedEffect(state.shareError) {
        val err = state.shareError ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(err)
        viewModel.clearShareState()
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("View logs") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.prepareShare() },
                        enabled = state.entries.isNotEmpty(),
                    ) {
                        Icon(
                            Icons.Default.Share,
                            contentDescription = "Share logs",
                            tint = if (state.entries.isNotEmpty())
                                MaterialTheme.colorScheme.onSurface
                            else
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        if (state.entries.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                EmptyState(
                    icon = Icons.Default.Article,
                    title = "No log entries",
                    subtitle = "Release builds capture Error and Warn entries here. " +
                        "Debug builds write to Logcat instead.",
                )
            }
        } else {
            val listState = rememberLazyListState()
            // Scroll to the bottom on initial composition so newest entries are visible.
            LaunchedEffect(state.entries.size) {
                if (state.entries.isNotEmpty()) {
                    listState.animateScrollToItem(state.entries.size - 1)
                }
            }
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "${state.entries.size} entries (Error + Warn)",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                items(state.entries) { line ->
                    LogLine(line = line)
                }
            }
        }
    }
}

@Composable
private fun LogLine(line: String) {
    // Colour-code by level prefix: "E/" = error, "W/" = warn.
    val color = when {
        line.contains(Regex("""^\d{2}:\d{2}:\d{2}\.\d{3} E""")) ->
            MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(
        text = line,
        style = MaterialTheme.typography.bodySmall,
        fontFamily = FontFamily.Monospace,
        color = color,
        modifier = Modifier.fillMaxWidth(),
    )
}

// ---------------------------------------------------------------------------
// Share helper
// ---------------------------------------------------------------------------

/**
 * Opens the system share-sheet for [file] via FileProvider.
 * The authority matches the `<provider android:authorities>` entry in
 * AndroidManifest.xml (`${applicationId}.fileprovider`).
 */
private fun shareLogs(context: Context, file: File) {
    val authority = "${context.packageName}.fileprovider"
    val uri = runCatching {
        FileProvider.getUriForFile(context, authority, file)
    }.getOrNull() ?: return
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "Bizarre CRM diagnostic logs — ${file.name}")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share logs"))
}
