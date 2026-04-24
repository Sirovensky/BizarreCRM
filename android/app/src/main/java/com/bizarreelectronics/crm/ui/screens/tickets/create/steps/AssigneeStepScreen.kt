package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem

/** Urgency levels available in Step 6. */
val URGENCY_LEVELS = listOf("Critical", "High", "Normal", "Low")

/**
 * Step 6 — Assignee, urgency and due date.
 *
 * Provides:
 * - LazyVerticalGrid of employees, filterable by clocked-in status.
 * - "Assign to me" shortcut via [currentUserId].
 * - Urgency chip selector: Critical / High / Normal / Low.
 * - Due-date text field (ISO-8601 string; a DatePickerDialog is launched via [onPickDate]).
 *
 * Validation: always valid — assignment is optional.
 */
@Composable
fun AssigneeStepScreen(
    employees: List<EmployeeListItem>,
    isLoadingEmployees: Boolean,
    assigneeId: Long?,
    urgency: String,
    dueDate: String?,
    currentUserId: Long?,
    onSelectAssignee: (Long?, String?) -> Unit,
    onUpdateUrgency: (String) -> Unit,
    onUpdateDueDate: (String?) -> Unit,
    onPickDate: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showClockedInOnly by remember { mutableStateOf(false) }

    val displayedEmployees = remember(employees, showClockedInOnly) {
        if (showClockedInOnly) employees.filter { it.isClockedIn == true } else employees
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Assignee header + shortcuts ────────────────────────────────
        Text("Assignee", style = MaterialTheme.typography.titleSmall)

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FilterChip(
                selected = showClockedInOnly,
                onClick = { showClockedInOnly = !showClockedInOnly },
                label = { Text("Clocked in") },
            )
            if (currentUserId != null) {
                val me = employees.firstOrNull { it.id == currentUserId }
                if (me != null) {
                    OutlinedButton(onClick = {
                        onSelectAssignee(me.id, listOfNotNull(me.firstName, me.lastName).joinToString(" "))
                    }) {
                        Text("Assign to me")
                    }
                }
            }
            if (assigneeId != null) {
                TextButton(onClick = { onSelectAssignee(null, null) }) { Text("Clear") }
            }
        }

        // ── Employee grid ──────────────────────────────────────────────
        if (isLoadingEmployees) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 140.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 320.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(displayedEmployees, key = { "emp_${it.id}" }) { emp ->
                    EmployeeTile(
                        employee = emp,
                        isSelected = assigneeId == emp.id,
                        onSelect = {
                            onSelectAssignee(
                                emp.id,
                                listOfNotNull(emp.firstName, emp.lastName).joinToString(" "),
                            )
                        },
                    )
                }
            }
        }

        HorizontalDivider()

        // ── Urgency chips ──────────────────────────────────────────────
        Text("Urgency", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            URGENCY_LEVELS.forEach { level ->
                FilterChip(
                    selected = urgency == level,
                    onClick = { onUpdateUrgency(level) },
                    label = { Text(level) },
                )
            }
        }

        HorizontalDivider()

        // ── Due date picker ────────────────────────────────────────────
        Text("Due date", style = MaterialTheme.typography.titleSmall)
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = dueDate ?: "",
                onValueChange = { onUpdateDueDate(it.ifBlank { null }) },
                modifier = Modifier.weight(1f),
                label = { Text("YYYY-MM-DD") },
                singleLine = true,
                readOnly = false,
            )
            OutlinedButton(onClick = onPickDate) { Text("Pick") }
            if (dueDate != null) {
                TextButton(onClick = { onUpdateDueDate(null) }) { Text("Clear") }
            }
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun EmployeeTile(
    employee: EmployeeListItem,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    val name = listOfNotNull(employee.firstName, employee.lastName).joinToString(" ").ifBlank { employee.username ?: "User" }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect),
        border = if (isSelected) CardDefaults.outlinedCardBorder() else null,
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer
            else MaterialTheme.colorScheme.surface,
        ),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(Icons.Default.Person, contentDescription = null, modifier = Modifier.size(32.dp))
            Text(name, style = MaterialTheme.typography.bodySmall, maxLines = 1)
            if (isSelected) {
                Icon(Icons.Default.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
            }
            if (employee.isClockedIn == true) {
                Text("In", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}
