package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.NetworkMonitor
import javax.inject.Inject

/**
 * §16.9 — Offline-mode banner pinned to the top of the POS screen.
 *
 * Shown when [NetworkMonitor.isOnline] emits false (no interface with
 * INTERNET capability). Disappears automatically when connectivity returns.
 *
 * Behaviour:
 *  - Cash sales bypass network check entirely — they still work.
 *  - Non-cash sales are queued in sync_queue with an idempotency key.
 *  - The drain-worker resolves the queue on reconnect.
 *  - Failures after reconnect → dead-letter queue (§20.7).
 *
 * Note: [NetworkMonitor] reports general connectivity. The actual server
 * reachability is governed by [ServerReachabilityMonitor]; the POS
 * offline banner reacts to either signal via [isOffline].
 */
@Composable
fun PosOfflineBanner(
    isOffline: Boolean,
    pendingQueueCount: Int = 0,
    modifier: Modifier = Modifier,
) {
    AnimatedVisibility(
        visible = isOffline,
        enter = expandVertically() + fadeIn(),
        exit = shrinkVertically() + fadeOut(),
        modifier = modifier,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.errorContainer)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .semantics {
                    liveRegion = LiveRegionMode.Polite
                },
        ) {
            Icon(
                imageVector = Icons.Default.CloudOff,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Offline — cash sales only",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                if (pendingQueueCount > 0) {
                    Text(
                        text = "$pendingQueueCount sale${if (pendingQueueCount == 1) "" else "s"} queued",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.8f),
                    )
                }
            }
            Icon(
                imageVector = Icons.Default.Sync,
                contentDescription = "Will sync when online",
                tint = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.6f),
            )
        }
    }
}
