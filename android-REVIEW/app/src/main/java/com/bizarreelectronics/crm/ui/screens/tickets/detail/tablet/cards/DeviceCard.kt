package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice

/**
 * Tablet ticket-detail Device card.
 *
 * Collapsed: device title (manufacturer + name) + repair subtitle on
 * one row, with an edit pencil and a rotating chevron at the right.
 * Expanded: pills row (color / category, when present) plus kv-rows
 * showing Serial / IMEI / Passcode-on-file. First seen / Last seen
 * rows are gated on `priorTicketCount > 0` (wired in T-C4b once VM
 * exposes `deviceHistorySummary`); for now they render only when
 * [firstSeen] / [lastSeen] are non-null.
 *
 * Decision: card-internal expand state via [remember]. Survives
 * recomposition but resets on configuration change — fine for v1
 * since the user-set expand position isn't critical persistence.
 *
 * @param device first ticket device, or null when the ticket is
 *   still loading (collapsed shell renders empty title).
 * @param firstSeen optional human-readable first-seen string ("Jan
 *   2024"). Null = row hidden.
 * @param lastSeen optional human-readable last-seen string ("12 days
 *   ago · T-1198"). Null = row hidden.
 * @param onEdit fires when the edit pencil is tapped — host opens
 *   the ticket-edit screen scoped to this device id.
 */
@Composable
internal fun DeviceCard(
    device: TicketDevice?,
    firstSeen: String? = null,
    lastSeen: String? = null,
    onEdit: () -> Unit = {},
) {
    var expanded by remember { mutableStateOf(false) }
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        animationSpec = tween(220),
        label = "device_chevron",
    )

    val title = remember(device) {
        listOfNotNull(device?.manufacturerName, device?.name?.takeIf { it.isNotBlank() })
            .joinToString(" ")
            .ifBlank { device?.deviceName ?: "Device" }
    }
    val subtitle = remember(device) {
        device?.category?.takeIf { it.isNotBlank() }
            ?: device?.service?.get("name")?.toString()?.takeIf { it.isNotBlank() }
            ?: "Repair"
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            // Section label
            Text(
                "Device",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Header row: title + subtitle | edit + chevron
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(
                    onClick = onEdit,
                    modifier = Modifier
                        .size(36.dp)
                        .semantics { contentDescription = "Edit device" },
                ) {
                    Icon(Icons.Default.Edit, contentDescription = null)
                }
                IconButton(
                    onClick = { expanded = !expanded },
                    modifier = Modifier
                        .size(36.dp)
                        .semantics {
                            contentDescription = if (expanded) "Collapse device details"
                            else "Expand device details"
                        },
                ) {
                    Icon(
                        Icons.Default.ExpandMore,
                        contentDescription = null,
                        modifier = Modifier.rotate(chevronRotation),
                    )
                }
            }

            // Expanded body — pills + kv-rows.
            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(top = 6.dp)) {
                    // Pills row — color, category, etc.
                    val pills = remember(device) {
                        listOfNotNull(
                            device?.color?.takeIf { it.isNotBlank() },
                            device?.category?.takeIf { it.isNotBlank() },
                        )
                    }
                    if (pills.isNotEmpty()) {
                        Row(
                            modifier = Modifier.padding(bottom = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            pills.forEach { pill -> InfoPill(pill) }
                        }
                    }

                    // KV rows — Serial / IMEI / Passcode / First seen / Last seen.
                    HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
                    Column(
                        modifier = Modifier.padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        device?.serial?.takeIf { it.isNotBlank() }?.let { KvRow("Serial", it) }
                        device?.imei?.takeIf { it.isNotBlank() }?.let { KvRow("IMEI", it) }
                        device?.securityCode?.takeIf { it.isNotBlank() }?.let {
                            KvRow("Passcode on file", "●●●● (encrypted)")
                        }
                        // First/Last seen render only when host derives a value
                        // (priorTicketCount > 0 — see DeviceCard.kdoc).
                        firstSeen?.let { KvRow("First seen", it) }
                        lastSeen?.let { KvRow("Last seen", it) }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoPill(label: String) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        shape = RoundedCornerShape(999.dp),
    ) {
        Box(modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun KvRow(key: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            key,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
