package com.bizarreelectronics.crm.ui.screens.expenses.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Approval status options surfaced in the filter sheet.
 * Matches the server `expenses.status` CHECK constraint.
 */
enum class ExpenseApprovalFilter(val label: String, val apiValue: String?) {
    ALL("All statuses", null),
    PENDING("Pending", "pending"),
    APPROVED("Approved", "approved"),
    DENIED("Denied", "denied"),
}

/**
 * Employee entry shown in the employee chip row.
 * [userId] == null means "all employees".
 */
data class EmployeeOption(val userId: Long?, val displayName: String)

/**
 * Current state of the advanced expense filters.
 *
 * @param fromDate ISO-8601 date string (e.g. "2025-01-01"), empty = no lower bound.
 * @param toDate   ISO-8601 date string, empty = no upper bound.
 * @param selectedEmployeeId null = all employees; non-null = filter by user_id.
 * @param approvalFilter approval-status chip selection.
 */
data class ExpenseFilterState(
    val fromDate: String = "",
    val toDate: String = "",
    val selectedEmployeeId: Long? = null,
    val approvalFilter: ExpenseApprovalFilter = ExpenseApprovalFilter.ALL,
) {
    val isActive: Boolean
        get() = fromDate.isNotEmpty() || toDate.isNotEmpty() ||
            selectedEmployeeId != null ||
            approvalFilter != ExpenseApprovalFilter.ALL
}

/**
 * Modal bottom sheet with advanced expense filters:
 *  - Date range (from / to) via Material 3 [DatePicker]
 *  - Employee selection via [FilterChip] row
 *  - Approval status via [FilterChip] row
 *
 * All filter state is hoisted: changes call [onFilterChanged] and the sheet
 * does not dismiss until the user taps "Apply". A "Clear all" button resets
 * every filter.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseFilterSheet(
    filterState: ExpenseFilterState,
    employeeOptions: List<EmployeeOption>,
    onFilterChanged: (ExpenseFilterState) -> Unit,
    onDismiss: () -> Unit,
) {
    var localState by remember(filterState) { mutableStateOf(filterState) }
    var showFromPicker by remember { mutableStateOf(false) }
    var showToPicker by remember { mutableStateOf(false) }

    val isoFormatter = remember { DateTimeFormatter.ISO_LOCAL_DATE }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Header ────────────────────────────────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.expense_filter_title),
                    style = MaterialTheme.typography.titleMedium,
                )
                TextButton(
                    onClick = {
                        localState = ExpenseFilterState()
                        onFilterChanged(ExpenseFilterState())
                    },
                    enabled = localState.isActive,
                ) {
                    Text(stringResource(R.string.expense_filter_clear_all))
                }
            }

            HorizontalDivider()

            // ── Date range ────────────────────────────────────────────────────
            Text(
                text = stringResource(R.string.expense_filter_date_range),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = { showFromPicker = true },
                    modifier = Modifier
                        .weight(1f)
                        .semantics {
                            contentDescription = if (localState.fromDate.isEmpty())
                                "From date, not set"
                            else
                                "From date, ${localState.fromDate}"
                        },
                ) {
                    Text(
                        text = localState.fromDate.ifEmpty {
                            stringResource(R.string.expense_filter_from_date)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                OutlinedButton(
                    onClick = { showToPicker = true },
                    modifier = Modifier
                        .weight(1f)
                        .semantics {
                            contentDescription = if (localState.toDate.isEmpty())
                                "To date, not set"
                            else
                                "To date, ${localState.toDate}"
                        },
                ) {
                    Text(
                        text = localState.toDate.ifEmpty {
                            stringResource(R.string.expense_filter_to_date)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                if (localState.fromDate.isNotEmpty() || localState.toDate.isNotEmpty()) {
                    IconButton(
                        onClick = { localState = localState.copy(fromDate = "", toDate = "") },
                    ) {
                        Icon(
                            Icons.Default.Clear,
                            contentDescription = stringResource(R.string.expense_filter_clear_dates),
                        )
                    }
                }
            }

            // ── Approval status ───────────────────────────────────────────────
            Text(
                text = stringResource(R.string.expense_filter_approval_status),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ExpenseApprovalFilter.entries.forEach { filter ->
                    val selected = localState.approvalFilter == filter
                    FilterChip(
                        selected = selected,
                        onClick = { localState = localState.copy(approvalFilter = filter) },
                        label = { Text(filter.label) },
                        modifier = Modifier.semantics {
                            contentDescription = if (selected)
                                "${filter.label}, selected"
                            else
                                "${filter.label}, not selected"
                        },
                    )
                }
            }

            // ── Employee ──────────────────────────────────────────────────────
            if (employeeOptions.size > 1) {
                Text(
                    text = stringResource(R.string.expense_filter_employee),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // Wrap in a Row that scrolls horizontally via scrollable modifier
                androidx.compose.foundation.lazy.LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(employeeOptions.size) { idx ->
                        val option = employeeOptions[idx]
                        val selected = localState.selectedEmployeeId == option.userId
                        FilterChip(
                            selected = selected,
                            onClick = {
                                localState = localState.copy(
                                    selectedEmployeeId = if (selected) null else option.userId,
                                )
                            },
                            label = { Text(option.displayName) },
                            modifier = Modifier.semantics {
                                contentDescription = if (selected)
                                    "${option.displayName}, selected"
                                else
                                    "${option.displayName}, not selected"
                            },
                        )
                    }
                }
            }

            HorizontalDivider()

            // ── Apply button ──────────────────────────────────────────────────
            FilledTonalButton(
                onClick = {
                    onFilterChanged(localState)
                    onDismiss()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Apply expense filters"
                    },
            ) {
                Text(stringResource(R.string.expense_filter_apply))
            }
        }
    }

    // ── Date picker dialogs ───────────────────────────────────────────────────
    if (showFromPicker) {
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = localState.fromDate
                .toEpochMillisOrNull(isoFormatter),
        )
        DatePickerDialog(
            onDismissRequest = { showFromPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        pickerState.selectedDateMillis?.let { millis ->
                            localState = localState.copy(
                                fromDate = millis.toIsoDate(isoFormatter),
                            )
                        }
                        showFromPicker = false
                    },
                ) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showFromPicker = false }) { Text("Cancel") }
            },
        ) {
            DatePicker(state = pickerState)
        }
    }

    if (showToPicker) {
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = localState.toDate
                .toEpochMillisOrNull(isoFormatter),
        )
        DatePickerDialog(
            onDismissRequest = { showToPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        pickerState.selectedDateMillis?.let { millis ->
                            localState = localState.copy(
                                toDate = millis.toIsoDate(isoFormatter),
                            )
                        }
                        showToPicker = false
                    },
                ) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showToPicker = false }) { Text("Cancel") }
            },
        ) {
            DatePicker(state = pickerState)
        }
    }
}

// ── Date conversion helpers ───────────────────────────────────────────────────

/** Parse an ISO date string to epoch milliseconds, or null if blank/invalid. */
private fun String.toEpochMillisOrNull(fmt: DateTimeFormatter): Long? {
    if (isEmpty()) return null
    return try {
        LocalDate.parse(this, fmt)
            .atStartOfDay(java.time.ZoneOffset.UTC)
            .toInstant()
            .toEpochMilli()
    } catch (_: Exception) {
        null
    }
}

/** Convert epoch milliseconds (UTC midnight) to an ISO date string. */
private fun Long.toIsoDate(fmt: DateTimeFormatter): String {
    val instant = java.time.Instant.ofEpochMilli(this)
    val date = instant.atZone(java.time.ZoneOffset.UTC).toLocalDate()
    return date.format(fmt)
}
