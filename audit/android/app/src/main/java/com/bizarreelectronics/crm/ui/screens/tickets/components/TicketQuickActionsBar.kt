package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * plan:L797-L803 — TicketQuickActionsBar
 *
 * Horizontal scrolling row of 8 quick-action chip buttons for the ticket detail screen.
 * Actions are sorted by most-recently-used frequency ([actionUsageCounts] — plan:L803),
 * then by default catalog order.
 *
 * Catalog (plan:L797):
 *   Open (link in browser), Copy ID, Share PDF, Call, SMS,
 *   Print, Mark Ready, Assign-to-me, Archive
 *
 * Note: swipe actions (plan:L799) and batch actions (plan:L802) are already shipped
 * in TicketSwipeRow and TicketBulkActionBar respectively (commits 68cadc5, 181e486).
 *
 * @param ticketId         Ticket being displayed.
 * @param hasPhone         True when customer has a phone number (gates Call/SMS chips).
 * @param isReadyState     True when "Mark Ready" should show as already done.
 * @param isArchived       True when ticket is already archived.
 * @param actionUsageCounts Map of action key → usage count for MRU sort (plan:L803).
 * @param onOpen           Open ticket in browser.
 * @param onCopyId         Copy ticket ID to clipboard.
 * @param onSharePdf       Share PDF of ticket.
 * @param onCall           Launch phone call intent.
 * @param onSms            Launch SMS intent.
 * @param onPrint          Print ticket receipt.
 * @param onMarkReady      Move ticket to Ready for Pickup.
 * @param onAssignToMe     Assign ticket to current user.
 * @param onArchive        Archive the ticket.
 */
@Composable
fun TicketQuickActionsBar(
    ticketId: Long,
    hasPhone: Boolean,
    isReadyState: Boolean,
    isArchived: Boolean,
    actionUsageCounts: Map<String, Int>,
    onOpen: () -> Unit,
    onCopyId: () -> Unit,
    onSharePdf: () -> Unit,
    onCall: () -> Unit,
    onSms: () -> Unit,
    onPrint: () -> Unit,
    onMarkReady: () -> Unit,
    onAssignToMe: () -> Unit,
    onArchive: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Catalog definition — each item has a stable key, label, enabled flag, and click handler.
    data class QuickAction(
        val key: String,
        val label: String,
        val enabled: Boolean,
        val onClick: () -> Unit,
    )

    val catalog = listOf(
        QuickAction("open", "Open", enabled = true, onOpen),
        QuickAction("copy_id", "Copy ID", enabled = true, onCopyId),
        QuickAction("share_pdf", "Share PDF", enabled = true, onSharePdf),
        QuickAction("call", "Call", enabled = hasPhone, onCall),
        QuickAction("sms", "SMS", enabled = hasPhone, onSms),
        QuickAction("print", "Print", enabled = true, onPrint),
        QuickAction("mark_ready", if (isReadyState) "Ready ✓" else "Mark Ready", enabled = !isReadyState, onMarkReady),
        QuickAction("assign_me", "Assign to me", enabled = true, onAssignToMe),
        QuickAction("archive", if (isArchived) "Archived" else "Archive", enabled = !isArchived, onArchive),
    )

    // plan:L803 — sort by MRU count descending, stable secondary order from catalog index
    val sorted = remember(actionUsageCounts) {
        catalog.sortedByDescending { action -> actionUsageCounts[action.key] ?: 0 }
    }

    Surface(
        tonalElevation = 1.dp,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            sorted.forEach { action ->
                FilterChip(
                    selected = false,
                    onClick = {
                        if (action.enabled) action.onClick()
                    },
                    label = {
                        Text(
                            action.label,
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                    enabled = action.enabled,
                )
            }
        }
    }
}
