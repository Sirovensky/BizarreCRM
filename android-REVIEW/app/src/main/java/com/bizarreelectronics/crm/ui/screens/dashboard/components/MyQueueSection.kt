package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Message
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgency
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgencyChip

/**
 * §3.4 L519–L526 — My Queue section for the Dashboard.
 *
 * Renders a section heading ("My Queue") + a list of [MyQueueTicket] rows.
 * Each row shows ticket id, customer name, device, time-since-opened, and
 * an urgency chip. Tap → ticket detail; long-press → context menu
 * {Assign, SMS, Call, Mark done}.
 *
 * Visibility is controlled by the caller: render this composable only when
 * [AppPreferences.dashboardShowMyQueue] is true AND the assignment feature is
 * enabled. An empty-state message is shown when [tickets] is empty.
 *
 * @param tickets        Queue items from the ViewModel.
 * @param onViewAll      "View All" button tap.
 * @param onTicketClick  Tap row — navigate to ticket detail.
 * @param onAssign       Long-press menu: Assign action.
 * @param onSms          Long-press menu: SMS action.
 * @param onCall         Long-press menu: Call action.
 * @param onMarkDone     Long-press menu: Mark done action.
 * @param modifier       Outer modifier.
 */
@Composable
fun MyQueueSection(
    tickets: List<MyQueueTicket>,
    onViewAll: () -> Unit,
    onTicketClick: (id: Long) -> Unit,
    onAssign: (id: Long) -> Unit = {},
    onSms: (id: Long) -> Unit = {},
    onCall: (id: Long) -> Unit = {},
    onMarkDone: (id: Long) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Section header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "My Queue",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { heading() },
            )
            TextButton(onClick = onViewAll) {
                Text("View All")
            }
        }

        if (tickets.isEmpty()) {
            MyQueueEmptyState()
        } else {
            tickets.forEach { ticket ->
                MyQueueTicketRow(
                    ticket = ticket,
                    onClick = { onTicketClick(ticket.id) },
                    onAssign = { onAssign(ticket.id) },
                    onSms = { onSms(ticket.id) },
                    onCall = { onCall(ticket.id) },
                    onMarkDone = { onMarkDone(ticket.id) },
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/**
 * §3.4 — Richer My Queue ticket model that includes device, time-since-opened,
 * and derived urgency for display purposes. Mapped from [TicketSummary] in the
 * ViewModel (or directly from the DB query).
 */
data class MyQueueTicket(
    val id: Long,
    val orderId: String,
    val customerName: String,
    /** Human-readable device description (e.g. "iPhone 14 Pro – Cracked Screen"). */
    val device: String,
    /** Relative time string (e.g. "3h ago", "2d ago"). Pre-formatted by the VM. */
    val timeSinceOpened: String,
    val urgency: TicketUrgency,
    val statusName: String,
)

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

@Composable
private fun MyQueueEmptyState() {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "Your queue is clear"
            },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Default.ConfirmationNumber,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSecondaryContainer,
            )
            Text(
                text = "Your queue is clear \uD83C\uDF89",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSecondaryContainer,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Queue row with long-press context menu
// ---------------------------------------------------------------------------

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MyQueueTicketRow(
    ticket: MyQueueTicket,
    onClick: () -> Unit,
    onAssign: () -> Unit,
    onSms: () -> Unit,
    onCall: () -> Unit,
    onMarkDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var menuExpanded by remember { mutableStateOf(false) }

    Box(modifier = modifier.fillMaxWidth()) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 48.dp)
                .semantics(mergeDescendants = true) {
                    contentDescription = buildString {
                        append("Ticket ${ticket.orderId}, ${ticket.customerName}")
                        if (ticket.device.isNotBlank()) append(", ${ticket.device}")
                        append(", opened ${ticket.timeSinceOpened}")
                        append(", urgency: ${ticket.urgency.label}")
                        append(". Tap to open. Long-press for more options.")
                    }
                    role = Role.Button
                }
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outline,
                    shape = MaterialTheme.shapes.medium,
                )
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = { menuExpanded = true },
                ),
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface,
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        ) {
            Row(
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = ticket.orderId,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        TicketUrgencyChip(urgency = ticket.urgency)
                    }
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = ticket.customerName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (ticket.device.isNotBlank()) {
                        Text(
                            text = ticket.device,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        text = ticket.timeSinceOpened,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f),
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
                BrandStatusBadge(
                    label = ticket.statusName,
                    status = ticket.statusName,
                )
            }
        }

        // Context menu (long-press)
        DropdownMenu(
            expanded = menuExpanded,
            onDismissRequest = { menuExpanded = false },
        ) {
            DropdownMenuItem(
                text = { Text("Assign") },
                leadingIcon = {
                    Icon(Icons.Default.Group, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onAssign()
                },
            )
            DropdownMenuItem(
                text = { Text("SMS") },
                leadingIcon = {
                    Icon(Icons.Default.Message, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onSms()
                },
            )
            DropdownMenuItem(
                text = { Text("Call") },
                leadingIcon = {
                    Icon(Icons.Default.Call, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onCall()
                },
            )
            DropdownMenuItem(
                text = { Text("Mark done") },
                leadingIcon = {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onMarkDone()
                },
            )
        }
    }
}
