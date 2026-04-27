package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.CampaignDto
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

private val BrandCream = Color(0xFFFDEED0)

/**
 * A single campaign row card.
 *
 * Displays name, type+channel badges, status, sent count,
 * and action buttons (Send, Stats, Archive).
 */
@Composable
fun CampaignRow(
    campaign: CampaignDto,
    onSendClick: () -> Unit,
    onStatsClick: () -> Unit,
    onArchiveClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }

    BrandCard(
        modifier = modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = campaign.name,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                    )
                    Spacer(Modifier.height(2.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        TypeBadge(campaign.type)
                        ChannelBadge(campaign.channel)
                        StatusBadge(campaign.status)
                    }
                }
                Box {
                    IconButton(onClick = { expanded = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "Campaign options")
                    }
                    DropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false },
                    ) {
                        if (campaign.status != "archived") {
                            DropdownMenuItem(
                                text = { Text("Send now") },
                                leadingIcon = { Icon(Icons.Default.Send, null) },
                                onClick = {
                                    expanded = false
                                    onSendClick()
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("Stats") },
                            leadingIcon = { Icon(Icons.Default.BarChart, null) },
                            onClick = {
                                expanded = false
                                onStatsClick()
                            },
                        )
                        if (campaign.status != "archived") {
                            DropdownMenuItem(
                                text = { Text("Archive") },
                                leadingIcon = { Icon(Icons.Default.Archive, null) },
                                onClick = {
                                    expanded = false
                                    onArchiveClick()
                                },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatItem(label = "Sent", value = campaign.sentCount)
                StatItem(label = "Replied", value = campaign.repliedCount)
                StatItem(label = "Converted", value = campaign.convertedCount)
            }
        }
    }
}

@Composable
private fun TypeBadge(type: String) {
    val label = when (type) {
        "birthday"            -> "Birthday"
        "winback"             -> "Win-back"
        "review_request"      -> "Review req."
        "churn_warning"       -> "Churn warn."
        "service_subscription" -> "Subscription"
        "custom"              -> "Custom"
        else                  -> type
    }
    SuggestionChip(
        onClick = {},
        label = { Text(label, style = MaterialTheme.typography.labelSmall) },
        modifier = Modifier.height(22.dp),
    )
}

@Composable
private fun ChannelBadge(channel: String) {
    val icon = when (channel) {
        "sms"   -> Icons.Default.Sms
        "email" -> Icons.Default.Email
        else    -> Icons.Default.Campaign
    }
    SuggestionChip(
        onClick = {},
        icon = { Icon(icon, contentDescription = null, modifier = Modifier.size(12.dp)) },
        label = { Text(channel.uppercase(), style = MaterialTheme.typography.labelSmall) },
        modifier = Modifier.height(22.dp),
    )
}

@Composable
private fun StatusBadge(status: String) {
    val (label, color) = when (status) {
        "draft"    -> "Draft"    to MaterialTheme.colorScheme.onSurfaceVariant
        "active"   -> "Active"   to Color(0xFF4CAF50)
        "paused"   -> "Paused"   to Color(0xFFFF9800)
        "archived" -> "Archived" to MaterialTheme.colorScheme.error
        else       -> status     to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Text(
        text = label,
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = Modifier.padding(top = 2.dp),
    )
}

@Composable
private fun StatItem(label: String, value: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = value.toString(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = Color(0xFFFDEED0),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
