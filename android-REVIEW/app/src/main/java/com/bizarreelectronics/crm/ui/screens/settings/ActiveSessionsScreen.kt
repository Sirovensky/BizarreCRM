package com.bizarreelectronics.crm.ui.screens.settings

// §2.11 — Active Sessions screen.
//
// Shows all active sessions for the current user, with:
//   - Device name + "(Current session)" chip for the calling session.
//   - IP address + truncated user-agent.
//   - "Last seen N min/h/d ago" relative time.
//   - "Revoke" button (disabled for current session).
//   - Pull-to-refresh.
//   - Error state with retry.
//   - Empty state: "No other active sessions."
//   - 404 footer: "This server does not support session listing."

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DevicesOther
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.util.AppError
import java.time.Instant
import java.time.temporal.ChronoUnit

// ---------------------------------------------------------------------------
// Composable
// ---------------------------------------------------------------------------

/**
 * §2.11 — Active sessions list screen.
 *
 * Reachable from SecurityScreen → "Active sessions" row.
 * Displays all server-side sessions for the current user and allows revoking
 * any session that is not the current one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActiveSessionsScreen(
    onBack: () -> Unit,
    viewModel: ActiveSessionsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val revokeMessage by viewModel.revokeMessage.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(revokeMessage) {
        val msg = revokeMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearRevokeMessage()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Active sessions") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        val isLoading = uiState is ActiveSessionsUiState.Loading
        PullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { viewModel.refresh() },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (val state = uiState) {
                is ActiveSessionsUiState.Loading -> {
                    // Pull-to-refresh indicator handles the visual; nothing extra needed.
                    Box(modifier = Modifier.fillMaxSize())
                }

                is ActiveSessionsUiState.Error -> {
                    SessionErrorState(
                        error = state.error,
                        onRetry = { viewModel.refresh() },
                    )
                }

                is ActiveSessionsUiState.Content -> {
                    SessionListContent(
                        state = state,
                        onRevoke = { id -> viewModel.revoke(id) },
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

@Composable
private fun SessionListContent(
    state: ActiveSessionsUiState.Content,
    onRevoke: (String) -> Unit,
) {
    if (state.sessions.isEmpty()) {
        EmptySessionsState(serverUnsupported = state.serverUnsupported)
        return
    }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(items = state.sessions, key = { it.id }) { session ->
            SessionCard(session = session, onRevoke = onRevoke)
        }

        if (state.serverUnsupported) {
            item {
                Text(
                    text = "Session listing is not supported on this server version.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun SessionCard(
    session: ActiveSessionUi,
    onRevoke: (String) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // ── Header row: device + current chip ────────────────────────
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = if (session.isCurrent) Icons.Default.PhoneAndroid
                    else Icons.Default.DevicesOther,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = session.device,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (session.isCurrent) {
                    SuggestionChip(
                        onClick = {},
                        label = {
                            Text(
                                "Current session",
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                    )
                }
            }

            // ── IP ────────────────────────────────────────────────────────
            session.ip?.let { ip ->
                Text(
                    text = "IP: $ip",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // ── User-agent (truncated) ────────────────────────────────────
            session.userAgentShort?.let { ua ->
                Text(
                    text = ua,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            // ── Last seen ─────────────────────────────────────────────────
            val lastSeenText = session.lastSeenAt?.let { formatRelativeTime(it) }
                ?: session.createdAt?.let { "Started ${formatRelativeTime(it)}" }
            lastSeenText?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // ── Revoke button ─────────────────────────────────────────────
            if (!session.isCurrent) {
                Spacer(Modifier.height(4.dp))
                OutlinedButton(
                    onClick = { onRevoke(session.id) },
                    modifier = Modifier.align(Alignment.End),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Text("Revoke")
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Empty / Error states
// ---------------------------------------------------------------------------

@Composable
private fun EmptySessionsState(serverUnsupported: Boolean) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = if (serverUnsupported) "Session listing not available"
                else "No other active sessions",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (serverUnsupported) {
                Text(
                    text = "This server does not support the active sessions endpoint. " +
                            "Update the server to use this feature.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SessionErrorState(
    error: AppError,
    onRetry: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = error.title,
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                text = error.message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = onRetry) {
                Text("Try again")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Time formatting
// ---------------------------------------------------------------------------

/**
 * Returns a human-readable relative time string for an ISO-8601 timestamp.
 * Falls back gracefully if parsing fails — returns the raw string.
 *
 * Granularity: minutes → hours → days.
 */
private fun formatRelativeTime(isoTimestamp: String): String {
    return try {
        val then = Instant.parse(isoTimestamp)
        val now = Instant.now()
        val minutesAgo = ChronoUnit.MINUTES.between(then, now)
        when {
            minutesAgo < 2 -> "Last seen just now"
            minutesAgo < 60 -> "Last seen ${minutesAgo}m ago"
            minutesAgo < 1440 -> "Last seen ${minutesAgo / 60}h ago"
            else -> "Last seen ${minutesAgo / 1440}d ago"
        }
    } catch (_: Exception) {
        "Last seen $isoTimestamp"
    }
}
