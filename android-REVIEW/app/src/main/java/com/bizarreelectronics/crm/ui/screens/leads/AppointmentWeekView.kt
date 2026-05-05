package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.AppointmentDetail
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

// ─── Formatters ──────────────────────────────────────────────────────────────

/** ISO date string → LocalDate, returns null on parse failure. */
private fun String.toLocalDateOrNull(): LocalDate? = try {
    LocalDate.parse(this.take(10))
} catch (_: Exception) {
    null
}

/** "HH:mm" from an ISO-8601 start_time string like "2026-04-23T09:30:00". */
private fun isoToHhmm(iso: String?): String {
    if (iso.isNullOrBlank() || iso.length < 16) return "?"
    return iso.substring(11, 16)
}

// ─── Header range label ───────────────────────────────────────────────────────

private val MONTH_DAY_FMT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d", Locale.getDefault())

private val FULL_DATE_FMT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("EEE, MMM d", Locale.getDefault())

private fun weekRangeLabel(weekStart: LocalDate): String {
    val weekEnd = weekStart.plusDays(6)
    return if (weekStart.month == weekEnd.month) {
        // Same month: "Mon Apr 20 – Sun Apr 26"
        "${MONTH_DAY_FMT.format(weekStart)} – ${MONTH_DAY_FMT.format(weekEnd)}, ${weekEnd.year}"
    } else {
        // Month boundary: "Mon Mar 30 – Sun Apr 5, 2026"
        "${MONTH_DAY_FMT.format(weekStart)} – ${MONTH_DAY_FMT.format(weekEnd)}, ${weekEnd.year}"
    }
}

// ─── Week view composable ─────────────────────────────────────────────────────

/**
 * Week view of appointments — 7 columns (Mon–Sun).
 *
 * Each column shows the day name + date in the sub-header and stacks
 * appointment cards ordered by start time. The user scrolls horizontally
 * on compact phones; all 7 columns are shown side-by-side when the available
 * width is 600 dp or more (tablet / landscape).
 *
 * Read-only this wave. Tapping a card navigates to detail via [onAppointmentClick].
 * Week navigation: ← / → arrows in the header select previous/next week.
 *
 * Accessibility:
 *   - Each column has contentDescription "<dayname> <date>, N appointments".
 *   - Each card has contentDescription "Appointment at TIME with CUSTOMER for SERVICE".
 *   - Today's column is highlighted with primaryContainer background.
 *   - Prev/Next icons have explicit contentDescription labels.
 */
@Composable
fun AppointmentWeekView(
    appointments: List<AppointmentDetail>,
    weekStart: LocalDate,
    onWeekPrev: () -> Unit,
    onWeekNext: () -> Unit,
    onAppointmentClick: (id: Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val today = LocalDate.now()

    // Derive the 7 days of the week (immutable list).
    val days: List<LocalDate> = (0..6).map { weekStart.plusDays(it.toLong()) }

    // Group appointments by their ISO date prefix (first 10 chars = YYYY-MM-DD).
    // groupBy returns a new map — immutable, no mutation.
    val byDay: Map<LocalDate, List<AppointmentDetail>> = appointments
        .groupBy { appt ->
            appt.startTime?.toLocalDateOrNull() ?: LocalDate.MIN
        }

    Column(modifier = modifier) {
        // ── Week navigation header ──────────────────────────────────────────
        WeekNavHeader(
            label = weekRangeLabel(weekStart),
            onPrev = onWeekPrev,
            onNext = onWeekNext,
        )

        HorizontalDivider()

        // ── Day columns ────────────────────────────────────────────────────
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val isWide = maxWidth >= 600.dp

            if (isWide) {
                // Tablet / landscape: all 7 columns in a fixed Row — each gets equal weight.
                Row(modifier = Modifier.fillMaxSize()) {
                    days.forEach { day ->
                        DayColumn(
                            day = day,
                            isToday = day == today,
                            appointments = byDay[day] ?: emptyList(),
                            onAppointmentClick = onAppointmentClick,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                        if (day != days.last()) {
                            VerticalDivider(modifier = Modifier.fillMaxHeight())
                        }
                    }
                }
            } else {
                // Phone / compact: horizontal scroll so the user can pan across days.
                val hScroll = rememberScrollState()
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .horizontalScroll(hScroll),
                ) {
                    days.forEach { day ->
                        DayColumn(
                            day = day,
                            isToday = day == today,
                            appointments = byDay[day] ?: emptyList(),
                            onAppointmentClick = onAppointmentClick,
                            // 140 dp per column — readable but not wasteful on 360 dp screens.
                            modifier = Modifier.width(140.dp).fillMaxHeight(),
                        )
                        if (day != days.last()) {
                            VerticalDivider(modifier = Modifier.fillMaxHeight())
                        }
                    }
                }
            }
        }
    }
}

// ─── Week nav header ──────────────────────────────────────────────────────────

@Composable
private fun WeekNavHeader(
    label: String,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 4.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        IconButton(
            onClick = onPrev,
            modifier = Modifier.semantics {
                contentDescription = "Previous week"
            },
        ) {
            Icon(
                Icons.Default.ChevronLeft,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Text(
            text = label,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )

        IconButton(
            onClick = onNext,
            modifier = Modifier.semantics {
                contentDescription = "Next week"
            },
        ) {
            Icon(
                Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ─── Day column ───────────────────────────────────────────────────────────────

@Composable
private fun DayColumn(
    day: LocalDate,
    isToday: Boolean,
    appointments: List<AppointmentDetail>,
    onAppointmentClick: (id: Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    val dayName = day.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault())
    val dayNum = day.dayOfMonth
    val count = appointments.size
    val columnA11y = "$dayName ${day.month.getDisplayName(TextStyle.SHORT, Locale.getDefault())} $dayNum, $count ${if (count == 1) "appointment" else "appointments"}"

    val columnBg = if (isToday)
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.25f)
    else
        MaterialTheme.colorScheme.surface

    Column(
        modifier = modifier
            .background(columnBg)
            .semantics {
                contentDescription = columnA11y
            },
    ) {
        // Day sub-header
        Surface(
            color = if (isToday)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    dayName.uppercase(Locale.getDefault()),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isToday)
                        MaterialTheme.colorScheme.onPrimaryContainer
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    dayNum.toString(),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                    color = if (isToday)
                        MaterialTheme.colorScheme.onPrimaryContainer
                    else
                        MaterialTheme.colorScheme.onSurface,
                )
            }
        }

        HorizontalDivider()

        // Appointment cards sorted by start time (already sorted by caller, but
        // sort within the column defensively — sortedBy returns a new list, immutable).
        val sorted = appointments.sortedBy { it.startTime ?: "" }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            items(sorted, key = { it.id }) { appt ->
                WeekAppointmentCard(
                    appointment = appt,
                    onClick = { onAppointmentClick(appt.id) },
                )
            }
            if (sorted.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "—",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// ─── Appointment card (compact, week layout) ──────────────────────────────────

@Composable
private fun WeekAppointmentCard(
    appointment: AppointmentDetail,
    onClick: () -> Unit,
) {
    val timeLabel = isoToHhmm(appointment.startTime)
    val customerLabel = appointment.customerName?.takeIf { it.isNotBlank() }
    val serviceLabel = appointment.title?.takeIf { it.isNotBlank() } ?: "Appointment"

    val cardA11y = buildString {
        append("Appointment at $timeLabel")
        if (customerLabel != null) append(" with $customerLabel")
        append(" for $serviceLabel")
    }

    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = cardA11y
                role = Role.Button
            },
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
        ) {
            Text(
                timeLabel,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Text(
                serviceLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (customerLabel != null) {
                Text(
                    customerLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
