package com.bizarreelectronics.crm.ui.screens.stocktake

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.StocktakeListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState

/**
 * §6.6 Stocktake sessions list.
 *
 * Shows all stocktake sessions loaded from [GET /stocktake] with status filter
 * chips (All / Open / Committed). FAB opens "New session" dialog that POSTs to
 * [POST /stocktake]. Tapping an open session navigates to the active-count flow
 * via [onOpenSession].
 *
 * 404-tolerant: if the server does not have stocktake routes, shows an
 * "unavailable" state instead of an error.
 *
 * Role: admin / manager may create sessions; all roles may view the list.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StocktakeListScreen(
    onBack: () -> Unit,
    /** Navigate to the active-count flow for the given server session id. */
    onOpenSession: (sessionId: Int) -> Unit,
    viewModel: StocktakeListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Status filter: null = "All"
    var statusFilter by rememberSaveable { mutableStateOf<String?>(null) }

    // Show snackbar on error
    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    // Navigate to active-count flow when a new session is created
    LaunchedEffect(state.createdSessionId) {
        val id = state.createdSessionId ?: return@LaunchedEffect
        viewModel.consumeCreatedSessionId()
        onOpenSession(id)
    }

    // "New session" dialog
    if (state.showNewDialog) {
        NewStocktakeSessionDialog(
            isCreating = state.isCreating,
            onDismiss = { viewModel.dismissNewDialog() },
            onCreate = { name, location, notes ->
                viewModel.createSession(name, location, notes)
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Stocktakes",
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics {
                            contentDescription = "Back"
                        },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        floatingActionButton = {
            if (!state.serverUnsupported) {
                FloatingActionButton(
                    onClick = { viewModel.showNewDialog() },
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.semantics {
                        contentDescription = "New stocktake session"
                    },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                }
            }
        },
    ) { paddingValues ->
        when {
            state.serverUnsupported -> {
                ServerUnsupportedState(modifier = Modifier.padding(paddingValues))
            }
            else -> {
                PullToRefreshBox(
                    isRefreshing = state.isLoading,
                    onRefresh = { viewModel.loadSessions() },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues),
                ) {
                    Column(modifier = Modifier.fillMaxSize()) {
                        // ── Status filter chips ──────────────────────────────
                        StatusFilterRow(
                            current = statusFilter,
                            onSelect = { statusFilter = it },
                        )

                        // ── Session list ─────────────────────────────────────
                        val filtered = if (statusFilter == null) {
                            state.sessions
                        } else {
                            state.sessions.filter { it.status == statusFilter }
                        }

                        if (!state.isLoading && filtered.isEmpty()) {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center,
                            ) {
                                EmptyState(
                                    title = if (statusFilter == null) "No stocktake sessions yet"
                                            else "No $statusFilter sessions",
                                    subtitle = "Tap + to start a new count",
                                )
                            }
                        } else {
                            LazyColumn(
                                modifier = Modifier.fillMaxSize(),
                                contentPadding = PaddingValues(
                                    start = 16.dp,
                                    end = 16.dp,
                                    bottom = 88.dp, // avoid FAB overlap
                                ),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                items(
                                    items = filtered,
                                    key = { it.id },
                                ) { session ->
                                    StocktakeSessionCard(
                                        session = session,
                                        onOpen = { onOpenSession(session.id) },
                                        onCancel = { viewModel.cancelSession(session.id) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Status filter chips ───────────────────────────────────────────────────────

@Composable
private fun StatusFilterRow(
    current: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChip(
            selected = current == null,
            onClick = { onSelect(null) },
            label = { Text("All") },
        )
        FilterChip(
            selected = current == "open",
            onClick = { onSelect("open") },
            label = { Text("Open") },
        )
        FilterChip(
            selected = current == "committed",
            onClick = { onSelect("committed") },
            label = { Text("Committed") },
        )
        FilterChip(
            selected = current == "cancelled",
            onClick = { onSelect("cancelled") },
            label = { Text("Cancelled") },
        )
    }
}

// ─── Session card ──────────────────────────────────────────────────────────────

@Composable
private fun StocktakeSessionCard(
    session: StocktakeListItem,
    onOpen: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isOpen = session.status == "open"
    BrandCard(
        modifier = modifier.fillMaxWidth(),
        onClick = if (isOpen) onOpen else null,
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Status icon
            val (icon, tint) = when (session.status) {
                "committed" -> Icons.Default.CheckCircle to MaterialTheme.colorScheme.primary
                "cancelled" -> Icons.Default.Close to MaterialTheme.colorScheme.error
                else -> Icons.Default.Assignment to MaterialTheme.colorScheme.tertiary
            }
            Icon(
                imageVector = icon,
                contentDescription = session.status,
                tint = tint,
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = session.name,
                    style = MaterialTheme.typography.titleSmall,
                )
                session.location?.takeIf { it.isNotBlank() }?.let { loc ->
                    Text(
                        text = loc,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    text = formatStocktakeDate(session.openedAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Cancel action for open sessions
            if (isOpen) {
                TextButton(
                    onClick = onCancel,
                    modifier = Modifier.semantics {
                        contentDescription = "Cancel stocktake ${session.name}"
                    },
                ) {
                    Text(
                        "Cancel",
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
}

// ─── New session dialog ────────────────────────────────────────────────────────

@Composable
private fun NewStocktakeSessionDialog(
    isCreating: Boolean,
    onDismiss: () -> Unit,
    onCreate: (name: String, location: String?, notes: String?) -> Unit,
) {
    var name by rememberSaveable { mutableStateOf("") }
    var location by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = { if (!isCreating) onDismiss() },
        title = { Text("New Stocktake Session") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Session name *") },
                    placeholder = { Text("e.g. Monthly count — May 2026") },
                    singleLine = true,
                    enabled = !isCreating,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = location,
                    onValueChange = { location = it },
                    label = { Text("Location (optional)") },
                    placeholder = { Text("e.g. Main shelf, Back storage") },
                    singleLine = true,
                    enabled = !isCreating,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes (optional)") },
                    enabled = !isCreating,
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (isCreating) {
                    Box(
                        modifier = Modifier.fillMaxWidth(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onCreate(name, location.ifBlank { null }, notes.ifBlank { null }) },
                enabled = name.isNotBlank() && !isCreating,
            ) {
                Text("Start session")
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isCreating,
            ) {
                Text("Cancel")
            }
        },
    )
}

// ─── Server-unsupported fallback ───────────────────────────────────────────────

@Composable
private fun ServerUnsupportedState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        EmptyState(
            title = "Stocktake not available",
            subtitle = "This feature requires a newer server build. Update your self-hosted server to enable stocktake.",
        )
    }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Format an ISO-8601 date-time string to a human-readable label.
 * Falls back to the raw string on parse failure.
 */
private fun formatStocktakeDate(isoDate: String): String {
    return try {
        // ISO-8601 e.g. "2026-04-27T14:30:00.000Z"
        val instant = java.time.Instant.parse(isoDate)
        val zdt = instant.atZone(java.time.ZoneId.systemDefault())
        val formatter = java.time.format.DateTimeFormatter.ofPattern("MMM d, yyyy · h:mm a")
        formatter.format(zdt)
    } catch (_: Exception) {
        isoDate
    }
}
