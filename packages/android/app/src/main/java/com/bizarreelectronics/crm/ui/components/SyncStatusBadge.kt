package com.bizarreelectronics.crm.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
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

/**
 * Visual indicator showing how many rows are waiting to sync to the server
 * and whether a sync is currently running. Designed to sit in an app-bar
 * action slot or on top of the dashboard.
 *
 * The badge is a pure View — it does NOT inject Hilt dependencies itself.
 * The caller is expected to pass in already-collected Flows so the same
 * component can be reused on any screen (dashboard, tickets list, etc.).
 *
 * ## States (brand-aligned)
 *   - Syncing now: `purpleContainer` bg — brand active.
 *   - Pending > 0: `magentaContainer` bg — attention, NOT errorContainer.
 *     Red is reserved for real errors. Gentle 600ms alpha pulse (0.9 → 1.0).
 *   - Clean: `tealContainer` (secondaryContainer) bg — calm, resolved.
 *
 * Icons are unchanged from the original implementation.
 */
@Composable
fun SyncStatusBadge(
    isSyncingFlow: StateFlow<Boolean>,
    pendingCountFlow: Flow<Int>,
    onForceSync: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isSyncing by isSyncingFlow.collectAsState()
    val pendingCount by pendingCountFlow.collectAsState(initial = 0)

    val isPending = !isSyncing && pendingCount > 0

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
        else -> BadgeVisual(
            icon = Icons.Filled.CloudDone,
            label = "Synced",
            container = MaterialTheme.colorScheme.secondaryContainer,  // teal
            onContainer = MaterialTheme.colorScheme.onSecondaryContainer,
        )
    }

    Surface(
        modifier = modifier
            .then(if (isPending) Modifier.alpha(pulseAlpha) else Modifier)
            .clickable(enabled = !isSyncing, onClick = onForceSync),
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
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
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
