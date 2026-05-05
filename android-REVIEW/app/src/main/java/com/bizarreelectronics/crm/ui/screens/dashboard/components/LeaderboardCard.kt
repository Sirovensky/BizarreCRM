package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L502 — Leaderboard card.
 *
 * Shows the top 5 staff members ranked by tickets closed or revenue generated.
 * Each row: rank medal + name + primary metric.
 *
 * Data contract:
 * - [entries]: list of [LeaderboardEntry]. Empty = stub "No leaderboard data" state.
 * - Display is capped at 5 rows; extras are silently ignored.
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/** One row in the leaderboard. */
data class LeaderboardEntry(
    val staffName: String,
    /** Human-readable metric string, e.g. "12 tickets" or "$1,240". */
    val metricLabel: String,
)

// TODO: cream-theme — pick token — medal colors (gold/silver/bronze) are decorative; no theme token equivalent
private val MEDAL_COLORS = listOf(
    Color(0xFFFFD700), // Gold
    Color(0xFFC0C0C0), // Silver
    Color(0xFFCD7F32), // Bronze
)

@Composable
fun LeaderboardCard(
    entries: List<LeaderboardEntry>,
    /** Label shown next to the icon, e.g. "Top Staff (Tickets Closed)". */
    title: String = "Top Staff",
    modifier: Modifier = Modifier,
) {
    val displayed = entries.take(5)
    val isEmpty = displayed.isEmpty()

    val a11yDesc = if (isEmpty) {
        "Leaderboard: no data available."
    } else {
        "Leaderboard: top ${displayed.size} staff. ${displayed.first().staffName} leads with ${displayed.first().metricLabel}."
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .semantics { contentDescription = a11yDesc },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.EmojiEvents,
                    contentDescription = null,
                    // TODO: cream-theme — pick token — gold trophy tint; decorative, matches MEDAL_COLORS[0]
                    tint = Color(0xFFFFD700),
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            if (isEmpty) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(80.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No leaderboard data",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            } else {
                // Use a Column instead of LazyColumn — max 5 rows, so LazyColumn
                // overhead is unnecessary and causes nested-scroll issues inside
                // LazyColumn (DashboardScreen).
                displayed.forEachIndexed { index, entry ->
                    LeaderboardRow(
                        rank = index + 1,
                        entry = entry,
                        medalColor = MEDAL_COLORS.getOrNull(index),
                    )
                    if (index < displayed.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(vertical = 4.dp),
                            thickness = 0.5.dp,
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LeaderboardRow(
    rank: Int,
    entry: LeaderboardEntry,
    medalColor: Color?,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Rank badge
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .border(
                    width = 1.dp,
                    color = medalColor ?: MaterialTheme.colorScheme.outline,
                    shape = CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = rank.toString(),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = medalColor ?: MaterialTheme.colorScheme.onSurface,
            )
        }

        // Avatar placeholder
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outline,
                    shape = CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Default.Person,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
        }

        // Name
        Text(
            text = entry.staffName,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )

        // Metric
        Text(
            text = entry.metricLabel,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}
