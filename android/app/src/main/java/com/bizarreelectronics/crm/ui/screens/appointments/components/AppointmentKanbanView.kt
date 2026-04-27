package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------

private val SLOT_HEIGHT = 56.dp          // height of each 30-min slot row
private val TIME_LABEL_WIDTH = 52.dp     // left gutter for hour labels
private val COLUMN_MIN_WIDTH = 140.dp    // min employee column width
private const val SLOTS_PER_DAY = 28     // 07:00–21:00 = 28 half-hour slots
private const val FIRST_SLOT_HOUR = 7   // grid starts at 07:00

// Brand cream #FDEED0 as a Compose Color
private val BrandCream = Color(0xFFFDEED0)

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/** A (employeeId, slotIndex) drop target inferred from drag position. */
private data class DropTarget(val employeeId: Long?, val slotIndex: Int)

/** Half-hour slot index → "HH:MM" label. */
private fun slotLabel(slotIndex: Int): String {
    val totalMinutes = FIRST_SLOT_HOUR * 60 + slotIndex * 30
    val h = totalMinutes / 60
    val m = totalMinutes % 60
    return "%02d:%02d".format(h, m)
}

/** Parse an ISO time string (e.g. "2026-04-26T09:30:00") to a slot index, or -1. */
private fun timeToSlotIndex(isoTime: String?): Int {
    if (isoTime.isNullOrBlank()) return -1
    // Accept "HH:MM" or "YYYY-MM-DDTHH:MM:SS" or "YYYY-MM-DD HH:MM:SS"
    val timePart = when {
        isoTime.length >= 16 && (isoTime[10] == 'T' || isoTime[10] == ' ') -> isoTime.substring(11, 16)
        isoTime.length >= 5 && isoTime[2] == ':' -> isoTime.take(5)
        else -> return -1
    }
    val parts = timePart.split(":")
    if (parts.size < 2) return -1
    val h = parts[0].toIntOrNull() ?: return -1
    val m = parts[1].toIntOrNull() ?: return -1
    val slotMinutes = (h - FIRST_SLOT_HOUR) * 60 + m
    return (slotMinutes / 30).coerceIn(0, SLOTS_PER_DAY - 1)
}

/** Build a new ISO start_time from a date + slot index. */
private fun slotToIsoTime(date: LocalDate, slotIndex: Int): String {
    val totalMinutes = FIRST_SLOT_HOUR * 60 + slotIndex * 30
    val h = totalMinutes / 60
    val m = totalMinutes % 60
    return "%s %02d:%02d:00".format(date.toString(), h, m)
}

// ---------------------------------------------------------------------------
// Tile color by appointment type
// ---------------------------------------------------------------------------

@Composable
private fun tileContainerColor(type: String?): Color {
    return when (type?.lowercase()) {
        "drop-off", "drop_off"  -> MaterialTheme.colorScheme.primaryContainer
        "pickup"                 -> MaterialTheme.colorScheme.secondaryContainer
        "consult"                -> MaterialTheme.colorScheme.tertiaryContainer
        "on-site", "on_site"    -> MaterialTheme.colorScheme.errorContainer
        "delivery"              -> MaterialTheme.colorScheme.surfaceVariant
        else                    -> MaterialTheme.colorScheme.surfaceContainerHigh
    }
}

// ---------------------------------------------------------------------------
// Public composable
// ---------------------------------------------------------------------------

/**
 * Time-block Kanban view (ActionPlan §10.1, tablet).
 *
 * Layout: fixed-width hour-label gutter + horizontal scroll of employee columns.
 * Each column shows 30-min slot rows; appointments appear as tonal tiles spanning
 * their duration. Drag-to-reschedule via [detectDragGestures]:
 *   1. Long-press lifts the tile and shows a ghost.
 *   2. Drag calculates the drop (employee, slot) from raw offset.
 *   3. On release: haptic [HapticFeedbackType.LongPress] (GESTURE_END equivalent)
 *      + optimistic PATCH callback; ConfirmDialog is shown if status would change.
 *
 * Phone fallback: if [isTablet] is false, renders an explanatory EmptyState
 * pointing users to the Day or Week views.
 *
 * @param appointments Full filtered appointment list.
 * @param selectedDate Currently selected date (used as the kanban date).
 * @param isLoading Loading state.
 * @param error Error message, if any.
 * @param isTablet True when the device is a tablet (>= 600dp width).
 * @param onAppointmentClick Navigate to detail.
 * @param onDateChange Navigate to a different date.
 * @param onReschedule Called with (appointmentId, newStartIso, newEmployeeId) — caller
 *   issues the PATCH and handles rollback on failure.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppointmentKanbanView(
    appointments: List<AppointmentItem>,
    selectedDate: LocalDate,
    isLoading: Boolean,
    error: String?,
    isTablet: Boolean,
    onAppointmentClick: (Long) -> Unit,
    onDateChange: (LocalDate) -> Unit,
    onReschedule: (id: Long, newStartIso: String, newEmployeeId: Long?) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Phone fallback — Kanban only makes sense on tablet (sufficient column width)
    if (!isTablet) {
        EmptyState(
            icon = Icons.Default.CalendarMonth,
            title = "Kanban is tablet-only",
            subtitle = "Switch to Day or Week view on this device",
        )
        return
    }

    when {
        isLoading -> BrandSkeleton(
            modifier = Modifier
                .fillMaxWidth()
                .height(400.dp)
                .padding(16.dp),
        )
        error != null -> ErrorState(message = error)
        else -> KanbanContent(
            appointments = appointments,
            selectedDate = selectedDate,
            onAppointmentClick = onAppointmentClick,
            onDateChange = onDateChange,
            onReschedule = onReschedule,
            modifier = modifier,
        )
    }
}

// ---------------------------------------------------------------------------
// Internal: KanbanContent (grid + drag engine)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KanbanContent(
    appointments: List<AppointmentItem>,
    selectedDate: LocalDate,
    onAppointmentClick: (Long) -> Unit,
    onDateChange: (LocalDate) -> Unit,
    onReschedule: (Long, String, Long?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val haptic = LocalHapticFeedback.current

    // Filter to today's appointments
    val dayAppts = appointments.filter { appt ->
        appt.startTime?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() } == selectedDate
    }

    // Derive unique employees from appointments (no server /employees call needed)
    val employees: List<Pair<Long?, String>> = remember(dayAppts) {
        dayAppts
            .map { it.employeeId to (it.employeeName ?: "Unassigned") }
            .distinctBy { it.first }
            .sortedBy { it.second }
            .ifEmpty { listOf(null to "Unassigned") }
    }

    // Drag state
    var draggingId by remember { mutableStateOf<Long?>(null) }
    var dragOffsetPx by remember { mutableStateOf(IntOffset.Zero) }
    // Column-root positions keyed by employeeId (null = unassigned)
    val columnPositions = remember { mutableStateMapOf<Long?, Float>() }
    // Column width cached for drop calculation
    var columnWidthPx by remember { mutableStateOf(0f) }

    // Confirm reschedule dialog
    var pendingReschedule by remember { mutableStateOf<Triple<Long, String, Long?>?>(null) }

    if (pendingReschedule != null) {
        val (rId, rStart, rEmp) = pendingReschedule!!
        val apptTitle = appointments.firstOrNull { it.id == rId }?.let {
            it.customerName ?: it.title ?: "Appointment"
        } ?: "Appointment"
        AlertDialog(
            onDismissRequest = { pendingReschedule = null },
            title = { Text("Reschedule?") },
            text = { Text("Move \"$apptTitle\" to ${rStart.take(16).replace('T', ' ')}?") },
            confirmButton = {
                Button(onClick = {
                    onReschedule(rId, rStart, rEmp)
                    pendingReschedule = null
                }) { Text("Reschedule") }
            },
            dismissButton = {
                TextButton(onClick = { pendingReschedule = null }) { Text("Cancel") }
            },
        )
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Date navigation header
        KanbanDateHeader(
            selectedDate = selectedDate,
            onPrev = { onDateChange(selectedDate.minusDays(1)) },
            onNext = { onDateChange(selectedDate.plusDays(1)) },
        )

        // Grid
        val hScroll = rememberScrollState()
        val vScroll = rememberScrollState()

        Row(modifier = Modifier.fillMaxSize()) {
            // Hour gutter (fixed, vertically scrolls with grid)
            Column(
                modifier = Modifier
                    .width(TIME_LABEL_WIDTH)
                    .verticalScroll(vScroll),
            ) {
                Spacer(Modifier.height(40.dp)) // header row height
                repeat(SLOTS_PER_DAY) { slot ->
                    Box(
                        modifier = Modifier
                            .height(SLOT_HEIGHT)
                            .fillMaxWidth()
                            .padding(end = 4.dp),
                        contentAlignment = Alignment.TopEnd,
                    ) {
                        if (slot % 2 == 0) { // show label only on whole-hour slots
                            Text(
                                text = slotLabel(slot),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 10.sp,
                            )
                        }
                    }
                }
            }

            // Employee columns (horizontally + vertically scrollable)
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .horizontalScroll(hScroll)
                    .verticalScroll(vScroll),
            ) {
                employees.forEach { (empId, empName) ->
                    val colAppts = dayAppts.filter { it.employeeId == empId }
                    EmployeeColumn(
                        employeeId = empId,
                        employeeName = empName,
                        appointments = colAppts,
                        draggingId = draggingId,
                        onColumnPositioned = { x, w ->
                            columnPositions[empId] = x
                            columnWidthPx = w
                        },
                        onAppointmentClick = onAppointmentClick,
                        onDragStart = { id ->
                            draggingId = id
                            dragOffsetPx = IntOffset.Zero
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        },
                        onDrag = { delta ->
                            dragOffsetPx = IntOffset(
                                (dragOffsetPx.x + delta.x).roundToInt(),
                                (dragOffsetPx.y + delta.y).roundToInt(),
                            )
                        },
                        onDragEnd = { sourceSlot ->
                            val id = draggingId
                            if (id != null) {
                                // Infer target column from dragOffsetPx.x + source column x
                                val sourceX = columnPositions[empId] ?: 0f
                                val dropX = sourceX + dragOffsetPx.x
                                val targetEmpId = columnPositions.entries
                                    .minByOrNull { (_, colX) -> kotlin.math.abs(colX + columnWidthPx / 2 - dropX) }
                                    ?.key
                                val slotDelta = (dragOffsetPx.y / SLOT_HEIGHT.value).roundToInt()
                                val targetSlot = (sourceSlot + slotDelta).coerceIn(0, SLOTS_PER_DAY - 1)
                                val newIso = slotToIsoTime(selectedDate, targetSlot)
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                pendingReschedule = Triple(id, newIso, targetEmpId)
                            }
                            draggingId = null
                            dragOffsetPx = IntOffset.Zero
                        },
                        onDragCancel = {
                            draggingId = null
                            dragOffsetPx = IntOffset.Zero
                        },
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Date header
// ---------------------------------------------------------------------------

@Composable
private fun KanbanDateHeader(
    selectedDate: LocalDate,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        IconButton(onClick = onPrev) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous day")
        }
        Text(
            text = selectedDate.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next day")
        }
    }
}

// ---------------------------------------------------------------------------
// Employee column
// ---------------------------------------------------------------------------

@Composable
private fun EmployeeColumn(
    employeeId: Long?,
    employeeName: String,
    appointments: List<AppointmentItem>,
    draggingId: Long?,
    onColumnPositioned: (x: Float, width: Float) -> Unit,
    onAppointmentClick: (Long) -> Unit,
    onDragStart: (id: Long) -> Unit,
    onDrag: (delta: androidx.compose.ui.geometry.Offset) -> Unit,
    onDragEnd: (sourceSlot: Int) -> Unit,
    onDragCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(COLUMN_MIN_WIDTH)
            .onGloballyPositioned { coords ->
                val pos = coords.positionInRoot()
                onColumnPositioned(pos.x, coords.size.width.toFloat())
            },
    ) {
        // Column header — employee name
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            modifier = Modifier
                .fillMaxWidth()
                .height(40.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = employeeName,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 8.dp),
                )
            }
        }

        // Time slots
        Box {
            // Background slots
            Column {
                repeat(SLOTS_PER_DAY) { slot ->
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(SLOT_HEIGHT)
                            .background(
                                if (slot % 2 == 0)
                                    MaterialTheme.colorScheme.surface
                                else
                                    MaterialTheme.colorScheme.surfaceContainerLow,
                            )
                            .border(
                                width = 0.5.dp,
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            ),
                    )
                }
            }

            // Appointment tiles overlaid on the grid
            appointments.forEach { appt ->
                val slotIdx = timeToSlotIndex(appt.startTime)
                if (slotIdx < 0) return@forEach
                val durationSlots = ((appt.durationMinutes ?: 60) / 30).coerceAtLeast(1)
                val tileHeightDp = SLOT_HEIGHT * durationSlots
                val yOffsetDp = SLOT_HEIGHT * slotIdx
                val isDragging = draggingId == appt.id
                val tileColor = tileContainerColor(appt.type)

                AppointmentTile(
                    appointment = appt,
                    tileColor = tileColor,
                    isDragging = isDragging,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(tileHeightDp)
                        .offset(y = yOffsetDp)
                        .zIndex(if (isDragging) 10f else 1f)
                        .padding(2.dp),
                    onAppointmentClick = onAppointmentClick,
                    onDragStart = { onDragStart(appt.id) },
                    onDrag = onDrag,
                    onDragEnd = { onDragEnd(slotIdx) },
                    onDragCancel = onDragCancel,
                )
            }
        }
    }

    // Column separator
    VerticalDivider(
        modifier = Modifier.height((40 + SLOT_HEIGHT.value * SLOTS_PER_DAY).dp),
        color = MaterialTheme.colorScheme.outlineVariant,
    )
}

// ---------------------------------------------------------------------------
// Appointment tile
// ---------------------------------------------------------------------------

@Composable
private fun AppointmentTile(
    appointment: AppointmentItem,
    tileColor: Color,
    isDragging: Boolean,
    modifier: Modifier = Modifier,
    onAppointmentClick: (Long) -> Unit,
    onDragStart: () -> Unit,
    onDrag: (androidx.compose.ui.geometry.Offset) -> Unit,
    onDragEnd: () -> Unit,
    onDragCancel: () -> Unit,
) {
    val elevation = if (isDragging) 8.dp else 1.dp
    Surface(
        modifier = modifier
            .shadow(elevation, RoundedCornerShape(6.dp))
            .then(
                if (isDragging) Modifier.border(
                    2.dp,
                    BrandCream,
                    RoundedCornerShape(6.dp),
                ) else Modifier
            )
            .pointerInput(appointment.id) {
                detectDragGestures(
                    onDragStart = { onDragStart() },
                    onDrag = { _, dragAmount -> onDrag(dragAmount) },
                    onDragEnd = onDragEnd,
                    onDragCancel = onDragCancel,
                )
            },
        color = tileColor,
        shape = RoundedCornerShape(6.dp),
        onClick = { onAppointmentClick(appointment.id) },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 6.dp, vertical = 4.dp),
        ) {
            Text(
                text = appointment.customerName ?: appointment.title ?: "Appt",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                fontSize = 11.sp,
            )
            appointment.type?.takeIf { it.isNotBlank() }?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
