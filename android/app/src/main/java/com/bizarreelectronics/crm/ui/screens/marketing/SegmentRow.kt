package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.SegmentDto
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

/**
 * A single segment row card.
 *
 * Shows segment name, description, member count, and an "Auto" badge
 * for server-managed auto segments.
 *
 * Plan §37.3 (ActionPlan.md lines ~3285-3295).
 */
@Composable
fun SegmentRow(
    segment: SegmentDto,
    modifier: Modifier = Modifier,
) {
    BrandCard(
        modifier = modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.Group,
                contentDescription = null,
                tint = Color(0xFFFDEED0),
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = segment.name,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                    if (segment.isAuto == 1) {
                        SuggestionChip(
                            onClick = {},
                            label = { Text("Auto", style = MaterialTheme.typography.labelSmall) },
                            modifier = Modifier.height(20.dp),
                        )
                    }
                }
                if (!segment.description.isNullOrBlank()) {
                    Text(
                        text = segment.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            }
            if (segment.memberCount > 0) {
                Text(
                    text = "${segment.memberCount}",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFFFDEED0),
                )
            }
        }
    }
}
