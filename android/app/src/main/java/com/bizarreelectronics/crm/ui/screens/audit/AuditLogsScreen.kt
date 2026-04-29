package com.bizarreelectronics.crm.ui.screens.audit

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.AuditEntry
import com.bizarreelectronics.crm.ui.screens.audit.components.AuditEntryRow
import com.bizarreelectronics.crm.ui.screens.audit.components.AuditFilter
import com.bizarreelectronics.crm.ui.screens.audit.components.AuditFilterSheet

/**
 * §52 — Audit Logs screen.
 *
 * Admin-only: callers MUST gate this route on [authPreferences.userRole == "admin"].
 * The screen itself renders an access-denied message if [isAdmin] is false — a
 * defense-in-depth guard against accidental navigation.
 *
 * Features:
 *  - LazyColumn of [AuditEntryRow] (actor + action + entity + timestamp + diff-summary).
 *  - DockedSearchBar for client-side search across loaded entries.
 *  - Filter FAB opens [AuditFilterSheet] (actor, entity type, action, date range).
 *  - Infinite scroll: last-visible-item heuristic triggers [AuditLogsViewModel.loadNextPage].
 *  - Tap on row opens full-diff [AlertDialog] showing raw diff JSON.
 *  - 404 from server → empty-state with a "No audit log available" message (not an error).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuditLogsScreen(
    isAdmin: Boolean,
    onBack: () -> Unit,
    viewModel: AuditLogsViewModel = hiltViewModel(),
) {
    val items by viewModel.items.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    val error by viewModel.error.collectAsState()
    val hasMore by viewModel.hasMore.collectAsState()
    val filter by viewModel.filter.collectAsState()
    val search by viewModel.search.collectAsState()
    val selectedEntry by viewModel.selectedEntry.collectAsState()
    val exportState by viewModel.exportState.collectAsState()

    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    // §52.4 — SAF launcher: user picks a file name/location; we write CSV there.
    val csvLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/csv"),
    ) { destUri: Uri? ->
        if (destUri != null) {
            viewModel.exportCsvTo(context, destUri)
        }
    }

    // React to export completion: show snackbar, then reset state.
    LaunchedEffect(exportState) {
        when (val s = exportState) {
            is AuditLogsViewModel.ExportState.Success -> {
                snackbarHostState.showSnackbar("Exported ${s.rowCount} rows to CSV")
                viewModel.clearExportState()
            }
            is AuditLogsViewModel.ExportState.Error -> {
                snackbarHostState.showSnackbar(s.message)
                viewModel.clearExportState()
            }
            else -> Unit
        }
    }

    var showFilterSheet by remember { mutableStateOf(false) }
    var searchActive by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()

    // Infinite scroll trigger: load next page when within 5 items of the end.
    val shouldLoadMore by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val totalItems = listState.layoutInfo.totalItemsCount
            hasMore && !isLoadingMore && lastVisible >= totalItems - 5
        }
    }
    LaunchedEffect(shouldLoadMore) {
        if (shouldLoadMore) viewModel.loadNextPage()
    }

    // Client-side search filter
    val displayItems = remember(items, search) {
        if (search.isBlank()) items
        else items.filter { entry ->
            entry.actor.contains(search, ignoreCase = true) ||
                entry.action.contains(search, ignoreCase = true) ||
                entry.entityType.contains(search, ignoreCase = true) ||
                entry.entityLabel?.contains(search, ignoreCase = true) == true ||
                entry.diffSummary?.contains(search, ignoreCase = true) == true
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_audit_logs)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // §52.4 — export current (filtered) page-set to CSV via SAF
                    val exportFilename = stringResource(R.string.audit_export_csv_filename)
                    IconButton(
                        onClick = { csvLauncher.launch(exportFilename) },
                        enabled = items.isNotEmpty() &&
                            exportState !is AuditLogsViewModel.ExportState.InProgress,
                    ) {
                        Icon(
                            Icons.Default.Download,
                            contentDescription = stringResource(R.string.audit_export_cd),
                        )
                    }
                    IconButton(onClick = { viewModel.loadFirstPage() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    IconButton(onClick = { showFilterSheet = true }) {
                        Icon(Icons.Default.FilterList, contentDescription = "Filter")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { innerPadding ->

        // Admin gate
        if (!isAdmin) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Access denied — admin role required",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            // Search bar
            DockedSearchBar(
                inputField = {
                    androidx.compose.material3.SearchBarDefaults.InputField(
                        query = search,
                        onQueryChange = viewModel::updateSearch,
                        onSearch = { searchActive = false },
                        expanded = searchActive,
                        onExpandedChange = { searchActive = it },
                        placeholder = { Text("Search logs…") },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    )
                },
                expanded = searchActive,
                onExpandedChange = { searchActive = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) { /* search suggestions — not needed for audit */ }

            if (isLoadingMore) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }

            when {
                isLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }

                error != null -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text = error ?: "Unknown error",
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            TextButton(onClick = { viewModel.loadFirstPage() }) {
                                Text("Retry")
                            }
                        }
                    }
                }

                displayItems.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = if (filter == AuditFilter() && search.isBlank())
                                "No audit log entries found"
                            else "No entries match current filters",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                else -> {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(bottom = 16.dp),
                    ) {
                        items(items = displayItems, key = { it.id }) { entry ->
                            AuditEntryRow(
                                entry = entry,
                                onClick = { viewModel.selectEntry(entry) },
                            )
                        }
                    }
                }
            }
        }

        // Filter bottom sheet
        if (showFilterSheet) {
            AuditFilterSheet(
                current = filter,
                onApply = { newFilter ->
                    viewModel.updateFilter(newFilter)
                    showFilterSheet = false
                },
                onDismiss = { showFilterSheet = false },
            )
        }

        // Full-diff dialog
        selectedEntry?.let { entry ->
            AuditDiffDialog(
                entry = entry,
                onDismiss = { viewModel.selectEntry(null) },
            )
        }
    }
}

// ─── Full-diff dialog ─────────────────────────────────────────────────────────

@Composable
private fun AuditDiffDialog(
    entry: AuditEntry,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("${entry.action.uppercase()} · ${entry.entityType}")
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    text = "Actor: ${entry.actor} (${entry.actorRole})",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    text = "Time: ${entry.timestamp}",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (!entry.entityLabel.isNullOrBlank()) {
                    Text(
                        text = "Entity: ${entry.entityLabel}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (!entry.ipAddress.isNullOrBlank()) {
                    Text(
                        text = "IP: ${entry.ipAddress}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (!entry.diffJson.isNullOrBlank()) {
                    Text(
                        text = entry.diffJson,
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else if (!entry.diffSummary.isNullOrBlank()) {
                    Text(
                        text = entry.diffSummary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                } else {
                    Text(
                        text = "(no diff data)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
    )
}
