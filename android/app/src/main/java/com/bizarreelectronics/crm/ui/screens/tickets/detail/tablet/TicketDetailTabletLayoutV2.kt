package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
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
 * Tablet (sw >= 600 dp) ticket-detail layout — phase T-C1 stub.
 *
 * This is the entry point for the tablet redesign tracked at
 * `~/.claude/plans/tablet-ticket-detail-redesign.md`. The current
 * implementation is a transparent pass-through that delegates to a
 * caller-supplied [content] lambda — typically the existing
 * `TicketDetailContent` from `TicketDetailScreen.kt`. Subsequent
 * commits (T-C2 through T-C10) will replace [content] with the new
 * 2-pane scaffold from `mockups/android-tablet-ticket-detail.html`.
 *
 * Phones (sw < 600 dp) MUST NOT call this composable — gate at the
 * call site with `isCompactWidth()` from `util/WindowSize.kt`.
 *
 * The parameter list intentionally mirrors `TicketDetailContent` so
 * each future phase can swap one card or pane at a time without
 * touching the call-site signature. Once the redesign is complete the
 * `content` lambda will be removed and the body composed inline here.
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
    @Suppress("UNUSED_PARAMETER") statuses: List<TicketStatusItem> = emptyList(),
    @Suppress("UNUSED_PARAMETER") payments: List<PaymentSummary> = emptyList(),
    @Suppress("UNUSED_PARAMETER") employees: List<EmployeeListItem> = emptyList(),
    @Suppress("UNUSED_PARAMETER") isActionInProgress: Boolean = false,
    @Suppress("UNUSED_PARAMETER") isBenchTimerRunning: Boolean = false,
    @Suppress("UNUSED_PARAMETER") reduceMotion: Boolean = false,
    @Suppress("UNUSED_PARAMETER") padding: PaddingValues,
    @Suppress("UNUSED_PARAMETER") onNavigateToCustomer: (Long) -> Unit,
    @Suppress("UNUSED_PARAMETER") onEditDevice: (Long) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onAddPhotos: ((ticketId: Long, deviceId: Long) -> Unit)? = null,
    @Suppress("UNUSED_PARAMETER") serverUrl: String = "",
    @Suppress("UNUSED_PARAMETER") onStatusSelected: (Long) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onAddNote: (String) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onNavigateToSms: ((String) -> Unit)? = null,
    @Suppress("UNUSED_PARAMETER") onDeletePhoto: (Long) -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onBenchStart: () -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onBenchStop: () -> Unit = {},
    @Suppress("UNUSED_PARAMETER") modifier: Modifier = Modifier,
    /**
     * Pass-through slot — invoked verbatim during the T-C1 stub phase
     * so the current `TicketDetailContent` + `TicketRelatedRail` Row
     * keeps rendering on tablet without behavioural change. Each
     * subsequent phase shrinks what the slot is responsible for until
     * it is removed entirely in T-C9.
     */
    content: @Composable () -> Unit,
) {
    content()
}
