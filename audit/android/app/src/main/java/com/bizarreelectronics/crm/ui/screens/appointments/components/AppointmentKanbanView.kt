package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

// ─── Constants ────────────────────────────────────────────────────────────────

private val HOURS = (7..20).toList()               // 07:00 – 20:00
private val TIME_COL_WIDTH  = 56.dp
private val EMPLOYEE_COL_WIDTH = 160.dp
private val ROW_HEIGHT       = 64.dp

// ─── Public composable ────────────────────────────────────────────────────────

/**
 * §10.1 Tablet time-block Kanban.
 *
 * Renders a scrollable grid where:
 *  - Rows = hourly time slots (07:00 – 20:00).
 *  - Columns = unique employee names extracted from [appointments].
 *  - Events appear as tonal tiles in the matching cell.
 *  - Long-press + drag emits an [onReschedule] callback with the
 *    appointment id, new employee name, and new start hour. The caller
 *    (AppointmentListViewModel) performs the PATCH and optimistic update.
 *
 * Tablet guard: this composable is typically only shown when
 * `LocalConfiguration.current.screenWidthDp >= 600`.
 */
@Composable
fun AppointmentKanbanView(
    appointments: List<AppointmentItem>,
    selectedDate: LocalDate,
    isLoading: Boolean,
    error: String?,
    onAppointmentClick: (Long) -> Unit,
    onReschedule: (appointmentId: Long, newEmployeeName: String, newHour: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    when {
        isLoading -> {
            Box(
                modifier = modifier
                    .fillMaxWidth()
                    .height(300.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
        }
        error != null -> {
            Box(
                modifier = modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(error, color = MaterialTheme.colorScheme.error)
            }
        }
        else -> {
            KanbanGrid(
                appointments = appointments,
                selectedDate = selectedDate,
                onAppointmentClick = onAppointmentClick,
                onReschedule = onReschedule,
                modifier = modifier,
            )
        }
    }
}

// ─── Grid ─────────────────────────────────────────────────────────────────────

@Composable
private fun KanbanGrid(
    appointments: List<AppointmentItem>,
    selectedDate: LocalDate,
    onAppointmentClick: (Long) -> Unit,
    onReschedule: (appointmentId: Long, newEmployeeName: String, newHour: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val dayAppts = appointments.filter { appt ->
        appt.startTime?.take(10)
            ?.let { runCatching { LocalDate.parse(it) }.getOrNull() } == selectedDate
    }

    // Collect unique employees in insertion order.
    val employees: List<String> = dayAppts
        .mapNotNull { it.employeeName?.takeIf { n -> n.isNotBlank() } }
        .distinct()
        .ifEmpty { listOf("Unassigned") }

    // Build a lookup: (employeeName, hour) → list of appointments
    val grid: Map<Pair<String, Int>, List<AppointmentItem>> = buildMap {
        dayAppts.forEach { appt ->
            val emp = appt.employeeName?.takeIf { it.isNotBlank() } ?: "Unassigned"
            val hour = appt.startTime
                ?.takeIf { it.length >= 16 }
                ?.substring(11, 13)
                ?.toIntOrNull() ?: return@forEach
            val key = emp to hour
            put(key, (get(key) ?: emptyList()) + appt)
        }
    }

    val hScroll = rememberScrollState()
    val vScroll = rememberScrollState()

    Column(modifier = modifier) {
        // ── Header row: time gutter + employee columns ──
        Row(
            modifier = Modifier
                .horizontalScroll(hScroll)
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            // Time gutter header (empty corner cell)
            Box(
                modifier = Modifier
                    .width(TIME_COL_WIDTH)
                    .height(40.dp),
            )
            employees.forEach { emp ->
                Box(
                    modifier = Modifier
                        .width(EMPLOYEE_COL_WIDTH)
                        .height(40.dp)
                        .border(
                            width = 0.5.dp,
                            color = MaterialTheme.colorScheme.outlineVariant,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = emp,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .padding(horizontal = 8.dp)
                            .semantics { contentDescription = "Employee: $emp" },
                    )
                }
            }
        }

        // ── Scrollable body ──
        Row(
            modifier = Modifier
                .horizontalScroll(hScroll)
                .verticalScroll(vScroll),
        ) {
            // Time gutter
            Column {
                HOURS.forEach { hour ->
                    Box(
                        modifier = Modifier
                            .width(TIME_COL_WIDTH)
                            .height(ROW_HEIGHT)
                            .border(
                                width = 0.5.dp,
                                color = MaterialTheme.colorScheme.outlineVariant,
                            ),
                        contentAlignment = Alignment.TopEnd,
                    ) {
                        Text(
                            text = LocalTime.of(hour, 0)
                                .format(DateTimeFormatter.ofPattern("h a")),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(end = 6.dp, top = 4.dp),
                        )
                    }
                }
            }

            // Employee columns
            employees.forEach { emp ->
                Column {
                    HOURS.forEach { hour ->
                        val cellAppts = grid[emp to hour] ?: emptyList()
                        KanbanCell(
                            appointments = cellAppts,
                            employeeName = emp,
                            hour = hour,
                            onAppointmentClick = onAppointmentClick,
                            onDropped = { draggedId ->
                                onReschedule(draggedId, emp, hour)
                            },
                        )
                    }
                }
            }
        }
    }
}

// ─── Individual cell ──────────────────────────────────────────────────────────

@Composable
private fun KanbanCell(
    appointments: List<AppointmentItem>,
    employeeName: String,
    hour: Int,
    onAppointmentClick: (Long) -> Unit,
    onDropped: (appointmentId: Long) -> Unit,
) {
    val haptic = LocalHapticFeedback.current

    // Drag target highlight state
    var isDragTarget by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .width(EMPLOYEE_COL_WIDTH)
            .height(ROW_HEIGHT)
            .background(
                if (isDragTarget) {
                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
                } else {
                    MaterialTheme.colorScheme.surface
                },
            )
            .border(
                width = 0.5.dp,
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            .semantics {
                contentDescription = "$employeeName ${hour}:00 slot"
            },
        contentAlignment = Alignment.TopStart,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(2.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            appointments.forEach { appt ->
                DraggableApptTile(
                    appointment = appt,
                    onClick = { onAppointmentClick(appt.id) },
                    onDragEnd = { dropped ->
                        if (dropped) {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            onDropped(appt.id)
                        }
                    },
                )
            }
        }
    }
}

// ─── Draggable appointment tile ────────────────────────────────────────────────

@Composable
private fun DraggableApptTile(
    appointment: AppointmentItem,
    onClick: () -> Unit,
    onDragEnd: (dropped: Boolean) -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    var dragOffset by remember { mutableStateOf(Offset.Zero) }
    var isDragging by remember { mutableStateOf(false) }

    val containerColor = when (appointment.type?.lowercase()) {
        "drop-off" -> MaterialTheme.colorScheme.tertiaryContainer
        "pickup"   -> MaterialTheme.colorScheme.secondaryContainer
        "consult"  -> MaterialTheme.colorScheme.primaryContainer
        "on-site"  -> MaterialTheme.colorScheme.errorContainer
        else       -> MaterialTheme.colorScheme.surfaceVariant
    }
    val labelColor = when (appointment.type?.lowercase()) {
        "drop-off" -> MaterialTheme.colorScheme.onTertiaryContainer
        "pickup"   -> MaterialTheme.colorScheme.onSecondaryContainer
        "consult"  -> MaterialTheme.colorScheme.onPrimaryContainer
        "on-site"  -> MaterialTheme.colorScheme.onErrorContainer
        else       -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 24.dp)
            .offset(dragOffset.x.dp, dragOffset.y.dp)
            .pointerInput(appointment.id) {
                detectDragGestures(
                    onDragStart = {
                        isDragging = true
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    },
                    onDrag = { _, delta ->
                        dragOffset = Offset(
                            dragOffset.x + delta.x,
                            dragOffset.y + delta.y,
                        )
                    },
                    onDragEnd = {
                        isDragging = false
                        // Consider it a "drop" if the user dragged far enough to
                        // indicate intent (> 40px in either axis).
                        val dropped = Math.abs(dragOffset.x) > 40f ||
                            Math.abs(dragOffset.y) > 40f
                        dragOffset = Offset.Zero
                        onDragEnd(dropped)
                    },
                    onDragCancel = {
                        isDragging = false
                        dragOffset = Offset.Zero
                    },
                )
            }
            .semantics {
                contentDescription = "Appointment: ${appointment.customerName ?: appointment.title ?: "Unknown"}"
            },
        color = containerColor,
        shape = MaterialTheme.shapes.extraSmall,
        tonalElevation = if (isDragging) 6.dp else 0.dp,
        shadowElevation = if (isDragging) 4.dp else 0.dp,
    ) {
        Column(modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp)) {
            Text(
                text = appointment.customerName ?: appointment.title ?: "Appointment",
                style = MaterialTheme.typography.labelSmall,
                color = labelColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            appointment.type?.let { type ->
                Text(
                    text = type,
                    style = MaterialTheme.typography.labelSmall,
                    color = labelColor.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
