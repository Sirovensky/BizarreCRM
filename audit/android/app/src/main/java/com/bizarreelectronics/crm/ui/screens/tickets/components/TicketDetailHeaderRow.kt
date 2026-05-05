package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.ui.theme.SharedTicketElement
import com.bizarreelectronics.crm.ui.theme.sharedTicketKey
import java.time.LocalDate

/**
 * §4.2 — Ticket detail header chip row.
 *
 * Renders a horizontally scrollable row of compact chips that surfaces the most
 * actionable at-a-glance signals for a ticket:
 *
 *   1. **Status pill** — tenant-colored chip from [TicketStatePill] using
 *      [TicketEntity.statusName] + [TicketEntity.statusColor].
 *   2. **Urgency chip** — derived by [ticketUrgencyFor]; hidden when urgency is
 *      [TicketUrgency.Normal] or [TicketUrgency.Low] on a closed ticket (no signal needed).
 *   3. **Due-date chip** — shows the [TicketEntity.dueOn] date; becomes amber when
 *      due today and red when overdue; hidden when [dueOn] is null.
 *
 * This completes the `[~]` §4.2 header item: "urgency chip, …, due / assignee" that
 * were previously absent from the detail content area (status chip only existed inside
 * the TicketDetailTabs Actions tab, not in the always-visible header).
 *
 * The row is fully client-side — every value is derived from [TicketEntity] which is
 * already hydrated from Room before the screen is shown.
 *
 * §70.3 — When [sharedTransitionScope] and [animatedContentScope] are non-null, the
 * [TicketStatePill] participates in the list→detail shared-element transition via
 * [SharedTicketElement.STATUS_CHIP]. The key matches the one emitted by [TicketListRow]
 * so the framework can animate the chip seamlessly between screens.
 *
 * @param ticket                  Room entity supplying status, statusColor, statusIsClosed, dueOn.
 * @param ticketId                DB id used to build the shared-element key. Defaults to
 *                                [TicketEntity.id] — only override in edge-cases where
 *                                the nav-arg id differs from the entity id.
 * @param sharedTransitionScope   SharedTransitionScope provided by the host nav graph.
 *                                Null disables the shared-element animation (safe default
 *                                for previews, tests, and call-sites that haven't been updated).
 * @param animatedContentScope    AnimatedContentScope from the NavHost composable lambda.
 *                                Must be non-null when [sharedTransitionScope] is non-null.
 * @param modifier                Optional modifier forwarded to the outer [Row].
 */
@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
fun TicketDetailHeaderRow(
    ticket: TicketEntity,
    ticketId: Long = ticket.id,
    sharedTransitionScope: SharedTransitionScope? = null,
    animatedContentScope: AnimatedContentScope? = null,
    modifier: Modifier = Modifier,
) {
    val urgency = remember(ticket.statusName, ticket.statusIsClosed) {
        ticketUrgencyFor(ticket)
    }

    // Suppress the urgency chip for closed/low tickets — they carry no actionable signal.
    val showUrgency = urgency != TicketUrgency.Low &&
        urgency != TicketUrgency.Normal

    // Parse the due date once.
    val dueDate: LocalDate? = remember(ticket.dueOn) {
        ticket.dueOn?.takeIf { it.isNotBlank() }?.let { parseLocalDate(it) }
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 1. Status pill (always shown when statusName is available)
        // §70.3 — participates in list→detail shared-element transition when scopes are
        // provided. The sharedElement modifier is applied to the TicketStatePill Surface
        // so the entire colored pill (background + text) morphs as one unit.
        val statusName = ticket.statusName
        if (!statusName.isNullOrBlank()) {
            val pillModifier: Modifier = if (
                sharedTransitionScope != null && animatedContentScope != null
            ) {
                with(sharedTransitionScope) {
                    Modifier.sharedElement(
                        sharedContentState = rememberSharedContentState(
                            key = sharedTicketKey(ticketId, SharedTicketElement.STATUS_CHIP),
                        ),
                        animatedVisibilityScope = animatedContentScope,
                    )
                }
            } else {
                Modifier
            }
            TicketStatePill(
                statusName = statusName,
                colorHex = ticket.statusColor,
                modifier = pillModifier,
            )
        }

        // 2. Urgency chip (only for Critical / High / Medium)
        if (showUrgency) {
            TicketUrgencyChip(urgency = urgency)
        }

        // 3. Due-date chip
        if (dueDate != null) {
            DueDateChip(dueDate = dueDate)
        }
    }
}

// ─── Due-date chip ────────────────────────────────────────────────────────────

/**
 * Compact due-date chip showing a calendar icon + date string.
 *
 * Color tiers (using [LocalExtendedColors]):
 *  - **Overdue** (past today) → [ExtendedColors.errorContainer] background, red text
 *    + warning icon.
 *  - **Due today**             → [ExtendedColors.warningContainer] background, amber text
 *    + clock icon.
 *  - **Upcoming**              → [MaterialTheme.colorScheme.surfaceVariant] background,
 *    muted text + calendar icon.
 *
 * The chip emits a TalkBack [contentDescription] that reads "Due: <formatted date>" or
 * "Overdue: <formatted date>" so screen-reader users understand the urgency signal.
 */
@Composable
private fun DueDateChip(
    dueDate: LocalDate,
    modifier: Modifier = Modifier,
) {
    val today = remember { LocalDate.now() }
    val ext = LocalExtendedColors.current

    val isOverdue = dueDate.isBefore(today)
    val isDueToday = dueDate.isEqual(today)

    val containerColor = when {
        isOverdue   -> ext.errorContainer
        isDueToday  -> ext.warningContainer
        else        -> MaterialTheme.colorScheme.surfaceVariant
    }
    val contentColor = when {
        isOverdue   -> ext.error
        isDueToday  -> ext.warning
        else        -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val icon = when {
        isOverdue  -> Icons.Default.Warning
        isDueToday -> Icons.Default.AccessTime
        else       -> Icons.Default.CalendarToday
    }

    // Format as "Apr 27" (MMMd pattern) — short enough to fit on phone widths.
    val dateLabel = remember(dueDate) {
        dueDate.format(java.time.format.DateTimeFormatter.ofPattern("MMM d"))
    }

    val a11yLabel = if (isOverdue) "Overdue: $dateLabel" else "Due: $dateLabel"

    Surface(
        shape = RoundedCornerShape(50),
        color = containerColor,
        contentColor = contentColor,
        modifier = modifier.semantics { contentDescription = a11yLabel },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(12.dp),
            )
            Text(
                text = dateLabel,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = contentColor,
            )
        }
    }
}
