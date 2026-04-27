package com.bizarreelectronics.crm.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Visual indicator showing how many rows are waiting to sync to the server
 * and whether a sync is currently running. Designed to sit in an app-bar
 * action slot or on top of the dashboard.
 *
 * The badge is a pure View — it does NOT inject Hilt dependencies itself.
 * The caller is expected to pass in already-collected Flows so the same
 * component can be reused on any screen (dashboard, tickets list, etc.).
 *
 * ## States (brand-aligned, §20.11)
 *   - Syncing now: `purpleContainer` bg — brand active.
 *   - Pending > 0: `magentaContainer` bg — attention, NOT errorContainer.
 *     Red is reserved for real errors. Gentle 600ms alpha pulse (0.9 → 1.0).
 *     Label: "Pending N".
 *   - Offline (no pending): `surfaceVariant` bg — muted, informational.
 *     Label: "Offline".
 *   - Clean + synced: `tealContainer` (secondaryContainer) bg — calm, resolved.
 *     Label: "Synced Xm ago" when [lastSyncedAt] is provided, "Synced" otherwise.
 *
 * Icons are unchanged from the original implementation.
 *
 * @param lastSyncedAt  Optional ISO-8601 / datetime string of the last full sync
 *                      completion (from [AppPreferences.lastFullSyncAt]). When
 *                      non-null, the clean-state label shows a relative time
 *                      ("Synced 3m ago") so the user can judge freshness.
 * @param isOffline     When true and there are no pending rows, the badge shows
 *                      "Offline" in a muted surface variant colour instead of the
 *                      clean green-teal. Defaults false (legacy callers unaffected).
 */
@Composable
fun SyncStatusBadge(
    isSyncingFlow: StateFlow<Boolean>,
    pendingCountFlow: Flow<Int>,
    onForceSync: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * §3.10 — route tap to Settings → Data → Sync Issues when the queue
     * has unsynced rows (pending count > 0). The default behavior is to
     * force a sync, which is fine when everything's already clean but
     * the wrong action when a row is stuck and the user actually wants
     * to diagnose. Null disables the redirect (keeps legacy callers
     * unchanged).
     */
    onOpenIssues: (() -> Unit)? = null,
    /** §20.11 — ISO-8601 / space-separated datetime of last full sync (nullable). */
    lastSyncedAt: String? = null,
    /** §20.11 — Whether the device is currently offline (no server reachability). */
    isOffline: Boolean = false,
) {
    val isSyncing by isSyncingFlow.collectAsState()
    val pendingCount by pendingCountFlow.collectAsState(initial = 0)

    val isPending = !isSyncing && pendingCount > 0
    // When the queue is pending and the caller wired an issues route, a tap
    // on the badge should land the user on Sync Issues rather than kick off
    // yet another sync attempt that will likely land in the same pending
    // state. Any other state (syncing / clean) still fires force-sync.
    val onTap: () -> Unit = if (isPending && onOpenIssues != null) onOpenIssues else onForceSync

    // 600ms gentle pulse for pending state (0.9 → 1.0 alpha)
    val infiniteTransition = rememberInfiniteTransition(label = "syncPulse")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.9f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 600),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseAlpha",
    )

    val (icon, label, container, onContainer) = when {
        isSyncing -> BadgeVisual(
            icon = Icons.Filled.CloudSync,
            label = "Syncing\u2026",
            container = MaterialTheme.colorScheme.primaryContainer,    // purple
            onContainer = MaterialTheme.colorScheme.onPrimaryContainer,
        )
        pendingCount > 0 -> BadgeVisual(
            icon = Icons.Filled.CloudOff,
            label = "$pendingCount unsynced",
            container = MaterialTheme.colorScheme.tertiaryContainer,   // magenta (NOT error)
            onContainer = MaterialTheme.colorScheme.onTertiaryContainer,
        )
        isOffline && pendingCount == 0 -> BadgeVisual(
            icon = Icons.Filled.CloudOff,
            label = "Offline",
            container = MaterialTheme.colorScheme.surfaceVariant,
            onContainer = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        else -> BadgeVisual(
            icon = Icons.Filled.CloudDone,
            // §20.11 — show relative "Synced Xm ago" when lastSyncedAt is available
            // so the user can judge data freshness at a glance.
            label = relativeTimeLabel(lastSyncedAt),
            container = MaterialTheme.colorScheme.secondaryContainer,  // teal
            onContainer = MaterialTheme.colorScheme.onSecondaryContainer,
        )
    }

    // D5-3: use Surface(onClick = ...) overload so M3 fires the native ripple
    // on tap. Layering .clickable on top of Surface suppressed the indication
    // because the Surface's own surface layer drew over the ripple target.
    Surface(
        onClick = onTap,
        enabled = !isSyncing,
        modifier = modifier
            .then(if (isPending) Modifier.alpha(pulseAlpha) else Modifier),
        color = container,
        contentColor = onContainer,
        shape = MaterialTheme.shapes.small,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (isSyncing) {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    strokeWidth = 2.dp,
                    color = onContainer,
                )
            } else {
                Icon(
                    imageVector = icon,
                    // decorative — Surface(onClick) wraps with Role.Button and
                    // the sibling label Text ("Synced" / "N unsynced") provides
                    // the accessible name TalkBack announces (D5-1).
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
    }
}

/**
 * §20.11 — Build a human-readable relative sync label.
 *
 * Accepted formats for [syncedAt]:
 *  - ISO-8601 / `"2026-04-26 14:30:00"` (SyncManager stores this)
 *  - null → "Synced" (fallback for callers that don't provide the timestamp)
 *
 * Examples: "Synced 2m ago", "Synced 1h ago", "Synced just now"
 */
private fun relativeTimeLabel(syncedAt: String?): String {
    if (syncedAt.isNullOrBlank()) return "Synced"
    return try {
        // SyncManager stores "2026-04-26 14:30:00" (space-separated, no T). Normalise.
        val normalised = syncedAt.trim().replace(' ', 'T').let {
            if (!it.contains('Z') && !it.contains('+')) "${it}Z" else it
        }
        val syncInstant = Instant.parse(normalised)
        val now = Instant.now()
        val minutesAgo = ChronoUnit.MINUTES.between(syncInstant, now)
        when {
            minutesAgo < 1L -> "Synced just now"
            minutesAgo < 60L -> "Synced ${minutesAgo}m ago"
            minutesAgo < 1440L -> "Synced ${minutesAgo / 60}h ago"
            else -> "Synced ${minutesAgo / 1440}d ago"
        }
    } catch (_: Exception) {
        "Synced"
    }
}

/**
 * Pure data holder for badge visual properties.
 */
private data class BadgeVisual(
    val icon: ImageVector,
    val label: String,
    val container: androidx.compose.ui.graphics.Color,
    val onContainer: androidx.compose.ui.graphics.Color,
)
