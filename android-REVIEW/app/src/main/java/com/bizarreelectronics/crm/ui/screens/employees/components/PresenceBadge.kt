package com.bizarreelectronics.crm.ui.screens.employees.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber

/**
 * §14.1 L1611 — Presence badge.
 *
 * Small coloured dot indicating live presence status:
 *   - green  = clocked in (online, working)
 *   - amber  = on break
 *   - gray   = off / not clocked in, or WebSocket event absent (stub state)
 *
 * Real-time updates arrive via WebSocket events with topic "presence".
 * When no WS event has been received, the VM defaults to [PresenceStatus.Off].
 */
enum class PresenceStatus { ClockedIn, OnBreak, Off }

@Composable
fun PresenceBadge(
    status: PresenceStatus,
    size: Dp = 10.dp,
    borderWidth: Dp = 1.5.dp,
    modifier: Modifier = Modifier,
) {
    val color: Color = when (status) {
        PresenceStatus.ClockedIn -> SuccessGreen
        PresenceStatus.OnBreak -> WarningAmber
        PresenceStatus.Off -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
    }
    val label = when (status) {
        PresenceStatus.ClockedIn -> "Clocked in"
        PresenceStatus.OnBreak -> "On break"
        PresenceStatus.Off -> "Not clocked in"
    }
    Box(
        modifier = modifier
            .size(size)
            .background(color = color, shape = CircleShape)
            .border(
                width = borderWidth,
                color = MaterialTheme.colorScheme.surface,
                shape = CircleShape,
            )
            .semantics { contentDescription = label },
    )
}
