package com.bizarreelectronics.crm.ui.screens.sync

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.DateFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * AUD-20260414-M5: VM for the Sync Issues screen.
 *
 * Dead-letter entries are streamed from [SyncQueueDao.observeDeadLetterEntries]
 * so the list updates reactively as entries get retried (and leave the
 * `dead_letter` status) or new entries arrive. Retry actions per row hand off
 * to [SyncManager.retryDeadLetter], which does the status reset + opportunistic
 * flush.
 *
 * [retryingIds] tracks which rows are mid-retry so the UI can disable the button
 * and show a spinner instead. It's a snapshot set, not a Room query, because
 * the dead-letter row leaves the observed list as soon as its status flips back
 * to `pending` — the spinner only needs to live long enough to cover the
 * DAO UPDATE + the flush kick.
 */
@HiltViewModel
class SyncIssuesViewModel @Inject constructor(
    private val syncQueueDao: SyncQueueDao,
    private val syncManager: SyncManager,
) : ViewModel() {

    /** Reactive list of dead-letter entries, newest first. */
    val entries: StateFlow<List<SyncQueueEntity>> = syncQueueDao
        .observeDeadLetterEntries()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = emptyList(),
        )

    private val _retryingIds = MutableStateFlow<Set<Long>>(emptySet())
    val retryingIds: StateFlow<Set<Long>> = _retryingIds.asStateFlow()

    fun retry(id: Long) {
        if (_retryingIds.value.contains(id)) return
        _retryingIds.value = _retryingIds.value + id
        viewModelScope.launch {
            try {
                syncManager.retryDeadLetter(id)
            } finally {
                _retryingIds.value = _retryingIds.value - id
            }
        }
    }
}

/**
 * AUD-20260414-M5: "Sync Issues" screen.
 *
 * Shows a LazyColumn of every row in `sync_queue` with `status = 'dead_letter'`:
 *   - Entity type ("ticket", "customer", "inventory", …)
 *   - Short error message (truncated to 2 lines) pulled from `last_error`
 *   - Relative timestamp of when the entry was first queued (`created_at`)
 *   - Retry button that calls [SyncIssuesViewModel.retry] to resurrect the
 *     row back into the pending queue + kick an immediate flush
 *
 * Empty state: a calm "All synced" message with a CheckCircle icon. Appears
 * the moment the list drains so the user gets visual confirmation their
 * retry worked.
 *
 * No discard action — the 30-day retention sweep on [SyncManager] is the only
 * path that removes entries. That's intentional: a failed sync almost always
 * represents work the user wants preserved (a ticket, a customer, a note);
 * making a discard button easy-to-reach would invite accidental data loss.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncIssuesScreen(
    onBack: () -> Unit,
    viewModel: SyncIssuesViewModel = hiltViewModel(),
) {
    val entries by viewModel.entries.collectAsState()
    val retryingIds by viewModel.retryingIds.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Sync issues",
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
    ) { padding ->
        if (entries.isEmpty()) {
            SyncIssuesEmptyState(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    top = 16.dp,
                    bottom = 16.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Text(
                        // Short explainer so the user knows why these are here
                        // and what Retry does — the more technical "dead-letter"
                        // wording stays inside SyncQueueDao docs.
                        text = "These changes could not be sent to the server after several attempts. Tap Retry to put them back in the queue.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(
                    items = entries,
                    // Stable Room primary key — lets Compose reuse row
                    // composition across list updates (retries / resurrections).
                    key = { it.id },
                ) { entry ->
                    SyncIssueRow(
                        entry = entry,
                        isRetrying = retryingIds.contains(entry.id),
                        onRetry = { viewModel.retry(entry.id) },
                    )
                }
            }
        }
    }
}

/**
 * Single dead-letter row. Uses [BrandCard] so it matches the card surface
 * used across the app instead of a bare divider list.
 */
@Composable
private fun SyncIssueRow(
    entry: SyncQueueEntity,
    isRetrying: Boolean,
    onRetry: () -> Unit,
) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // Header row: entity type + operation on the left, relative
            // timestamp on the right. Both pieces are small — the failure
            // reason is what the user actually needs to read.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = formatEntityLabel(entry),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = DateFormatter.formatRelative(entry.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Short error line — kept in error color so the severity is
            // obvious at a glance, max 2 lines so a huge stack trace
            // doesn't blow the card out.
            Text(
                text = entry.lastError?.takeIf { it.isNotBlank() }
                    ?: "Sync failed after $MAX_RETRIES_PLACEHOLDER attempts",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                maxLines = 2,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )

            // Retry button — OutlinedButton so it stays secondary to the
            // primary action on the parent screen (if any). Disabled + spinner
            // while the retry is in-flight.
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                OutlinedButton(
                    onClick = onRetry,
                    enabled = !isRetrying,
                ) {
                    if (isRetrying) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(14.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("Retrying\u2026")
                    } else {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("Retry")
                    }
                }
            }
        }
    }
}

/**
 * Empty-state ("All synced") shown when there are zero dead-letter entries.
 * A calm CheckCircle + bodyMedium line is enough — the user got here via an
 * explicit nav, so we don't need a marketing-copy empty state.
 */
@Composable
private fun SyncIssuesEmptyState(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.secondary,
            )
            Text(
                text = "All synced",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "No pending sync failures.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Pretty-prints `"ticket / create"` from the entity + operation columns. The
 * raw values are snake-case-ish (`"ticket_device"`, `"add_part"`) so we
 * sentence-case them for display without touching the persisted values —
 * [SyncManager] still dispatches on the canonical snake values.
 */
private fun formatEntityLabel(entry: SyncQueueEntity): String {
    val type = entry.entityType.replace('_', ' ')
        .replaceFirstChar { it.uppercase() }
    val op = entry.operation.replace('_', ' ')
    return "$type \u2022 $op"
}

/**
 * Used in the placeholder last-error string when the row has no stored error.
 * MAX_RETRIES is not imported directly to keep this file free of DAO-companion
 * coupling — the display value only ever shows up when last_error is blank
 * (which shouldn't happen for rows written by the current SyncManager, but can
 * happen for rows promoted to dead_letter before the last_error column was
 * persisted reliably).
 */
private const val MAX_RETRIES_PLACEHOLDER = 5
