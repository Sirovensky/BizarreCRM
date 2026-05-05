package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * §3.12 L562 — Team Inbox KPI tile.
 *
 * Shows the unread team-inbox message count from `GET /inbox`.
 * Tap navigates to the inbox route (stub nav — logs if screen is absent).
 *
 * **Graceful degradation**: when [unreadCount] is null the tile is hidden
 * (the caller should skip rendering this composable). A null value indicates
 * either a 404 response (endpoint not yet implemented) or a network failure.
 *
 * @param unreadCount Unread team-inbox count. Null = hide tile.
 * @param onNavigateToInbox Callback invoked when the tile is tapped.
 */
@Composable
fun TeamInboxTile(
    unreadCount: Int,
    onNavigateToInbox: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tint = if (unreadCount > 0) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Card(
        modifier = modifier
            .defaultMinSize(minHeight = 48.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "Team Inbox: $unreadCount unread. Tap to open."
                role = Role.Button
            }
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .clickable(onClick = onNavigateToInbox),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 16.dp),
        ) {
            Icon(
                Icons.Default.Inbox,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = unreadCount.toString(),
                style = MaterialTheme.typography.headlineMedium,
                color = tint,
            )
            Text(
                text = "Team Inbox",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
