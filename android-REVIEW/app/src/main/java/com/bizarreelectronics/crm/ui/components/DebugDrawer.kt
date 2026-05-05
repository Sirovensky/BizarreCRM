package com.bizarreelectronics.crm.ui.components

import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import coil3.SingletonImageLoader
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.sync.CacheEvictor
import com.bizarreelectronics.crm.data.sync.DeltaSyncer
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.data.sync.SyncWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.launch
import leakcanary.AppWatcher
import leakcanary.LeakCanary
import javax.inject.Inject

/**
 * §20.12 — Developer debug drawer: force offline / force sync / inspect queue /
 * inspect dead-letter / clear cache / reset sync state.
 *
 * Gated by [com.bizarreelectronics.crm.BuildConfig.DEBUG] at the call site —
 * never ship in production builds.
 *
 * ## Actions
 *
 * | Button              | Effect                                                   |
 * |---------------------|----------------------------------------------------------|
 * | Force Sync Now      | Enqueues an expedited one-time WorkManager sync          |
 * | Run Cache Eviction  | Trims entity tables to their configured caps immediately |
 * | Reset Delta Cursor  | Clears all SyncState rows → next sync is a full refresh  |
 * | Clear Coil Cache    | Flushes the in-memory image cache                        |
 *
 * ## Queue inspect panel
 *
 * Shows live pending + dead-letter counts from [SyncQueueDao]. The developer
 * can read entity-level details from the DiagnosticsScreen; this drawer is for
 * quick triage without leaving the current screen.
 *
 * ## LeakCanary panel (§20.12)
 *
 * Reads [AppWatcher.objectWatcher.retainedObjectCount] on a 2-second poll and
 * exposes it as [retainedObjectCount]. A non-zero count lights up in
 * [MaterialTheme.colorScheme.error] and an "Analyse Leaks" button triggers
 * [LeakCanary.dumpHeap] to force a heap dump / notification.
 */
@HiltViewModel
class DebugDrawerViewModel @Inject constructor(
    private val syncQueueDao: SyncQueueDao,
    private val syncStateDao: SyncStateDao,
    private val syncManager: SyncManager,
    private val cacheEvictor: CacheEvictor,
    private val deltaSyncer: DeltaSyncer,
) : ViewModel() {

    data class QueueStats(
        val pending: Int = 0,
        val deadLetter: Int = 0,
    )

    val queueStats: StateFlow<QueueStats> = combine(
        syncQueueDao.getCount(),             // pending
        syncQueueDao.getDeadLetterCount(),   // dead-letter
    ) { pending, dead -> QueueStats(pending = pending, deadLetter = dead) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), QueueStats())

    /**
     * §20.12 — Polls [AppWatcher.objectWatcher.retainedObjectCount] every 2 s.
     * Non-zero means LeakCanary has already detected suspect retained objects;
     * tap "Analyse Leaks" to trigger a heap dump for full analysis.
     */
    val retainedObjectCount: StateFlow<Int> = flow {
        while (true) {
            emit(AppWatcher.objectWatcher.retainedObjectCount)
            delay(2_000)
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    fun forceSyncNow(context: android.content.Context) {
        SyncWorker.syncNow(context)
        _statusMessage.value = "SyncWorker.syncNow enqueued"
        Log.d(TAG, "debug: forceSyncNow")
    }

    fun runCacheEviction() {
        viewModelScope.launch {
            try {
                cacheEvictor.runEviction()
                _statusMessage.value = "Cache eviction complete"
            } catch (e: Exception) {
                _statusMessage.value = "Eviction failed: ${e.message}"
            }
        }
    }

    fun resetDeltaCursor() {
        viewModelScope.launch {
            try {
                syncStateDao.clear()
                _statusMessage.value = "Delta cursor cleared — next sync is full"
                Log.d(TAG, "debug: delta cursor reset")
            } catch (e: Exception) {
                _statusMessage.value = "Reset failed: ${e.message}"
            }
        }
    }

    fun clearCoilMemoryCache(context: android.content.Context) {
        SingletonImageLoader.get(context).memoryCache?.clear()
        _statusMessage.value = "Coil memory cache cleared"
        Log.d(TAG, "debug: coil memory cache cleared")
    }

    fun clearStatusMessage() {
        _statusMessage.value = null
    }

    /**
     * §20.12 — Trigger a LeakCanary heap dump so it can analyse retained objects
     * and post a notification with the leak trace. Only meaningful when
     * [retainedObjectCount] > 0; safe to call at any time (no-op if nothing retained).
     */
    fun analyseLeaks() {
        val retained = AppWatcher.objectWatcher.retainedObjectCount
        if (retained > 0) {
            LeakCanary.dumpHeap()
            _statusMessage.value = "Heap dump triggered ($retained retained)"
            Log.d(TAG, "debug: analyseLeaks — $retained retained objects, heap dump triggered")
        } else {
            _statusMessage.value = "No retained objects — nothing to analyse"
            Log.d(TAG, "debug: analyseLeaks — 0 retained, skipped heap dump")
        }
    }

    companion object {
        private const val TAG = "DebugDrawer"
    }
}

/**
 * Debug drawer panel. Embed inside a `ModalDrawerSheet` or any container;
 * the caller controls the drawer visibility.
 *
 * **Only render in DEBUG builds:**
 * ```kotlin
 * if (BuildConfig.DEBUG) {
 *     DebugDrawer(onClose = { drawerState.close() })
 * }
 * ```
 */
@Composable
fun DebugDrawer(
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: DebugDrawerViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val stats by viewModel.queueStats.collectAsState()
    val statusMessage by viewModel.statusMessage.collectAsState()
    val retainedCount by viewModel.retainedObjectCount.collectAsState()

    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Header
            Text(
                "Debug Drawer",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                "Dev-only. Not visible in release builds.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )

            HorizontalDivider()

            // Queue stats
            Text("Sync Queue", style = MaterialTheme.typography.titleSmall)
            Text(
                "Pending: ${stats.pending}   Dead-letter: ${stats.deadLetter}",
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            HorizontalDivider()

            // Actions
            Text("Actions", style = MaterialTheme.typography.titleSmall)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = { viewModel.forceSyncNow(context) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Force Sync")
                }
                OutlinedButton(
                    onClick = { viewModel.runCacheEviction() },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Evict Cache")
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = { viewModel.resetDeltaCursor() },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Reset Cursor")
                }
                OutlinedButton(
                    onClick = { viewModel.clearCoilMemoryCache(context) },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Clear Images")
                }
            }

            // §20.12 — LeakCanary retained-object panel
            HorizontalDivider()
            Text("Memory (LeakCanary)", style = MaterialTheme.typography.titleSmall)
            Text(
                text = if (retainedCount == 0) "Retained objects: 0  ✓" else "Retained objects: $retainedCount  ⚠",
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                color = if (retainedCount > 0) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(
                onClick = { viewModel.analyseLeaks() },
                modifier = Modifier.fillMaxWidth(),
                enabled = retainedCount > 0,
            ) {
                Text(if (retainedCount > 0) "Analyse Leaks ($retainedCount)" else "Analyse Leaks")
            }

            // Status message
            statusMessage?.let { msg ->
                HorizontalDivider()
                Text(
                    text = msg,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }

            HorizontalDivider()

            // Close
            Button(
                onClick = onClose,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                ),
            ) {
                Text("Close Debug Drawer")
            }
        }
    }
}
