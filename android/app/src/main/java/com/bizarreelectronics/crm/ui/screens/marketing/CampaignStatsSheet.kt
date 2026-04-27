package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.CampaignStatsData
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

private val BrandCream = Color(0xFFFDEED0)

/**
 * Bottom sheet showing per-campaign open/click/send metrics.
 *
 * Data comes from GET /campaigns/:id/stats which returns:
 *   { campaign, counts: { sent, failed, replied, converted } }
 *
 * "Opens" and "clicks" are not tracked server-side (requires pixel/click
 * tracking not yet implemented). Displaying sent/replied/converted instead.
 *
 * Plan §37.1.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CampaignStatsSheet(
    stats: CampaignStatsData,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stats.campaign.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )

            BrandCard {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    val sent = stats.counts["sent"] ?: 0
                    val failed = stats.counts["failed"] ?: 0
                    val replied = stats.counts["replied"] ?: 0
                    val converted = stats.counts["converted"] ?: 0
                    val total = (sent + failed).coerceAtLeast(1)
                    val deliveryPct = (sent * 100 / total)

                    StatsColumn(label = "Sent", value = sent.toString())
                    StatsColumn(label = "Failed", value = failed.toString())
                    StatsColumn(label = "Delivery", value = "$deliveryPct%")
                    StatsColumn(label = "Replied", value = replied.toString())
                    StatsColumn(label = "Converted", value = converted.toString())
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Total sent (all-time): ${stats.campaign.sentCount}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                stats.campaign.lastRunAt?.let { lastRun ->
                    Text(
                        text = "Last run: $lastRun",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Text(
                text = "Note: open/click tracking requires pixel/link instrumentation (not yet implemented server-side).",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(8.dp))
            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = BrandCream,
                    contentColor = Color.Black,
                ),
            ) { Text("Close") }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun StatsColumn(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = BrandCream,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
