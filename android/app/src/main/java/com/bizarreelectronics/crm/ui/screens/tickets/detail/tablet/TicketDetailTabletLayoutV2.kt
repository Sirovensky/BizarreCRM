package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.PaymentSummary
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketHistory
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.data.remote.dto.TicketPhoto
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem

/**
 * Tablet (sw >= 600 dp) ticket-detail layout — phase T-C2.
 *
 * Adds the cream Status pill in a tablet-styled top app bar plus the
 * `ModalBottomSheet` status picker (Option B). The body is still the
 * pass-through `content` slot, so subsequent phases (T-C3 onward)
 * replace the body without touching the top-bar surface.
 *
 * Phones (sw < 600 dp) MUST NOT call this composable — gate at the
 * call site with `isCompactWidth()` from `util/WindowSize.kt`.
 *
 * Tablet redesign plan: `~/.claude/plans/tablet-ticket-detail-redesign.md`.
 *
 * @param ticket the loaded ticket entity (kept for future cards).
 * @param ticketId route param id (kept for future cards).
 * @param sharedTransitionScope shared-element scope (kept for future).
 * @param animatedContentScope animated content scope (kept for future).
 * @param ticketDetail full DTO with customer + payments (kept for future).
 * @param devices ticket devices list (kept for future cards).
 * @param notes notes list (kept for future timeline).
 * @param history history list (kept for future timeline).
 * @param photos photos list (kept for future cards).
 * @param statuses available next statuses; populates [StatusPickerSheet].
 * @param payments payments list (kept for future quote card).
 * @param employees employees list (kept for future assignment card).
 * @param isActionInProgress disable interactive surfaces while server
 *   request is in flight.
 * @param isBenchTimerRunning bench-timer state (kept for future card).
 * @param reduceMotion respects accessibility motion preferences.
 * @param padding parent scaffold inset.
 * @param onBack back-arrow handler.
 * @param ticketTitle short id text shown next to the back arrow.
 * @param currentStatusName status name displayed on the cream pill.
 * @param currentStatusId id of the active status; current row in the
 *   sheet shows a "current" badge.
 * @param onStatusSelected fires with the picked status id; the host
 *   routes through the existing `requestStatusChangeWithNotify` flow.
 * @param topBarActions trailing action slot for the top bar — host
 *   passes the same `Pin + Print + overflow ⋮` row it uses on the
 *   phone path so behaviour parity is preserved.
 * @param onNavigateToCustomer (kept for future cards).
 * @param onEditDevice (kept for future cards).
 * @param onAddPhotos (kept for future cards).
 * @param serverUrl (kept for future cards).
 * @param onAddNote (kept for future compose bar).
 * @param onNavigateToSms (kept for future compose bar).
 * @param onDeletePhoto (kept for future cards).
 * @param onBenchStart (kept for future card).
 * @param onBenchStop (kept for future card).
 * @param modifier root modifier.
 * @param content pass-through slot — current call site supplies the
 *   existing `Row { TicketDetailContent + TicketRelatedRail }` block.
 *   Phases T-C3 onward shrink what this lambda owns until it disappears.
 */
@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
internal fun TicketDetailTabletLayoutV2(
    @Suppress("UNUSED_PARAMETER") ticket: TicketEntity,
    @Suppress("UNUSED_PARAMETER") ticketId: Long,
    @Suppress("UNUSED_PARAMETER") sharedTransitionScope: SharedTransitionScope,
    @Suppress("UNUSED_PARAMETER") animatedContentScope: AnimatedContentScope,
    @Suppress("UNUSED_PARAMETER") ticketDetail: TicketDetail?,
    @Suppress("UNUSED_PARAMETER") devices: List<TicketDevice>,
    @Suppress("UNUSED_PARAMETER") notes: List<TicketNote>,
    @Suppress("UNUSED_PARAMETER") history: List<TicketHistory>,
    @Suppress("UNUSED_PARAMETER") photos: List<TicketPhoto>,
    statuses: List<TicketStatusItem> = emptyList(),
    @Suppress("UNUSED_PARAMETER") payments: List<PaymentSummary> = emptyList(),
    @Suppress("UNUSED_PARAMETER") employees: List<EmployeeListItem> = emptyList(),
    @Suppress("UNUSED_PARAMETER") isActionInProgress: Boolean = false,
    @Suppress("UNUSED_PARAMETER") isBenchTimerRunning: Boolean = false,
    @Suppress("UNUSED_PARAMETER") reduceMotion: Boolean = false,
    @Suppress("UNUSED_PARAMETER") padding: PaddingValues,
    onBack: () -> Unit,
    ticketTitle: String,
    currentStatusName: String,
    currentStatusId: Long?,
    onStatusSelected: (Long) -> Unit,
    topBarActions: @Composable RowScope.() -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onNavigateToCustomer: (Long) -> Unit,
    @Suppress("UNUSED_PARAMETER") onEditDevice: (Long) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onAddPhotos: ((ticketId: Long, deviceId: Long) -> Unit)? = null,
    @Suppress("UNUSED_PARAMETER") serverUrl: String = "",
    @Suppress("UNUSED_PARAMETER") onAddNote: (String) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onNavigateToSms: ((String) -> Unit)? = null,
    @Suppress("UNUSED_PARAMETER") onDeletePhoto: (Long) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onBenchStart: () -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onBenchStop: () -> Unit = {},
    @Suppress("UNUSED_PARAMETER") modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    var showStatusSheet by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {
        TabletTopAppBar(
            onBack = onBack,
            ticketTitle = ticketTitle,
            currentStatusName = currentStatusName,
            onStatusPillClick = { showStatusSheet = true },
            actions = topBarActions,
        )
        content()
    }

    if (showStatusSheet) {
        StatusPickerSheet(
            currentStatusId = currentStatusId,
            statuses = statuses,
            onStatusSelected = { id ->
                onStatusSelected(id)
                showStatusSheet = false
            },
            onDismiss = { showStatusSheet = false },
        )
    }
}
