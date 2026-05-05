package com.bizarreelectronics.crm.ui.screens.calls

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.VoicemailEntry
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §42.4 — Voicemail inbox fetched from the tenant VoIP provider via the server.
 *
 * Supports:
 *  - List new / all toggle
 *  - Mark as heard
 *  - Delete (with confirmation)
 *  - Play (via ACTION_VIEW intent to system player)
 *  - Call back the sender
 *
 * Audio routing is server-bridged; the app only requests an audio URL from the
 * server and opens it in the system media player.
 *
 * Route: calls/voicemail
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoicemailScreen(
    onBack: () -> Unit,
    onCallBack: (String) -> Unit,
    viewModel: CallsViewModel = hiltViewModel(),
) {
    val state by viewModel.voicemailState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var showAllMessages by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<VoicemailEntry?>(null) }

    LaunchedEffect(Unit) { viewModel.loadVoicemails(showAll = showAllMessages) }

    LaunchedEffect(showAllMessages) { viewModel.loadVoicemails(showAll = showAllMessages) }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearVoicemailActionMessage()
        }
    }

    // Delete confirmation dialog
    pendingDelete?.let { vm ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            icon = { Icon(Icons.Default.Delete, contentDescription = null) },
            title = { Text(stringResource(R.string.voicemail_delete_title)) },
            text = { Text(stringResource(R.string.voicemail_delete_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteVoicemail(vm.id)
                        pendingDelete = null
                    },
                ) { Text(stringResource(R.string.action_delete)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_voicemail),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.Default.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
                actions = {
                    // Toggle new / all
                    FilterChip(
                        selected = showAllMessages,
                        onClick = { showAllMessages = !showAllMessages },
                        label = {
                            Text(
                                if (showAllMessages)
                                    stringResource(R.string.voicemail_filter_all)
                                else
                                    stringResource(R.string.voicemail_filter_new),
                            )
                        },
                        modifier = Modifier.padding(end = 8.dp),
                    )
                    IconButton(onClick = viewModel::refreshVoicemails) {
                        Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.voicemail_refresh_cd))
                    }
                },
            )
        },
    ) { padding ->

        when {
            state.notConfigured -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(32.dp),
                ) {
                    Icon(
                        Icons.Default.Voicemail,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                    )
                    Text(
                        stringResource(R.string.voicemail_not_configured),
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Text(
                        stringResource(R.string.voicemail_not_configured_subtitle),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            state.isLoading -> BrandSkeleton(
                rows = 5,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )

            state.error != null -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(
                    message = state.error ?: "Failed to load voicemails",
                    onRetry = viewModel::refreshVoicemails,
                )
            }

            state.voicemails.isEmpty() -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                EmptyState(
                    icon = Icons.Default.Voicemail,
                    title = stringResource(
                        if (showAllMessages) R.string.voicemail_empty_all
                        else R.string.voicemail_empty_new,
                    ),
                    subtitle = null,
                )
            }

            else -> PullToRefreshBox(
                isRefreshing = state.isRefreshing,
                onRefresh = viewModel::refreshVoicemails,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                LazyColumn(
                    contentPadding = PaddingValues(
                        start = 16.dp, end = 16.dp, top = 8.dp, bottom = 80.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.voicemails, key = { it.id }) { vm ->
                        VoicemailRow(
                            entry = vm,
                            onPlay = { url ->
                                viewModel.markVoicemailHeard(vm.id)
                                playAudio(context, url)
                            },
                            onCallBack = {
                                viewModel.markVoicemailHeard(vm.id)
                                onCallBack(vm.from_number)
                            },
                            onDelete = { pendingDelete = vm },
                        )
                    }
                }
            }
        }
    }
}

// ── Voicemail row ─────────────────────────────────────────────────────────────

@Composable
private fun VoicemailRow(
    entry: VoicemailEntry,
    onPlay: (String) -> Unit,
    onCallBack: () -> Unit,
    onDelete: () -> Unit,
) {
    val isNew = entry.status == "new"
    OutlinedCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = buildString {
                    append("Voicemail from ${entry.customer_name ?: entry.from_number}")
                    append(", ${formatVmDuration(entry.duration_seconds)}")
                    if (isNew) append(", unheard")
                }
            },
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Voicemail,
                    contentDescription = null,
                    tint = if (isNew)
                        MaterialTheme.colorScheme.primary
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        entry.customer_name ?: entry.from_number,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = if (isNew) FontWeight.Bold else FontWeight.Normal,
                    )
                    Text(
                        "${entry.from_number} · ${formatVmDuration(entry.duration_seconds)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        DateFormatter.formatRelative(entry.received_at),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Transcription preview if available
            entry.transcription?.let { text ->
                Text(
                    text,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                )
            }

            // Action row
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                entry.audio_url?.let { url ->
                    FilledTonalButton(
                        onClick = { onPlay(url) },
                        modifier = Modifier.semantics {
                            contentDescription = "Play voicemail from ${entry.customer_name ?: entry.from_number}"
                        },
                    ) {
                        Icon(
                            Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Play")
                    }
                }
                OutlinedButton(onClick = onCallBack) {
                    Icon(
                        Icons.Default.Phone,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Call back")
                }
                Spacer(modifier = Modifier.weight(1f))
                IconButton(
                    onClick = onDelete,
                    modifier = Modifier.semantics {
                        contentDescription = "Delete voicemail from ${entry.customer_name ?: entry.from_number}"
                    },
                ) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private fun formatVmDuration(seconds: Int): String = when {
    seconds < 60 -> "${seconds}s"
    seconds < 3600 -> "${seconds / 60}m ${seconds % 60}s"
    else -> "${seconds / 3600}h ${(seconds % 3600) / 60}m"
}

private fun playAudio(context: Context, url: String) {
    runCatching {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            setDataAndType(Uri.parse(url), "audio/*")
        }
        context.startActivity(intent)
    }
}
