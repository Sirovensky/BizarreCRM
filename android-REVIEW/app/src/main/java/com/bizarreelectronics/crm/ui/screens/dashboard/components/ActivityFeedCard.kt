package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp

/**
 * §3.6 L534 — Activity Feed card for the Dashboard.
 *
 * Renders recent CRM activity (ticket updates, customer changes, etc.) in a
 * vertically-scrollable card. Feeds from [DashboardViewModel.recentActivity]
 * which calls [DashboardApi.recentActivity] → `GET /activity?limit=20`.
 * The endpoint stubs to an empty list on 404 — this card shows an empty state
 * rather than an error in that case.
 *
 * @param items      Activity items from the ViewModel. Empty → empty state.
 * @param onShowMore Optional "Show more" handler. When null the button is hidden.
 * @param modifier   Outer modifier.
 */
@Composable
fun ActivityFeedCard(
    items: List<ActivityItem>,
    onShowMore: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            ),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Section heading
            Text(
                text = "Recent Activity",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { heading() },
            )

            if (items.isEmpty()) {
                ActivityEmptyState()
            } else {
                items.forEach { item ->
                    ActivityRow(item = item)
                }

                if (onShowMore != null) {
                    TextButton(
                        onClick = onShowMore,
                        modifier = Modifier.align(Alignment.End),
                    ) {
                        Text("Show more")
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/**
 * §3.6 — A single activity feed entry.
 *
 * @param id        Stable server-assigned row ID.
 * @param actor     Display name of the user who performed the action.
 * @param verb      Action description (e.g. "updated", "created", "closed").
 * @param subject   Subject of the action (e.g. "Ticket #BE-0042").
 * @param timeAgo   Pre-formatted relative time string (e.g. "5m ago", "2h ago").
 * @param avatarInitials Initials for the avatar circle. Null falls back to a generic icon.
 */
data class ActivityItem(
    val id: Long,
    val actor: String,
    val verb: String,
    val subject: String,
    val timeAgo: String,
    val avatarInitials: String? = null,
)

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

@Composable
private fun ActivityEmptyState() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "No recent activity yet"
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = Icons.Default.History,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
        )
        Text(
            text = "No recent activity yet.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ---------------------------------------------------------------------------
// Activity row
// ---------------------------------------------------------------------------

@Composable
private fun ActivityRow(item: ActivityItem) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // Avatar circle
        ActorAvatar(initials = item.avatarInitials)

        Column(modifier = Modifier.weight(1f)) {
            // "Actor verb Subject" with bold actor name
            val annotated = buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                    append(item.actor)
                }
                append(" ${item.verb} ")
                withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) {
                    append(item.subject)
                }
            }
            Text(
                text = annotated,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = item.timeAgo,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f),
            )
        }
    }
}

@Composable
private fun ActorAvatar(initials: String?) {
    Surface(
        modifier = Modifier.size(32.dp),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.primaryContainer,
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (!initials.isNullOrBlank()) {
                Text(
                    text = initials.take(2).uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            } else {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Avatar width constant used in layout (exposed for alignment if needed)
// ---------------------------------------------------------------------------
val ActivityAvatarWidth = 32.dp + 10.dp // avatar + spacing
