package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.CustomerCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.DeviceCard
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards.QuoteCard

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
    onCustomerClick: (() -> Unit)? = null,
    onCall: (() -> Unit)? = null,
    onSms: (() -> Unit)? = null,
    onEditDevice: () -> Unit = {},
    onCheckout: ((dueAmount: Double) -> Unit)? = null,
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
        items(BUILD_OUT_PLACEHOLDERS) { placeholder ->
            CardPlaceholder(label = placeholder)
        }
    }
}

/** Build-out placeholders shown until each phase lands. */
private val BUILD_OUT_PLACEHOLDERS: List<String> = listOf(
    "Quote add-row typeahead · lands in T-C6",
    "Photos · lands in T-C7",
    "Bench Timer · lands in T-C7",
)

@Composable
private fun CardPlaceholder(label: String) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        modifier = Modifier.fillMaxSize(),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(14.dp),
        )
    }
}
