package com.bizarreelectronics.crm.ui.screens.audit.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.AuditEntry

/**
 * §52 — Single row in the audit log LazyColumn.
 *
 * Displays: actor avatar icon + actor name, action badge, entity label, diff
 * summary, and ISO timestamp. Tap invokes [onClick] to open the full diff dialog.
 */
@Composable
fun AuditEntryRow(
    entry: AuditEntry,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val actionColor = when (entry.action.lowercase()) {
        "create" -> MaterialTheme.colorScheme.primary
        "delete" -> MaterialTheme.colorScheme.error
        "login", "logout" -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.secondary
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = "Audit entry: ${entry.actor} ${entry.action} ${entry.entityType}"
            },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Default.AccountCircle,
                contentDescription = null,
                modifier = Modifier.size(36.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = entry.actor,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Surface(
                        shape = MaterialTheme.shapes.extraSmall,
                        color = actionColor.copy(alpha = 0.12f),
                    ) {
                        Text(
                            text = entry.action.uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            color = actionColor,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                    if (entry.actorRole.isNotBlank()) {
                        Text(
                            text = entry.actorRole,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                if (!entry.entityLabel.isNullOrBlank()) {
                    Text(
                        text = "${entry.entityType}: ${entry.entityLabel}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else if (entry.entityType.isNotBlank()) {
                    Text(
                        text = entry.entityType,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                if (!entry.diffSummary.isNullOrBlank()) {
                    Text(
                        text = entry.diffSummary,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                    )
                }
            }

            Spacer(Modifier.width(4.dp))

            Text(
                text = formatAuditTimestamp(entry.timestamp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        HorizontalDivider(
            modifier = Modifier.padding(horizontal = 16.dp),
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outlineVariant,
        )
    }
}

/**
 * Minimal timestamp formatter: strips the trailing seconds + timezone for
 * compact display. Falls back to the raw string if parsing fails.
 * Full ISO value is still shown in the detail dialog.
 */
private fun formatAuditTimestamp(iso: String): String {
    return runCatching {
        // "2026-04-23T14:32:11.000Z" -> "04-23 14:32"
        val parts = iso.substringBefore('.').split('T')
        val date = parts[0].substring(5) // MM-DD
        val time = parts.getOrElse(1) { "" }.take(5) // HH:MM
        "$date $time"
    }.getOrDefault(iso.take(16))
}
