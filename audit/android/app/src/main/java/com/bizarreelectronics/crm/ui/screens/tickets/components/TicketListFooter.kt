package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Four-state footer rendered at the bottom of the ticket lazy list (plan:L635).
 *
 * States:
 * 1. **Loading**  — spinner + "Loading…" while the next page is in-flight.
 * 2. **Partial**  — "Showing N of ~M" when more pages remain on the server.
 * 3. **EndOfList** — "End of list" when [endOfPaginationReached] and network is available.
 * 4. **Offline**  — "Offline — N cached, last synced Xh ago" when the device has no
 *                   connectivity and the cache has at least one ticket.
 *
 * The composable is stateless; all state is driven by the caller (TicketListScreen).
 *
 * @param state        The current footer state to render.
 * @param modifier     Optional layout modifier.
 */
@Composable
fun TicketListFooter(
    state: TicketFooterState,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        contentAlignment = Alignment.Center,
    ) {
        when (state) {
            is TicketFooterState.Loading -> FooterLoading()
            is TicketFooterState.Partial -> FooterPartial(shown = state.shown, total = state.approximateTotal)
            is TicketFooterState.EndOfList -> FooterEndOfList()
            is TicketFooterState.Offline -> FooterOffline(
                cachedCount = state.cachedCount,
                lastSyncedHoursAgo = state.lastSyncedHoursAgo,
            )
        }
    }
}

// -----------------------------------------------------------------------
// State sealed class
// -----------------------------------------------------------------------

/**
 * Discriminated union of the four footer states.
 *
 * Callers build the correct subtype by inspecting [LazyPagingItems.loadState] and the
 * offline/cache signals from [TicketListViewModel].
 */
sealed class TicketFooterState {

    /** Next-page fetch is in-flight. */
    object Loading : TicketFooterState()

    /**
     * Cache has items but more pages remain on the server.
     * @param shown            Current number of tickets visible in the list.
     * @param approximateTotal Server-reported approximate total (null if unknown).
     */
    data class Partial(val shown: Int, val approximateTotal: Int?) : TicketFooterState()

    /** Server confirmed no more pages; device is online. */
    object EndOfList : TicketFooterState()

    /**
     * Device has no server connectivity; showing cached-only data.
     * @param cachedCount         Number of tickets in the local Room cache.
     * @param lastSyncedHoursAgo  Hours since the last successful sync (0 = very recent).
     */
    data class Offline(val cachedCount: Int, val lastSyncedHoursAgo: Long) : TicketFooterState()
}

// -----------------------------------------------------------------------
// Private sub-composables
// -----------------------------------------------------------------------

@Composable
private fun FooterLoading() {
    Row(verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(
            modifier = Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "Loading…",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun FooterPartial(shown: Int, total: Int?) {
    val label = if (total != null) {
        "Showing $shown of ~$total"
    } else {
        "Showing $shown — scroll for more"
    }
    Text(
        text = label,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun FooterEndOfList() {
    Text(
        text = "End of list",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun FooterOffline(cachedCount: Int, lastSyncedHoursAgo: Long) {
    val syncLabel = when {
        lastSyncedHoursAgo < 1L -> "recently"
        lastSyncedHoursAgo == 1L -> "1h ago"
        else -> "${lastSyncedHoursAgo}h ago"
    }
    Text(
        text = "Offline — $cachedCount cached, last synced $syncLabel",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.tertiary,
    )
}
