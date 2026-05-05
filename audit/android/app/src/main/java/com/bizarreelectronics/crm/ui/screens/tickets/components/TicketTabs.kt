@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.dto.PaymentSummary
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketHistory
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.toCentsOrZero

private val TABS = listOf("Actions", "Devices", "Notes", "Payments")

/**
 * Four-tab layout for the ticket detail screen.
 *
 * Tabs: Actions / Devices / Notes / Payments. Tab selection state survives
 * rotation via [rememberSaveable]. Animated tab transitions respect
 * ReduceMotion — when [reduceMotion] is true the crossfade duration is 0ms.
 *
 * @param ticket          Room entity for money + status fields.
 * @param ticketDetail    API detail (nullable — may not be loaded yet).
 * @param devices         Device list from API.
 * @param notes           Note list from API.
 * @param history         Timeline events from API.
 * @param payments        Payment summaries for the Payments tab.
 * @param statuses        Available statuses for the status picker in Actions tab.
 * @param isActionInProgress true while a VM action is pending.
 * @param reduceMotion    when true, tab transitions skip animation.
 * @param onStatusSelected callback to VM.changeStatus(id).
 * @param onAddNote       callback to VM.addNote(text) — type already encoded by caller.
 * @param onEditDevice    route into device edit screen.
 * @param onNavigateToSms optional in-app SMS callback.
 */
@Composable
fun TicketDetailTabs(
    ticket: TicketEntity,
    ticketDetail: TicketDetail?,
    devices: List<TicketDevice>,
    notes: List<TicketNote>,
    history: List<TicketHistory>,
    payments: List<PaymentSummary>,
    statuses: List<TicketStatusItem>,
    isActionInProgress: Boolean,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
    employees: List<EmployeeListItem> = emptyList(),
    onStatusSelected: (Long) -> Unit = {},
    onAddNote: (String) -> Unit = {},
    onEditDevice: (Long) -> Unit = {},
    onNavigateToSms: ((String) -> Unit)? = null,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    Column(modifier = modifier.fillMaxWidth()) {
        PrimaryTabRow(selectedTabIndex = selectedTab) {
            TABS.forEachIndexed { index, title ->
                Tab(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    text = { Text(title) },
                )
            }
        }

        val animDuration = if (reduceMotion) 0 else 200

        AnimatedContent(
            targetState = selectedTab,
            transitionSpec = {
                fadeIn(tween(animDuration)) togetherWith fadeOut(tween(animDuration))
            },
            label = "ticket_tab_content",
        ) { tab ->
            when (tab) {
                0 -> ActionsTab(
                    ticket = ticket,
                    ticketDetail = ticketDetail,
                    statuses = statuses,
                    isActionInProgress = isActionInProgress,
                    onStatusSelected = onStatusSelected,
                    onNavigateToSms = onNavigateToSms,
                )
                1 -> DevicesTab(
                    devices = devices,
                    onEditDevice = onEditDevice,
                )
                2 -> TicketNotesTab(
                    notes = notes,
                    isSubmitting = isActionInProgress,
                    employees = employees,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    onSubmit = { text, _, _, _ -> onAddNote(text) },
                )
                3 -> PaymentsTab(
                    ticket = ticket,
                    payments = payments,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Actions tab
// ---------------------------------------------------------------------------

@Composable
private fun ActionsTab(
    ticket: TicketEntity,
    ticketDetail: TicketDetail?,
    statuses: List<TicketStatusItem>,
    isActionInProgress: Boolean,
    onStatusSelected: (Long) -> Unit,
    onNavigateToSms: ((String) -> Unit)?,
) {
    val customer = ticketDetail?.customer
    val phone = customer?.mobile ?: customer?.phone ?: ticket.customerPhone
    val email = customer?.email

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Customer quick actions
        TicketCustomerActions(
            phone = phone,
            email = email,
            onNavigateToSms = onNavigateToSms,
        )

        // Status picker
        TicketStatusPickerRow(
            currentStatusId = ticket.statusId,
            currentStatusName = ticket.statusName,
            currentStatusColor = ticket.statusColor,
            statuses = statuses,
            enabled = !isActionInProgress,
            onStatusSelected = onStatusSelected,
        )

        // Warranty/SLA banner (if device has warranty data)
        val warrantyDevice = ticketDetail?.devices?.firstOrNull { it.warrantyDays != null && it.warrantyDays > 0 }
        if (warrantyDevice != null) {
            WarrantySlaBanner(
                dueOn = warrantyDevice.dueOn,
                warrantyDays = warrantyDevice.warrantyDays ?: 0,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Devices tab
// ---------------------------------------------------------------------------

@Composable
private fun DevicesTab(
    devices: List<TicketDevice>,
    onEditDevice: (Long) -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (devices.isEmpty()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "No devices",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(devices, key = { it.id }) { device ->
                DeviceCard(device = device, onEdit = { onEditDevice(device.id) })
            }
        }
    }
}

@Composable
private fun DeviceCard(device: TicketDevice, onEdit: () -> Unit) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    device.name ?: device.deviceName ?: "Device",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onEdit, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Default.Edit,
                        contentDescription = "Edit device",
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            // Pre-conditions intake checklist
            val conditions = device.preConditionsList
            if (conditions.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Intake conditions:",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                conditions.forEach { condition ->
                    Text(
                        "  \u2022 $condition",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Services (from service map)
            val serviceName = device.service?.get("service_name") as? String
                ?: device.service?.get("name") as? String
            if (!serviceName.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Service:",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(serviceName, style = MaterialTheme.typography.bodySmall)
                    if (device.price != null && device.price > 0) {
                        Text(
                            "$${String.format("%.2f", device.total ?: device.price)}",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }

            // Parts list with quantity + price columns
            val parts = device.parts ?: emptyList()
            if (parts.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Parts:",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                parts.forEach { part ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "${part.name ?: "Part"} x${part.quantity ?: 1}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f),
                        )
                        if (part.price != null && part.price > 0) {
                            Text(
                                "$${String.format("%.2f", part.total ?: (part.price * (part.quantity ?: 1)))}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // Device metadata
            if (!device.imei.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(4.dp))
                Text("IMEI: ${device.imei}", style = MaterialTheme.typography.bodySmall)
            }
            if (!device.serial.isNullOrBlank()) {
                Text("Serial: ${device.serial}", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Payments tab
// ---------------------------------------------------------------------------

@Composable
private fun PaymentsTab(
    ticket: TicketEntity,
    payments: List<PaymentSummary>,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            TicketTotalsPanel(ticket = ticket, payments = payments)
        }
        if (payments.isEmpty()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "No payments recorded.",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(payments, key = { it.id }) { payment ->
                PaymentRow(payment)
            }
        }
    }
}

@Composable
private fun PaymentRow(payment: PaymentSummary) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    payment.method ?: "Payment",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    payment.amount?.toCentsOrZero()?.formatAsMoney() ?: "-",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            if (!payment.paymentDate.isNullOrBlank()) {
                Text(
                    DateFormatter.formatAbsolute(payment.paymentDate),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!payment.notes.isNullOrBlank()) {
                Text(
                    payment.notes,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Warranty/SLA banner
// ---------------------------------------------------------------------------

@Composable
fun WarrantySlaBanner(
    dueOn: String?,
    warrantyDays: Int,
    modifier: Modifier = Modifier,
) {
    val daysLeft = daysUntil(dueOn)
    val (containerColor, contentColor, label) = when {
        daysLeft != null && daysLeft < 0 ->
            Triple(
                MaterialTheme.colorScheme.errorContainer,
                MaterialTheme.colorScheme.onErrorContainer,
                "Warranty overdue by ${-daysLeft} day(s)",
            )
        daysLeft != null && daysLeft <= 3 ->
            Triple(
                MaterialTheme.colorScheme.tertiaryContainer,
                MaterialTheme.colorScheme.onTertiaryContainer,
                "Warranty expires in $daysLeft day(s)",
            )
        else ->
            Triple(
                MaterialTheme.colorScheme.secondaryContainer,
                MaterialTheme.colorScheme.onSecondaryContainer,
                "Warranty: $warrantyDays day(s)${if (dueOn != null) " (due ${DateFormatter.formatAbsolute(dueOn)})" else ""}",
            )
    }

    Box(
        modifier = modifier
            .fillMaxWidth(),
    ) {
        androidx.compose.material3.Surface(
            color = containerColor,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                label,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
                color = contentColor,
            )
        }
    }
}

/** Returns number of days from today to [dateStr] (negative = past). Null if unparseable. */
private fun daysUntil(dateStr: String?): Long? {
    if (dateStr.isNullOrBlank()) return null
    return runCatching {
        val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        val due = sdf.parse(dateStr) ?: return null
        val today = java.util.Date()
        val diffMs = due.time - today.time
        diffMs / (1000L * 60 * 60 * 24)
    }.getOrNull()
}

// ---------------------------------------------------------------------------
// Status picker row (chip strip + ModalBottomSheet)
// ---------------------------------------------------------------------------

/**
 * Displays the current status as a tappable chip. Tapping opens a [ModalBottomSheet]
 * listing all available statuses with the current one highlighted.
 */
@Composable
fun TicketStatusPickerRow(
    currentStatusId: Long?,
    currentStatusName: String?,
    currentStatusColor: String?,
    statuses: List<com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem>,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onStatusSelected: (Long) -> Unit,
) {
    var showSheet by rememberSaveable { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            "Status",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(4.dp))
        androidx.compose.material3.Surface(
            onClick = { if (enabled) showSheet = true },
            enabled = enabled,
            shape = MaterialTheme.shapes.small,
            color = runCatching {
                androidx.compose.ui.graphics.Color(
                    android.graphics.Color.parseColor(currentStatusColor ?: "#6b7280")
                ).copy(alpha = 0.18f)
            }.getOrDefault(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Text(
                text = currentStatusName ?: "Unknown",
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
        }
    }

    if (showSheet) {
        androidx.compose.material3.ModalBottomSheet(
            onDismissRequest = { showSheet = false },
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 24.dp),
            ) {
                Text(
                    "Change Status",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                statuses.forEach { status ->
                    val isCurrent = status.id == currentStatusId
                    androidx.compose.material3.ListItem(
                        headlineContent = { Text(status.name) },
                        leadingContent = {
                            Box(
                                modifier = Modifier
                                    .size(12.dp)
                                    .then(
                                        Modifier.background(
                                            runCatching {
                                                androidx.compose.ui.graphics.Color(
                                                    android.graphics.Color.parseColor(status.color ?: "#6b7280")
                                                )
                                            }.getOrDefault(MaterialTheme.colorScheme.primary),
                                            CircleShape,
                                        )
                                    ),
                            )
                        },
                        trailingContent = if (isCurrent) ({
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }) else null,
                        modifier = Modifier.clickable(enabled = !isCurrent) {
                            showSheet = false
                            onStatusSelected(status.id)
                        },
                    )
                }
            }
        }
    }
}

