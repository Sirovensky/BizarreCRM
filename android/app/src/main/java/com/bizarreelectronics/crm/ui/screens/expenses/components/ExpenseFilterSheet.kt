package com.bizarreelectronics.crm.ui.screens.expenses.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private val ISO_DATE: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

/** Approval status options shown as filter chips in the sheet. */
internal val APPROVAL_STATUS_OPTIONS = listOf(
    "" to "All",
    "pending" to "Pending",
    "approved" to "Approved",
    "denied" to "Denied",
)

/**
 * Bottom sheet for expense list multi-dimensional filtering.
 *
 * Dimensions:
 * - Date range (from / to) — Material3 DatePicker per field
 * - Approval status — chip row
 * - Employee name — free-text search
 *
 * Category filter is kept as a LazyRow chip bar on the main screen for quick access.
 * This sheet handles the less-frequent compound filters.
 *
 * All callbacks are invoked on every change; the caller debounces if needed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseFilterSheet(
    dateFrom: String,
    dateTo: String,
    approvalStatus: String,
    employeeName: String,
    onDateFromChanged: (String) -> Unit,
    onDateToChanged: (String) -> Unit,
    onApprovalStatusChanged: (String) -> Unit,
    onEmployeeNameChanged: (String) -> Unit,
    onClearAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val hasActiveFilters = dateFrom.isNotBlank() || dateTo.isNotBlank() ||
        approvalStatus.isNotBlank() || employeeName.isNotBlank()

    var showFromPicker by remember { mutableStateOf(false) }
    var showToPicker by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Handle bar
        Box(
            modifier = Modifier
                .width(32.dp)
                .height(4.dp)
                .align(Alignment.CenterHorizontally),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                modifier = Modifier.fillMaxSize(),
            ) {}
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Filter expenses",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (hasActiveFilters) {
                TextButton(onClick = onClearAll) {
                    Icon(Icons.Default.Clear, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Clear all")
                }
            }
        }

        HorizontalDivider()

        // ── Date range ──────────────────────────────────────────────────────
        Text(
            "Date range",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // From date
            OutlinedTextField(
                value = dateFrom,
                onValueChange = { /* read-only — use picker */ },
                label = { Text("From") },
                readOnly = true,
                trailingIcon = {
                    if (dateFrom.isNotBlank()) {
                        IconButton(onClick = { onDateFromChanged("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear from date")
                        }
                    } else {
                        IconButton(onClick = { showFromPicker = true }) {
                            Icon(Icons.Default.CalendarToday, contentDescription = "Pick from date")
                        }
                    }
                },
                modifier = Modifier
                    .weight(1f)
                    .also { if (dateFrom.isBlank()) it },
                singleLine = true,
            )
            // To date
            OutlinedTextField(
                value = dateTo,
                onValueChange = { /* read-only — use picker */ },
                label = { Text("To") },
                readOnly = true,
                trailingIcon = {
                    if (dateTo.isNotBlank()) {
                        IconButton(onClick = { onDateToChanged("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear to date")
                        }
                    } else {
                        IconButton(onClick = { showToPicker = true }) {
                            Icon(Icons.Default.CalendarToday, contentDescription = "Pick to date")
                        }
                    }
                },
                modifier = Modifier.weight(1f),
                singleLine = true,
            )
        }

        // ── Approval status ─────────────────────────────────────────────────
        Text(
            "Approval status",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            APPROVAL_STATUS_OPTIONS.forEach { (value, label) ->
                val selected = approvalStatus == value
                FilterChip(
                    selected = selected,
                    onClick = { onApprovalStatusChanged(value) },
                    label = { Text(label) },
                )
            }
        }

        // ── Employee name ───────────────────────────────────────────────────
        Text(
            "Employee",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = employeeName,
            onValueChange = onEmployeeNameChanged,
            label = { Text("Employee name") },
            placeholder = { Text("e.g. John") },
            singleLine = true,
            trailingIcon = {
                if (employeeName.isNotBlank()) {
                    IconButton(onClick = { onEmployeeNameChanged("") }) {
                        Icon(Icons.Default.Clear, contentDescription = "Clear employee filter")
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.height(8.dp))
    }

    // ── Date picker dialogs ──────────────────────────────────────────────
    if (showFromPicker) {
        ExpenseDatePickerDialog(
            initialDate = dateFrom,
            title = "Pick start date",
            onDateSelected = { date ->
                onDateFromChanged(date)
                showFromPicker = false
            },
            onDismiss = { showFromPicker = false },
        )
    }

    if (showToPicker) {
        ExpenseDatePickerDialog(
            initialDate = dateTo,
            title = "Pick end date",
            onDateSelected = { date ->
                onDateToChanged(date)
                showToPicker = false
            },
            onDismiss = { showToPicker = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExpenseDatePickerDialog(
    initialDate: String,
    title: String,
    onDateSelected: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val initial: Long? = remember(initialDate) {
        if (initialDate.isBlank()) null
        else try {
            LocalDate.parse(initialDate, ISO_DATE)
                .atStartOfDay()
                .toInstant(java.time.ZoneOffset.UTC)
                .toEpochMilli()
        } catch (_: Exception) { null }
    }

    val datePickerState = rememberDatePickerState(
        initialSelectedDateMillis = initial,
    )

    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                val ms = datePickerState.selectedDateMillis
                if (ms != null) {
                    val date = java.time.Instant.ofEpochMilli(ms)
                        .atZone(java.time.ZoneOffset.UTC)
                        .toLocalDate()
                        .format(ISO_DATE)
                    onDateSelected(date)
                } else {
                    onDismiss()
                }
            }) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    ) {
        DatePicker(
            state = datePickerState,
            title = { Text(title, modifier = Modifier.padding(start = 24.dp, end = 12.dp, top = 16.dp)) },
        )
    }
}
