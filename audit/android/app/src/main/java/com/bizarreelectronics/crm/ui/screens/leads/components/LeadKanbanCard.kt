package com.bizarreelectronics.crm.ui.screens.leads.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.PhoneFormatter

/**
 * Kanban card for a single lead (ActionPlan §9 L1382-L1387).
 *
 * Displays: name + phone + score chip + next-action date.
 *
 * Drag state is passed in as [isDragging] so the card visually elevates
 * when being dragged. The actual drag gesture is wired in [LeadKanbanBoard]
 * via [Modifier.pointerInput].
 *
 * @param lead          The lead entity to display.
 * @param isDragging    Elevates the card shadow when true.
 * @param onLeadClick   Tap handler.
 */
@Composable
fun LeadKanbanCard(
    lead: LeadEntity,
    isDragging: Boolean = false,
    onLeadClick: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val fullName = listOfNotNull(lead.firstName, lead.lastName)
        .joinToString(" ")
        .ifBlank { "Unknown" }
    val phoneFormatted = if (!lead.phone.isNullOrBlank()) PhoneFormatter.format(lead.phone) else null
    val nextActionDate = DateFormatter.formatRelative(lead.updatedAt)

    // Score chip colour: <40 error, 40-69 tertiary, 70+ primary
    val scoreColor = when {
        lead.leadScore >= 70 -> MaterialTheme.colorScheme.primaryContainer
        lead.leadScore >= 40 -> MaterialTheme.colorScheme.tertiaryContainer
        else -> MaterialTheme.colorScheme.errorContainer
    }
    val scoreOnColor = when {
        lead.leadScore >= 70 -> MaterialTheme.colorScheme.onPrimaryContainer
        lead.leadScore >= 40 -> MaterialTheme.colorScheme.onTertiaryContainer
        else -> MaterialTheme.colorScheme.onErrorContainer
    }

    val cardDescription = buildString {
        append(fullName)
        if (phoneFormatted != null) append(", $phoneFormatted")
        append(", score ${lead.leadScore}")
        if (nextActionDate.isNotBlank()) append(", updated $nextActionDate")
    }

    Card(
        onClick = { onLeadClick(lead.id) },
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = cardDescription },
        elevation = CardDefaults.cardElevation(
            defaultElevation = if (isDragging) 8.dp else 1.dp,
        ),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // Name row + score chip
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = fullName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Spacer(modifier = Modifier.width(6.dp))
                SuggestionChip(
                    onClick = {},
                    label = {
                        Text(
                            text = "${lead.leadScore}",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                        )
                    },
                    modifier = Modifier.height(24.dp),
                    colors = SuggestionChipDefaults.suggestionChipColors(
                        containerColor = scoreColor,
                        labelColor = scoreOnColor,
                    ),
                )
            }

            // Phone
            if (phoneFormatted != null) {
                Text(
                    text = phoneFormatted,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Next-action date row
            if (nextActionDate.isNotBlank()) {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = nextActionDate,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
