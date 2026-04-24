package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * Month calendar grid (L1420).
 *
 * Uses [YearMonth] for iteration. Displays a 6-row × 7-col grid with:
 *   - Navigation arrows to adjacent months
 *   - Today highlighted with a filled circle
 *   - Appointment-count dots per day (up to 3 shown, "+" if more)
 *   - Tap on a day → [onDayClick] with that [LocalDate]
 */
@Composable
fun AppointmentMonthView(
    appointments: List<AppointmentItem>,
    selectedMonth: LocalDate,
    isLoading: Boolean,
    error: String?,
    onDayClick: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
) {
    var displayMonth by remember(selectedMonth) {
        mutableStateOf(YearMonth.from(selectedMonth))
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Month navigation header
        MonthHeader(
            month = displayMonth,
            onPrevious = { displayMonth = displayMonth.minusMonths(1) },
            onNext = { displayMonth = displayMonth.plusMonths(1) },
        )

        // Day-of-week labels (Sun … Sat)
        DayOfWeekRow()

        when {
            isLoading -> BrandSkeleton(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(320.dp)
                    .padding(16.dp),
            )
            error != null -> ErrorState(message = error)
            else -> {
                // Build date → count map for the displayed month
                val countByDate = buildApptCountMap(appointments)
                CalendarGrid(
                    month = displayMonth,
                    countByDate = countByDate,
                    today = LocalDate.now(),
                    onDayClick = onDayClick,
                )
            }
        }
    }
}

@Composable
private fun MonthHeader(
    month: YearMonth,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    val label = month.format(DateTimeFormatter.ofPattern("MMMM yyyy"))
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        IconButton(onClick = onPrevious) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous month")
        }
        Text(
            text = label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next month")
        }
    }
}

@Composable
private fun DayOfWeekRow() {
    val days = listOf(
        DayOfWeek.SUNDAY, DayOfWeek.MONDAY, DayOfWeek.TUESDAY,
        DayOfWeek.WEDNESDAY, DayOfWeek.THURSDAY, DayOfWeek.FRIDAY,
        DayOfWeek.SATURDAY,
    )
    Row(modifier = Modifier.fillMaxWidth()) {
        days.forEach { dow ->
            Text(
                text = dow.getDisplayName(TextStyle.NARROW, Locale.getDefault()),
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CalendarGrid(
    month: YearMonth,
    countByDate: Map<LocalDate, Int>,
    today: LocalDate,
    onDayClick: (LocalDate) -> Unit,
) {
    val firstDay = month.atDay(1)
    // Sunday = 0 … Saturday = 6; DayOfWeek.SUNDAY.value == 7 in java.time
    val startOffset = (firstDay.dayOfWeek.value % 7) // 0 = Sunday
    val daysInMonth = month.lengthOfMonth()
    val totalCells = ((startOffset + daysInMonth + 6) / 7) * 7  // round up to full weeks

    Column(modifier = Modifier.fillMaxWidth()) {
        var cell = 0
        while (cell < totalCells) {
            Row(modifier = Modifier.fillMaxWidth()) {
                repeat(7) { col ->
                    val idx = cell + col
                    val dayNum = idx - startOffset + 1
                    val isValid = dayNum in 1..daysInMonth
                    val date = if (isValid) month.atDay(dayNum) else null
                    val count = date?.let { countByDate[it] } ?: 0
                    DayCell(
                        date = date,
                        apptCount = count,
                        isToday = date == today,
                        onClick = { date?.let(onDayClick) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            cell += 7
        }
    }
}

@Composable
private fun DayCell(
    date: LocalDate?,
    apptCount: Int,
    isToday: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colorScheme = MaterialTheme.colorScheme
    val bgColor = if (isToday) colorScheme.primary else colorScheme.surface
    val textColor = if (isToday) colorScheme.onPrimary else colorScheme.onSurface

    val cdLabel = date?.let { "Day ${it.dayOfMonth}, $apptCount appointments" } ?: "Empty"

    Box(
        modifier = modifier
            .aspectRatio(1f)
            .padding(2.dp)
            .clip(CircleShape)
            .then(
                if (date != null) Modifier.clickable(onClick = onClick) else Modifier
            )
            .semantics { contentDescription = cdLabel },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (date != null) {
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(bgColor),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = date.dayOfMonth.toString(),
                        style = MaterialTheme.typography.bodySmall,
                        fontSize = 12.sp,
                        color = textColor,
                    )
                }
                if (apptCount > 0) {
                    ApptDots(count = apptCount)
                }
            }
        }
    }
}

@Composable
private fun ApptDots(count: Int) {
    val dotColor = MaterialTheme.colorScheme.primary
    Row(
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.padding(top = 2.dp),
    ) {
        val dots = minOf(count, 3)
        repeat(dots) {
            Box(
                modifier = Modifier
                    .size(4.dp)
                    .clip(CircleShape)
                    .background(dotColor),
            )
        }
        if (count > 3) {
            Text(
                text = "+",
                style = MaterialTheme.typography.labelSmall,
                fontSize = 8.sp,
                color = dotColor,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Helper: build date→count map from ISO-8601 startTime strings
// ---------------------------------------------------------------------------

private val ISO_FORMATTER = DateTimeFormatter.ISO_DATE_TIME

internal fun buildApptCountMap(appointments: List<AppointmentItem>): Map<LocalDate, Int> {
    val map = mutableMapOf<LocalDate, Int>()
    for (appt in appointments) {
        val startTime = appt.startTime ?: continue
        runCatching {
            val date = LocalDate.parse(startTime.take(10))
            map[date] = (map[date] ?: 0) + 1
        }
    }
    return map
}
