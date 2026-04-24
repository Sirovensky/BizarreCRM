package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.WeekFields

/** Week view: appointments grouped within the week containing [selectedDate]. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AppointmentWeekView(
    appointments: List<AppointmentItem>,
    selectedDate: LocalDate,
    isLoading: Boolean,
    error: String?,
    onAppointmentClick: (Long) -> Unit,
    onDateChange: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
) {
    val firstOfWeek = selectedDate.with(
        WeekFields.of(DayOfWeek.SUNDAY, 1).dayOfWeek(), 1,
    )
    val lastOfWeek = firstOfWeek.plusDays(6)

    val weekAppts = appointments.filter { appt ->
        val d = appt.startTime?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        d != null && !d.isBefore(firstOfWeek) && !d.isAfter(lastOfWeek)
    }.sortedBy { it.startTime }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            IconButton(onClick = { onDateChange(selectedDate.minusWeeks(1)) }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous week")
            }
            val fmt = DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT)
            Text(
                text = "${firstOfWeek.format(fmt)} – ${lastOfWeek.format(fmt)}",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            IconButton(onClick = { onDateChange(selectedDate.plusWeeks(1)) }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next week")
            }
        }

        when {
            isLoading -> BrandSkeleton(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp)
                    .padding(16.dp),
            )
            error != null -> ErrorState(message = error)
            weekAppts.isEmpty() -> EmptyState(
                title = "No appointments this week",
                subtitle = "Tap + to schedule one",
            )
            else -> {
                val grouped = weekAppts.groupBy { appt ->
                    LocalDate.parse(appt.startTime!!.take(10))
                }
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 80.dp),
                ) {
                    grouped.entries.sortedBy { it.key }.forEach { (date, dayAppts) ->
                        stickyHeader(key = "week_hdr_$date") {
                            Surface(
                                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(
                                    text = date.format(
                                        DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL),
                                    ),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                )
                            }
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
