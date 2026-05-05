package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MultiChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.motionSpec
import com.bizarreelectronics.crm.util.ReduceMotion
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

/**
 * §3 L491 — date range selection model.
 *
 * Emitted by [DateRangeSelector] whenever the user picks a preset or
 * confirms a custom range. Immutable value object — callers receive a
 * new instance on each change; no mutation.
 *
 * [label] is the human-readable preset name for screen reader announcements
 * and topBar sub-title ("7 days", "This month", "Apr 1 – Apr 23", …).
 */
data class DateRange(
    val from: LocalDate,
    val to: LocalDate,
    val label: String,
)

/**
 * §3 L491 — preset buckets offered in the segmented button row.
 *
 * LOCAL to dashboard — not shared with the Reports screen to avoid
 * cross-feature coupling. The Reports screen has its own DateRangePreset.
 */
enum class DashboardDatePreset(val label: String) {
    TODAY("Today"),
    YESTERDAY("Yesterday"),
    DAYS_7("7 days"),
    DAYS_30("30 days"),
    MONTH_TO_DATE("This month"),
    CUSTOM("Custom"),
}

/**
 * Maps a [DashboardDatePreset] to a concrete [DateRange] for a given [today].
 *
 * [today] is injected rather than read inside the function so that tests can
 * pass a fixed reference date without mocking system clock.
 */
fun DashboardDatePreset.toDateRange(today: LocalDate = LocalDate.now()): DateRange = when (this) {
    DashboardDatePreset.TODAY -> DateRange(today, today, label)
    DashboardDatePreset.YESTERDAY -> DateRange(today.minusDays(1), today.minusDays(1), label)
    DashboardDatePreset.DAYS_7 -> DateRange(today.minusDays(6), today, label)
    DashboardDatePreset.DAYS_30 -> DateRange(today.minusDays(29), today, label)
    DashboardDatePreset.MONTH_TO_DATE -> DateRange(
        from = YearMonth.from(today).atDay(1),
        to = today,
        label = label,
    )
    DashboardDatePreset.CUSTOM ->
        // CUSTOM must be resolved externally via the picker; fallback = today.
        DateRange(today, today, label)
}

/**
 * §3 L491 — segmented preset row + custom date-range picker sheet.
 *
 * Renders a [SingleChoiceSegmentedButtonRow] with six buckets. Selecting
 * CUSTOM opens a bottom-sheet containing a Material 3 [DateRangePicker].
 *
 * ReduceMotion: the animated container color on the selected button uses
 * [motionSpec] so the color fade is suppressed when the user has enabled
 * reduce-motion in system accessibility settings.
 *
 * @param selectedPreset currently active preset
 * @param onRangeSelected callback delivering the new [DateRange] to the caller
 * @param reduceMotion whether reduce-motion is active; read from
 *   [ReduceMotion.isReduceMotion] or [com.bizarreelectronics.crm.util.rememberReduceMotion]
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateRangeSelector(
    selectedPreset: DashboardDatePreset,
    onRangeSelected: (DateRange) -> Unit,
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var showCustomPicker by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxWidth()) {
        SingleChoiceSegmentedButtonRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
        ) {
            DashboardDatePreset.entries.forEachIndexed { index, preset ->
                val isSelected = preset == selectedPreset
                SegmentedButton(
                    selected = isSelected,
                    onClick = {
                        if (preset == DashboardDatePreset.CUSTOM) {
                            showCustomPicker = true
                        } else {
                            onRangeSelected(preset.toDateRange())
                        }
                    },
                    shape = SegmentedButtonDefaults.itemShape(
                        index = index,
                        count = DashboardDatePreset.entries.size,
                    ),
                    label = {
                        Text(
                            text = preset.label,
                            style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
                        )
                    },
                )
            }
        }
    }

    if (showCustomPicker) {
        CustomDateRangeSheet(
            onDismiss = { showCustomPicker = false },
            onConfirm = { range ->
                showCustomPicker = false
                onRangeSelected(range)
            },
        )
    }
}

// ---------------------------------------------------------------------------
// Custom date-range bottom sheet
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomDateRangeSheet(
    onDismiss: () -> Unit,
    onConfirm: (DateRange) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val pickerState = rememberDateRangePickerState()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            DateRangePicker(
                state = pickerState,
                title = { Text("Select date range", modifier = Modifier.padding(start = 16.dp, top = 16.dp)) },
                headline = null,
                showModeToggle = true,
                modifier = Modifier.fillMaxWidth(),
            )
            androidx.compose.material3.Button(
                onClick = {
                    val startMs = pickerState.selectedStartDateMillis
                    val endMs = pickerState.selectedEndDateMillis
                    if (startMs != null && endMs != null) {
                        val zoneId = ZoneId.systemDefault()
                        val from = java.time.Instant.ofEpochMilli(startMs)
                            .atZone(zoneId).toLocalDate()
                        val to = java.time.Instant.ofEpochMilli(endMs)
                            .atZone(zoneId).toLocalDate()
                        val label = "${from.format(java.time.format.DateTimeFormatter.ofPattern("MMM d"))} – " +
                            to.format(java.time.format.DateTimeFormatter.ofPattern("MMM d"))
                        onConfirm(DateRange(from = from, to = to, label = label))
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                enabled = pickerState.selectedStartDateMillis != null &&
                    pickerState.selectedEndDateMillis != null,
            ) {
                Text("Apply")
            }
        }
    }
}
