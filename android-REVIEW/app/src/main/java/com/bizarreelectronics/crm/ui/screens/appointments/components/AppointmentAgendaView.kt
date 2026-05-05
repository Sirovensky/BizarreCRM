package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Agenda view (L1422): forward-looking LazyColumn grouped by day with sticky headers.
 * Each row shows: time + customer + type + duration. Tap → detail.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AppointmentAgendaView(
    appointments: List<AppointmentItem>,
    isLoading: Boolean,
    error: String?,
    onAppointmentClick: (Long) -> Unit,
    listState: LazyListState = rememberLazyListState(),
    modifier: Modifier = Modifier,
) {
    when {
        isLoading -> BrandSkeleton(
            modifier = Modifier
                .fillMaxWidth()
                .height(400.dp)
                .padding(16.dp),
        )
        error != null -> ErrorState(message = error)
        appointments.isEmpty() -> EmptyState(
            title = "No upcoming appointments",
            subtitle = "Tap + to schedule one",
        )
        else -> {
            val today = LocalDate.now()
            // Filter to today-and-forward; group by date
            val grouped: Map<LocalDate, List<AppointmentItem>> = appointments
                .filter { appt ->
                    val d = appt.startTime?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                    d != null && !d.isBefore(today)
                }
                .sortedBy { it.startTime }
                .groupBy { appt -> LocalDate.parse(appt.startTime!!.take(10)) }

            if (grouped.isEmpty()) {
                EmptyState(
                    title = "No upcoming appointments",
                    subtitle = "Tap + to schedule one",
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 80.dp),
                ) {
                    grouped.entries.sortedBy { it.key }.forEach { (date, dayAppts) ->
                        stickyHeader(key = "agenda_hdr_$date") {
                            AgendaDayHeader(date = date)
                        }
                        items(dayAppts, key = { it.id }) { appt ->
                            AppointmentRow(
                                appointment = appt,
                                onClick = { onAppointmentClick(appt.id) },
                            )
                            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AgendaDayHeader(date: LocalDate) {
    val today = LocalDate.now()
    val label = when (date) {
        today -> "Today — ${date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))}"
        today.plusDays(1) -> "Tomorrow — ${date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))}"
        else -> date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL))
    }
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
    }
}
