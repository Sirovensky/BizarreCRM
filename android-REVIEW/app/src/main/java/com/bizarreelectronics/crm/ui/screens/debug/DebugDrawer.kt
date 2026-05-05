package com.bizarreelectronics.crm.ui.screens.debug

import android.content.Context
import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.sync.SyncWorker
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

/**
 * §20.12 — Debug drawer ViewModel.
 *
 * Exposes queue stats + async actions for the developer debug panel.
 * Only wired in DEBUG builds (the composable guards with [BuildConfig.DEBUG]).
 *
 * Actions:
 *  - [forceOffline] / [clearForceOffline] — toggle offline simulation via
 *    [ServerReachabilityMonitor] (reports failure/success to the monitor without
 *    an actual network change so the offline banner appears in-app).
 *  - [forceSync] — kick [SyncWorker.syncNow] for an immediate drain pass.
 *  - [clearCache] — wipe all Room tables (equivalent to logout data-wipe).
 *  - [resetSyncState] — delete all [SyncStateDao] rows so the next sync
 *    treats every entity as first-run.
 *
 * Observables for inspection:
 *  - [pendingQueueCount] — count of `status = 'pending'` queue entries.
 *  - [deadLetterCount] — count of `status = 'dead_letter'` entries.
 */
@HiltViewModel
class DebugDrawerViewModel @Inject constructor(
    @ApplicationContext private val appContext: Context,
    private val syncQueueDao: SyncQueueDao,
    private val syncStateDao: SyncStateDao,
    private val database: BizarreDatabase,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    val pendingQueueCount: StateFlow<Int> = syncQueueDao.getCount()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    val deadLetterCount: StateFlow<Int> = syncQueueDao.getDeadLetterCount()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    /** True while the monitor's _isServerReachable has been forced to false. */
    private val _isOfflineForced = MutableStateFlow(false)
    val isOfflineForced: StateFlow<Boolean> = _isOfflineForced.asStateFlow()

    fun forceOffline() {
        serverMonitor.reportFailure()
        serverMonitor.reportFailure() // two consecutive failures trigger offline state
        _isOfflineForced.value = true
        _statusMessage.value = "Forced offline"
        Log.d(TAG, "Debug: force-offline activated")
    }

    fun clearForceOffline() {
        serverMonitor.reportSuccess()
        _isOfflineForced.value = false
        _statusMessage.value = "Back online"
        Log.d(TAG, "Debug: force-offline cleared")
    }

    fun forceSync(context: Context) {
        SyncWorker.syncNow(context)
        _statusMessage.value = "Sync kicked"
        Log.d(TAG, "Debug: force-sync kicked")
    }

    fun clearCache() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                database.clearAllTables()
            }
            _statusMessage.value = "Cache cleared"
            Log.d(TAG, "Debug: clearAllTables complete")
        }
    }

    fun resetSyncState() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                syncStateDao.clear()
            }
            _statusMessage.value = "Sync state reset"
            Log.d(TAG, "Debug: sync_state cleared")
        }
    }

    companion object {
        private const val TAG = "DebugDrawer"
    }
}

/**
 * §20.12 — Debug drawer composable.
 *
 * Renders inside a `ModalNavigationDrawer` or any side-sheet in the host
 * [AppNavGraph]. Guarded by [BuildConfig.DEBUG] — renders nothing in release
 * builds (the entire Composable call-graph is dead-code-eliminated by R8).
 *
 * ## Sections
 *
 *  1. **Connection** — force offline / clear forced offline.
 *  2. **Sync** — force sync now; counts of pending + dead-letter queue entries.
 *  3. **Cache** — clear Room cache / reset sync-state cursors.
 *  4. **Build info** — versionName / versionCode / BuildConfig.DEBUG.
 *
 * All buttons use [FilledTonalButton] (M3 Expressive tonal hierarchy — secondary
 * action weight without the prominence of a primary FilledButton).
 */
@Composable
fun DebugDrawer(
    modifier: Modifier = Modifier,
    viewModel: DebugDrawerViewModel = hiltViewModel(),
) {
    if (!BuildConfig.DEBUG) return

    val pendingCount by viewModel.pendingQueueCount.collectAsState()
    val deadLetterCount by viewModel.deadLetterCount.collectAsState()
    val isOfflineForced by viewModel.isOfflineForced.collectAsState()
    val statusMessage by viewModel.statusMessage.collectAsState()
    val context = LocalContext.current

    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Debug Tools",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )

        statusMessage?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
            )
        }

        HorizontalDivider()

        // ── Connection ────────────────────────────────────────────────────────
        DebugSection(title = "Connection") {
            if (isOfflineForced) {
                FilledTonalButton(
                    onClick = { viewModel.clearForceOffline() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Clear forced offline")
                }
            } else {
                FilledTonalButton(
                    onClick = { viewModel.forceOffline() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Force offline")
                }
            }
        }

        HorizontalDivider()

        // ── Sync ──────────────────────────────────────────────────────────────
        DebugSection(title = "Sync") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "Pending: $pendingCount",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "Dead-letter: $deadLetterCount",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (deadLetterCount > 0) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            FilledTonalButton(
                onClick = { viewModel.forceSync(context) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Force sync now")
            }
        }

        HorizontalDivider()

        // ── Cache ─────────────────────────────────────────────────────────────
        DebugSection(title = "Cache") {
            FilledTonalButton(
                onClick = { viewModel.clearCache() },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Clear cache (wipe Room tables)")
            }
            FilledTonalButton(
                onClick = { viewModel.resetSyncState() },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Reset sync state (clear cursors)")
            }
        }

        HorizontalDivider()

        // ── Build info ────────────────────────────────────────────────────────
        DebugSection(title = "Build") {
            Text(
                "Version ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "DEBUG = ${BuildConfig.DEBUG}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Labelled section card used inside [DebugDrawer].
 * Uses [OutlinedCard] to visually group related debug actions.
 */
@Composable
private fun DebugSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            content()
        }
    }
}
