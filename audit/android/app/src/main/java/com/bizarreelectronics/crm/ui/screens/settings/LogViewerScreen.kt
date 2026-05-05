package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Log level filter enum
// ---------------------------------------------------------------------------

/**
 * §32.4 — Selectable level filters for the log viewer.
 *
 * The release tree only records [ERROR] and [WARN] entries; both are shown by
 * default. Tapping a chip toggles that level in/out of the visible set.
 */
enum class LogLevel(val label: String, val priority: Int) {
    ERROR("Error", Log.ERROR),
    WARN("Warn", Log.WARN),
}

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

data class LogViewerUiState(
    /** All entries read from [ReleaseTree] ring buffer, unfiltered. */
    val allEntries: List<ReleaseTree.LogEntry> = emptyList(),
    /** Entries after applying [query] and [activeLevels]. Derived, not stored raw. */
    val filteredEntries: List<String> = emptyList(),
    /** Current search query; empty string = no text filter. */
    val query: String = "",
    /** Levels currently shown. Both levels active = "All". */
    val activeLevels: Set<LogLevel> = LogLevel.entries.toSet(),
    /** Non-null while a share-sheet is being prepared (flush in progress). */
    val shareFile: File? = null,
    val shareError: String? = null,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * §32.4 — ViewModel for [LogViewerScreen].
 *
 * Reads the in-memory ring buffer from [ReleaseTree] for display and
 * orchestrates [ReleaseTree.flushToDisk] when the user taps "Share logs".
 *
 * Search and level-filter are applied in [applyFilters] and exposed via
 * [uiState].filteredEntries.  All filtering is pure in-memory — no I/O.
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
        val entries = releaseTree.snapshot()
        _uiState.update { it.copy(allEntries = entries) }
        applyFilters()
    }

    /** Re-read the ring buffer (user-triggered refresh). */
    fun refresh() = load()

    /** Update the keyword search query and re-filter. */
    fun setQuery(query: String) {
        _uiState.update { it.copy(query = query) }
        applyFilters()
    }

    /** Toggle a log level chip on/off and re-filter. */
    fun toggleLevel(level: LogLevel) {
        _uiState.update { current ->
            val updated = if (level in current.activeLevels) {
                // Do not allow deselecting the last level — always show at least one.
                if (current.activeLevels.size > 1) current.activeLevels - level
                else current.activeLevels
            } else {
                current.activeLevels + level
            }
            current.copy(activeLevels = updated)
        }
        applyFilters()
    }

    /**
     * Applies [LogViewerUiState.query] and [LogViewerUiState.activeLevels] to
     * [LogViewerUiState.allEntries] and writes the formatted result into
     * [LogViewerUiState.filteredEntries].
     *
     * Runs synchronously on the calling thread — entries are in-memory only,
     * so no coroutine dispatch is needed here.
     */
    private fun applyFilters() {
        _uiState.update { current ->
            val queryLower = current.query.trim().lowercase()
            val filtered = current.allEntries.asSequence()
                .filter { entry -> entry.priority in current.activeLevels.map { it.priority } }
                .filter { entry ->
                    queryLower.isEmpty() ||
                        entry.message.lowercase().contains(queryLower) ||
                        entry.tag?.lowercase()?.contains(queryLower) == true
                }
                .map { it.format() }
                .toList()
            current.copy(filteredEntries = filtered)
        }
    }

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
                _uiState.update { it.copy(shareFile = file, shareError = null) }
            } else {
                _uiState.update {
                    it.copy(shareError = "Nothing to share — log buffer is empty.")
                }
            }
        }
    }

    fun clearShareState() {
        _uiState.update { it.copy(shareFile = null, shareError = null) }
    }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/**
 * §32.4 — Settings → Diagnostics → View logs.
 *
 * Displays the last [ReleaseTree.MAX_ENTRIES] Error+Warn entries from the
 * in-memory ring buffer with:
 *  • Keyword search bar — filters by message text and tag (debounce handled
 *    client-side; ring is in-memory so no coroutine needed).
 *  • Level filter chips — "Error" / "Warn" toggles; at least one always active.
 *  • Share action — flushes buffer to a dated file and opens share-sheet.
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
                        enabled = state.allEntries.isNotEmpty(),
                    ) {
                        Icon(
                            Icons.Default.Share,
                            contentDescription = "Share logs",
                            tint = if (state.allEntries.isNotEmpty())
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ----------------------------------------------------------------
            // Search + level filter strip
            // ----------------------------------------------------------------
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = { viewModel.setQuery(it) },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Search logs…") },
                    leadingIcon = {
                        Icon(Icons.Default.Search, contentDescription = null,
                            modifier = Modifier.size(18.dp))
                    },
                    trailingIcon = {
                        if (state.query.isNotEmpty()) {
                            IconButton(onClick = { viewModel.setQuery("") }) {
                                Icon(Icons.Default.Clear, contentDescription = "Clear search",
                                    modifier = Modifier.size(18.dp))
                            }
                        }
                    },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodySmall,
                )

                // Level filter chips
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LogLevel.entries.forEach { level ->
                        val selected = level in state.activeLevels
                        FilterChip(
                            selected = selected,
                            onClick = { viewModel.toggleLevel(level) },
                            label = { Text(level.label, style = MaterialTheme.typography.labelSmall) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = when (level) {
                                    LogLevel.ERROR -> MaterialTheme.colorScheme.errorContainer
                                    LogLevel.WARN  -> MaterialTheme.colorScheme.tertiaryContainer
                                },
                                selectedLabelColor = when (level) {
                                    LogLevel.ERROR -> MaterialTheme.colorScheme.onErrorContainer
                                    LogLevel.WARN  -> MaterialTheme.colorScheme.onTertiaryContainer
                                },
                            ),
                        )
                    }
                    Spacer(Modifier.width(4.dp))
                    // Entry count badge
                    Text(
                        text = if (state.filteredEntries.size == state.allEntries.size)
                            "${state.allEntries.size} entries"
                        else
                            "${state.filteredEntries.size} / ${state.allEntries.size}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.align(Alignment.CenterVertically),
                    )
                }
            }

            // ----------------------------------------------------------------
            // Log list
            // ----------------------------------------------------------------
            if (state.allEntries.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.AutoMirrored.Filled.Article,
                        title = "No log entries",
                        subtitle = "Release builds capture Error and Warn entries here. " +
                            "Debug builds write to Logcat instead.",
                    )
                }
            } else if (state.filteredEntries.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No entries match \"${state.query}\"",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                val listState = rememberLazyListState()
                // Scroll to the bottom on initial composition so newest entries are visible.
                LaunchedEffect(state.filteredEntries.size) {
                    if (state.filteredEntries.isNotEmpty()) {
                        listState.animateScrollToItem(state.filteredEntries.size - 1)
                    }
                }
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    items(state.filteredEntries) { line ->
                        LogLine(line = line)
                    }
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
