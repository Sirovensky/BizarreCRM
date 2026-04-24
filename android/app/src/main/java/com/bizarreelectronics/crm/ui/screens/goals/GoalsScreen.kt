package com.bizarreelectronics.crm.ui.screens.goals

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

private val METRIC_OPTIONS = listOf("tickets", "revenue", "commission", "nps")
private val PERIOD_OPTIONS = listOf(
    "2026-01", "2026-02", "2026-03", "2026-04",
    "2026-05", "2026-06", "2026-07", "2026-08",
    "2026-09", "2026-10", "2026-11", "2026-12",
    "Q1-2026", "Q2-2026", "Q3-2026", "Q4-2026",
)

/**
 * §48.1 Goals screen.
 *
 * Staff see their own goals with a progress ring per goal.
 * Manager/admin see all employees' goals and can create goals for the team.
 *
 * 404-tolerant: shows "Goals not configured on this server" empty state when the
 * server returns 404 for GET /goals.
 *
 * @param onBack Navigate back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen(
    onBack: () -> Unit,
    viewModel: GoalsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(state.toastMessage) {
        val msg = state.toastMessage
        if (!msg.isNullOrBlank()) {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
            viewModel.clearToast()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Goals",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (state.isManager) {
                FloatingActionButton(onClick = { viewModel.showCreateDialog() }) {
                    Icon(Icons.Default.Add, contentDescription = "Add goal")
                }
            }
        },
    ) { padding ->

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))

                state.serverUnsupported -> EmptyState(
                    icon = Icons.Default.Star,
                    title = "Goals not available",
                    subtitle = "Goals are not configured on this server.",
                )

                state.error != null -> ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.refresh() },
                )

                state.goals.isEmpty() -> EmptyState(
                    icon = Icons.Default.Star,
                    title = "No goals yet",
                    subtitle = if (state.isManager) "Tap + to create the first goal."
                    else "Your manager hasn't set goals for you yet.",
                )

                else -> LazyColumn(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(state.goals, key = { it.id }) { goal ->
                        GoalCard(
                            goal = goal,
                            canDelete = state.isManager,
                            onDelete = { viewModel.deleteGoal(goal.id) },
                        )
                    }
                }
            }
        }
    }

    if (state.showCreateDialog) {
        CreateGoalDialog(
            onDismiss = { viewModel.dismissCreateDialog() },
            onConfirm = { title, metric, target, period, isTeam ->
                viewModel.createGoal(title, metric, target, period, isTeam)
            },
        )
    }
}

@Composable
private fun GoalCard(
    goal: GoalItem,
    canDelete: Boolean,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val progress = if (goal.target > 0) (goal.progress / goal.target).coerceIn(0.0, 1.0).toFloat()
    else 0f
    val progressPct = (progress * 100).toInt()

    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = goal.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (goal.employeeName.isNotBlank()) {
                        Text(
                            text = goal.employeeName,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (goal.isTeamGoal) {
                    androidx.compose.material3.Badge { Text("Team") }
                    Spacer(Modifier.width(4.dp))
                }
                Text(
                    text = "$progressPct%",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (canDelete) {
                    IconButton(onClick = onDelete) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = "Delete goal",
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(4.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "${goal.progress.toLong()} / ${goal.target.toLong()} ${goal.metric}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = goal.period,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateGoalDialog(
    onDismiss: () -> Unit,
    onConfirm: (title: String, metric: String, target: Double, period: String, isTeam: Boolean) -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var metric by remember { mutableStateOf("tickets") }
    var targetText by remember { mutableStateOf("") }
    var period by remember { mutableStateOf(PERIOD_OPTIONS.first()) }
    var isTeam by remember { mutableStateOf(false) }
    var metricExpanded by remember { mutableStateOf(false) }
    var periodExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New Goal") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("Title") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                ExposedDropdownMenuBox(
                    expanded = metricExpanded,
                    onExpandedChange = { metricExpanded = it },
                ) {
                    OutlinedTextField(
                        value = metric,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Metric") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = metricExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = metricExpanded,
                        onDismissRequest = { metricExpanded = false },
                    ) {
                        METRIC_OPTIONS.forEach { opt ->
                            DropdownMenuItem(
                                text = { Text(opt) },
                                onClick = { metric = opt; metricExpanded = false },
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = targetText,
                    onValueChange = { targetText = it.filter { c -> c.isDigit() || c == '.' } },
                    label = { Text("Target") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                ExposedDropdownMenuBox(
                    expanded = periodExpanded,
                    onExpandedChange = { periodExpanded = it },
                ) {
                    OutlinedTextField(
                        value = period,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Period") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = periodExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = periodExpanded,
                        onDismissRequest = { periodExpanded = false },
                    ) {
                        PERIOD_OPTIONS.forEach { opt ->
                            DropdownMenuItem(
                                text = { Text(opt) },
                                onClick = { period = opt; periodExpanded = false },
                            )
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.material3.Checkbox(
                        checked = isTeam,
                        onCheckedChange = { isTeam = it },
                    )
                    Spacer(Modifier.width(4.dp))
                    Text("Team goal")
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val target = targetText.toDoubleOrNull() ?: 0.0
                onConfirm(title, metric, target, period, isTeam)
            }) { Text("Create") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
