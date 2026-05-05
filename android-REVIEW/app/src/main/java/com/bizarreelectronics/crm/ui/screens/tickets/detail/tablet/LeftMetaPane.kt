package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketPhoto
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.BenchTimerCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.CustomerCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.DeviceCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.PhotosCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.QuoteAddRow
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.QuoteCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.data.QuoteSuggestion

/**
 * Left meta pane for the tablet ticket-detail layout.
 *
 * Renders a vertically-scrolling stack of meta cards. T-C4 wires
 * Device + Customer; T-C5 adds Quote; T-C6 the typeahead add-row;
 * T-C7 Photos + Bench Timer. Until each future card lands, a
 * `[CardPlaceholder]` keeps the rhythm so the pane doesn't look
 * empty and so the user can see at a glance which slices are still
 * to come.
 *
 * Lays inside a `Box(weight = 0.38f)` from `TicketDetailTabletLayoutV2`.
 *
 * @param device first ticket device (mockup currently shows one
 *   primary device per ticket; multi-device support layers later).
 * @param customer customer DTO from `state.ticketDetail`.
 * @param fallbackCustomerName from cached ticket entity for the
 *   loading window before [customer] arrives.
 * @param fallbackCustomerPhone from cached ticket entity.
 * @param onCustomerClick host opens customer detail.
 * @param onCall host triggers dialer (null hides the icon).
 * @param onSms host opens SMS thread (null hides the icon).
 * @param onEditDevice host opens the device edit screen.
 */
@Composable
internal fun LeftMetaPane(
    device: TicketDevice?,
    customer: CustomerListItem?,
    fallbackCustomerName: String?,
    fallbackCustomerPhone: String?,
    ticketDetail: TicketDetail?,
    devices: List<TicketDevice>,
    photos: List<TicketPhoto>,
    serverUrl: String,
    isBenchTimerRunning: Boolean,
    techName: String?,
    onCustomerClick: (() -> Unit)? = null,
    onCall: (() -> Unit)? = null,
    onSms: (() -> Unit)? = null,
    onEditDevice: () -> Unit = {},
    onCheckout: ((dueAmount: Double) -> Unit)? = null,
    onAddPhoto: (() -> Unit)? = null,
    onOpenPhoto: ((photoId: Long) -> Unit)? = null,
    onBenchStart: () -> Unit = {},
    onBenchStop: () -> Unit = {},
    // T-C6 — Quote add-row typeahead.
    quoteSuggestions: List<QuoteSuggestion> = emptyList(),
    onQuoteQueryChange: (String) -> Unit = {},
    onQuoteSuggestionPick: (QuoteSuggestion) -> Unit = {},
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            DeviceCard(
                device = device,
                onEdit = onEditDevice,
            )
        }
        item {
            CustomerCard(
                customer = customer,
                fallbackName = fallbackCustomerName,
                fallbackPhone = fallbackCustomerPhone,
                onCardClick = onCustomerClick,
                onCall = onCall,
                onSms = onSms,
            )
        }
        item {
            QuoteCard(
                ticketDetail = ticketDetail,
                devices = devices,
                onCheckout = onCheckout,
            )
        }
        item {
            QuoteAddRow(
                deviceId = device?.id,
                suggestions = quoteSuggestions,
                onQueryChange = onQuoteQueryChange,
                onPick = onQuoteSuggestionPick,
            )
        }
        item {
            PhotosCard(
                photos = photos,
                serverUrl = serverUrl,
                onOpenPhoto = onOpenPhoto,
                onAddPhoto = onAddPhoto,
            )
        }
        item {
            BenchTimerCard(
                isRunning = isBenchTimerRunning,
                techName = techName,
                onStart = onBenchStart,
                onStop = onBenchStop,
            )
        }
    }
}
