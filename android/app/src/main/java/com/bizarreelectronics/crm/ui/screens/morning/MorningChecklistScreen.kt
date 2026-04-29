package com.bizarreelectronics.crm.ui.screens.morning

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.ChecklistStepDto
import com.bizarreelectronics.crm.util.PingResult

/**
 * §36 L585–L588 — Morning-open checklist screen.
 *
 * Displays an ordered [LazyColumn] of 7 (or tenant-configured) steps with a
 * [Checkbox] per row.  Steps 3, 4, 5 include a "View list →" navigation button.
 * Step 1 opens a cash-amount entry dialog.  Step 6 shows per-device ping status.
 *
 * The checklist is non-blocking: staff may skip individual steps or the entire
 * screen.  [onNavigateToRoute] is called when a step's "View list →" is tapped.
 * [onBack] closes the screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MorningChecklistScreen(
    onBack: () -> Unit,
    onNavigateToRoute: (route: String) -> Unit,
    viewModel: MorningChecklistViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showCashDialog by remember { mutableStateOf(false) }
    var cashInput by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Morning Checklist") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Go back",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Complete before opening the shop",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(8.dp))
            }

            items(uiState.steps, key = { it.id }) { step ->
                ChecklistStepRow(
                    step = step,
                    isChecked = step.id in uiState.completedStepIds,
                    pingResult = uiState.pingResults[step.id],
                    onToggle = {
                        if (step.requiresInput && step.id !in uiState.completedStepIds) {
                            // Step 1: open cash dialog before marking complete
                            showCashDialog = true
                        } else {
                            viewModel.toggleStep(step.id)
                        }
                    },
                    onViewList = step.deepLinkRoute?.let { route -> { onNavigateToRoute(route) } },
                )
            }

            item {
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = { viewModel.completeChecklist() },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { role = Role.Button },
                    enabled = !uiState.isSubmitting,
                ) {
                    if (uiState.isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(
                        text = if (uiState.isAllDone) "Done — Shop is open!" else "Mark all complete",
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                // §3.15 L589 — Skip records the event locally + attempts a server
                // audit-log POST (404-tolerant) before navigating back.
                TextButton(
                    onClick = {
                        viewModel.skipChecklist()
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Skip checklist for today")
                }
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }

    // Cash-drawer float dialog (step 1)
    if (showCashDialog) {
        AlertDialog(
            onDismissRequest = { showCashDialog = false },
            title = { Text("Starting cash amount") },
            text = {
                Column {
                    Text(
                        "Enter the float amount counted in the cash drawer.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedTextField(
                        value = cashInput,
                        onValueChange = { cashInput = it },
                        label = { Text("Amount (\$)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.setCashAmount(cashInput)
                        viewModel.toggleStep(1)
                        showCashDialog = false
                    },
                ) {
                    Text("Confirm")
                }
            },
            dismissButton = {
                TextButton(onClick = { showCashDialog = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}

// ---------------------------------------------------------------------------
// Step row composable
// ---------------------------------------------------------------------------

/**
 * §36 L586 — A single morning-checklist step rendered as a [Card] with:
 *  - A [Checkbox] (left)
 *  - Title + subtitle text (centre)
 *  - Optional "View list →" button (right, for steps 3/4/5)
 *  - Optional [PingResult] indicator (for step 6 hardware devices)
 *
 * @param step       The checklist step data.
 * @param isChecked  Whether the checkbox is ticked.
 * @param pingResult Latest ping result for hardware steps, or null.
 * @param onToggle   Called when the checkbox or row is tapped.
 * @param onViewList Called when "View list →" is tapped; null = button hidden.
 */
@Composable
fun ChecklistStepRow(
    step: ChecklistStepDto,
    isChecked: Boolean,
    pingResult: PingResult?,
    onToggle: () -> Unit,
    onViewList: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "${step.title}. ${if (isChecked) "Completed" else "Not completed"}."
            },
        colors = CardDefaults.cardColors(
            containerColor = if (isChecked) {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
            } else {
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            },
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Checkbox(
                checked = isChecked,
                onCheckedChange = { onToggle() },
                modifier = Modifier.semantics { role = Role.Checkbox },
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = step.title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                if (step.subtitle.isNotBlank()) {
                    Text(
                        text = step.subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                // Ping indicator for hardware step
                if (pingResult != null) {
                    Spacer(modifier = Modifier.height(4.dp))
                    PingStatusIndicator(result = pingResult)
                }
            }

            // "View list →" button for navigable steps
            if (onViewList != null) {
                TextButton(
                    onClick = onViewList,
                    contentPadding = ButtonDefaults.TextButtonContentPadding,
                ) {
                    Text(
                        "View",
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Spacer(modifier = Modifier.width(2.dp))
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Ping status indicator
// ---------------------------------------------------------------------------

/**
 * §36 L587 — Renders a colour-coded ping result badge:
 *  - [PingResult.Pending]  → amber [CircularProgressIndicator]
 *  - [PingResult.Success]  → green check + latency label
 *  - [PingResult.Timeout]  → amber warning icon
 *  - [PingResult.Failure]  → red cross + reason (tap → diagnostic dialog)
 */
@Composable
fun PingStatusIndicator(
    result: PingResult,
    modifier: Modifier = Modifier,
) {
    var showDiagDialog by remember { mutableStateOf(false) }
    var diagReason by remember { mutableStateOf("") }

    val ext = LocalExtendedColors.current
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        when (result) {
            is PingResult.Pending -> {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    strokeWidth = 2.dp,
                    color = ext.warning,
                )
                Text(
                    text = "Pinging…",
                    style = MaterialTheme.typography.labelSmall,
                    color = ext.warning,
                )
            }

            is PingResult.Success -> {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = "Device reachable",
                    tint = ext.success,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = "OK (${result.latencyMs} ms)",
                    style = MaterialTheme.typography.labelSmall,
                    color = ext.success,
                )
            }

            is PingResult.Timeout -> {
                Icon(
                    imageVector = Icons.Default.HourglassEmpty,
                    contentDescription = "Ping timed out",
                    tint = ext.warning,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = "Timeout (2 s)",
                    style = MaterialTheme.typography.labelSmall,
                    color = ext.warning,
                )
            }

            is PingResult.Failure -> {
                IconButton(
                    onClick = {
                        diagReason = result.reason
                        showDiagDialog = true
                    },
                    modifier = Modifier.size(18.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Error,
                        contentDescription = "Device unreachable — tap for details",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(14.dp),
                    )
                }
                Text(
                    text = "Unreachable",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }

    if (showDiagDialog) {
        AlertDialog(
            onDismissRequest = { showDiagDialog = false },
            title = { Text("Device unreachable") },
            text = {
                Text(
                    "Diagnostic: $diagReason\n\nCheck that the device is powered on and connected to the network.",
                )
            },
            confirmButton = {
                TextButton(onClick = { showDiagDialog = false }) { Text("OK") }
            },
        )
    }
}
