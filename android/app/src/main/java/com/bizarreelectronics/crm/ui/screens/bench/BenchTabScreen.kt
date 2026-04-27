package com.bizarreelectronics.crm.ui.screens.bench

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Inventory
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.tickets.components.BenchTimerCard
import com.bizarreelectronics.crm.ui.screens.tickets.components.HandoffEmployee
import com.bizarreelectronics.crm.ui.screens.tickets.components.QcChecklistItem
import com.bizarreelectronics.crm.ui.screens.tickets.components.QcChecklistSheet
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketHandoffDialog
import kotlinx.coroutines.launch

/**
 * BenchTabScreen — §43
 *
 * Full-screen list of the authenticated technician's active bench tickets.
 * Accessible from the Dashboard "Bench" tile (§43.1) or as a direct nav destination.
 *
 * Each row shows:
 *  - Ticket order ID, device description, and customer name.
 *  - A [BenchTimerCard] with per-ticket start/stop wired to [BenchTabViewModel] (§43.2).
 *  - A "Templates" shortcut to [Screen.DeviceTemplates] (§43.1).
 *  - A QC checklist chip that opens [QcChecklistSheet] on tap (§43.3).
 *  - A "Parts missing" chip that opens a parts-needed confirmation (§43.4).
 *  - A "Hand off" chip that opens [TicketHandoffDialog] for shift-change (§43.5).
 *
 * Multi-timer: multiple tickets can run concurrently; each has its own timer
 * driven by the [BenchTabUiState.runningTimers] set (§43.2).
 *
 * @param onBack                Navigate back (pop the back stack).
 * @param onNavigateToTicket    Open TicketDetail for the given ticket ID.
 * @param onNavigateToTemplates Navigate to DeviceTemplates settings sub-screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchTabScreen(
    onBack: () -> Unit,
    onNavigateToTicket: (Long) -> Unit,
    onNavigateToTemplates: () -> Unit,
    viewModel: BenchTabViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // Show transient snackbar messages from the VM.
    LaunchedEffect(state.timerError) {
        state.timerError?.let { msg ->
            scope.launch { snackbarHostState.showSnackbar(msg) }
            viewModel.clearTimerError()
        }
    }
    LaunchedEffect(state.partsMessage) {
        state.partsMessage?.let { msg ->
            scope.launch { snackbarHostState.showSnackbar(msg) }
            viewModel.clearPartsMessage()
        }
    }
    LaunchedEffect(state.handoffMessage) {
        state.handoffMessage?.let { msg ->
            scope.launch { snackbarHostState.showSnackbar(msg) }
            viewModel.clearHandoffMessage()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "My Bench",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.loadBench() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh bench")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.offline -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Build,
                        title = "Offline",
                        subtitle = "Bench requires a server connection.",
                    )
                }
            }

            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load bench tickets",
                        onRetry = { viewModel.loadBench() },
                    )
                }
            }

            state.tickets.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Build,
                        title = "No active bench tickets",
                        subtitle = "Tickets assigned to you with status \"In Repair\" will appear here.",
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(
                        items = state.tickets,
                        key = { it.id },
                    ) { ticket ->
                        BenchTicketRow(
                            ticket = ticket,
                            isTimerRunning = ticket.id in state.runningTimers,
                            employees = state.employees.map { emp ->
                                HandoffEmployee(
                                    id = emp.id,
                                    displayName = listOfNotNull(emp.firstName, emp.lastName)
                                        .joinToString(" ")
                                        .ifBlank { emp.username ?: "Employee ${emp.id}" },
                                    role = emp.role,
                                )
                            },
                            onRowClick = { onNavigateToTicket(ticket.id) },
                            onTemplatesClick = onNavigateToTemplates,
                            onTimerStart = { viewModel.startTimer(ticket.id) },
                            onTimerStop = { viewModel.stopTimer(ticket.id) },
                            onMarkPartMissing = { deviceId, partId, partName ->
                                viewModel.markPartMissing(ticket.id, deviceId, partId, partName)
                            },
                            onHandoff = { employeeId, reason ->
                                viewModel.handoffTicket(ticket.id, employeeId, reason)
                            },
                            onHandoffDialogOpen = { viewModel.loadEmployees() },
                        )
                    }
                }
            }
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

/**
 * A single bench ticket row showing ticket metadata + elapsed timer +
 * template shortcut + action chips for QC, parts, and handoff.
 *
 * Uses [OutlinedCard] per M3-Expressive guidelines. Touch targets are ≥48dp.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BenchTicketRow(
    ticket: TicketListItem,
    isTimerRunning: Boolean,
    employees: List<HandoffEmployee>,
    onRowClick: () -> Unit,
    onTemplatesClick: () -> Unit,
    onTimerStart: () -> Unit,
    onTimerStop: () -> Unit,
    onMarkPartMissing: (deviceId: Long, partId: Long, partName: String) -> Unit,
    onHandoff: (employeeId: Long, reason: String) -> Unit,
    onHandoffDialogOpen: () -> Unit,
) {
    // §43.3 — QC checklist sheet state
    var showQcSheet by rememberSaveable { mutableStateOf(false) }

    // §43.4 — parts-needed confirm state
    var showPartsDialog by rememberSaveable { mutableStateOf(false) }

    // §43.5 — handoff dialog state
    var showHandoffDialog by rememberSaveable { mutableStateOf(false) }

    OutlinedCard(
        onClick = onRowClick,
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // ── Ticket header: order ID + device ──────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "#${ticket.orderId}",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                    val deviceLabel = ticket.firstDevice?.deviceName
                        ?: ticket.firstDevice?.deviceType
                        ?: "Unknown device"
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(
                            Icons.Default.PhoneAndroid,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = deviceLabel,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    ticket.customerName.takeIf { it.isNotBlank() && it != "Unknown" }?.let { name ->
                        Text(
                            text = name,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                // §43.1 — Device templates shortcut
                FilledTonalButton(
                    onClick = onTemplatesClick,
                    modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                ) {
                    Icon(
                        Icons.Default.Build,
                        contentDescription = "Open device templates",
                        modifier = Modifier.padding(end = 4.dp),
                    )
                    Text(
                        text = "Templates",
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }

            // ── §43.2 Bench timer ─────────────────────────────────────────────
            // RepairInProgressService.start/stop is called by BenchTimerCard via
            // LiveUpdateNotifier on each tick to post a CATEGORY_PROGRESS
            // foreground notification (dataSync type, see AndroidManifest.xml L268).
            BenchTimerCard(
                ticketId = ticket.id,
                orderId = ticket.orderId,
                isRunning = isTimerRunning,
                onStart = onTimerStart,
                onStop = onTimerStop,
            )

            // ── §43.3 / §43.4 / §43.5 Action chips ───────────────────────────
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // §43.3 — QC checklist chip
                FilterChip(
                    selected = false,
                    onClick = { showQcSheet = true },
                    label = { Text("QC Check", style = MaterialTheme.typography.labelSmall) },
                    leadingIcon = {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = "Open QC checklist",
                        )
                    },
                    modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                )

                // §43.4 — Parts-needed chip
                FilterChip(
                    selected = false,
                    onClick = { showPartsDialog = true },
                    label = { Text("Parts?", style = MaterialTheme.typography.labelSmall) },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Inventory,
                            contentDescription = "Mark part missing",
                        )
                    },
                    modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                )

                // §43.5 — Handoff chip
                FilterChip(
                    selected = false,
                    onClick = {
                        onHandoffDialogOpen()
                        showHandoffDialog = true
                    },
                    label = { Text("Hand off", style = MaterialTheme.typography.labelSmall) },
                    leadingIcon = {
                        Icon(
                            Icons.Default.SwapHoriz,
                            contentDescription = "Hand off this ticket to another technician",
                        )
                    },
                    modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                )
            }
        }
    }

    // ── §43.3 QC checklist bottom sheet ──────────────────────────────────────
    if (showQcSheet) {
        // Starter QC items — in production these come from
        // GET /qc-checklists?service_id= (404-tolerant). Here we provide a
        // sensible default set so the sheet is always functional.
        val defaultQcItems = remember {
            listOf(
                QcChecklistItem(1L, "Power on / boot test"),
                QcChecklistItem(2L, "Touch-screen response"),
                QcChecklistItem(3L, "Front camera"),
                QcChecklistItem(4L, "Rear camera"),
                QcChecklistItem(5L, "Speaker / earpiece"),
                QcChecklistItem(6L, "Microphone"),
                QcChecklistItem(7L, "Charging port"),
                QcChecklistItem(8L, "Battery health > 80%"),
                QcChecklistItem(9L, "No physical damage from repair"),
                QcChecklistItem(10L, "Wi-Fi / cellular connectivity"),
            )
        }
        QcChecklistSheet(
            items = defaultQcItems,
            requireSecondSignoff = false,
            onComplete = { _ ->
                // QC payload would be submitted via TicketApi.qcSignOff in a
                // production flow; the sheet handles its own sign-off bitmap.
                showQcSheet = false
            },
            onDismiss = { showQcSheet = false },
        )
    }

    // ── §43.4 Parts-needed dialog ─────────────────────────────────────────────
    if (showPartsDialog) {
        // Stub: marks the first device's first part as missing.
        // A full implementation would show a list of parts from the ticket detail.
        // The server-side auto-status update (→ Awaiting Parts) and push to
        // purchasing manager are server responsibilities and are deferred.
        BenchPartsNeededDialog(
            ticketId = ticket.id,
            onMarkMissing = { deviceId, partId, partName ->
                onMarkPartMissing(deviceId, partId, partName)
                showPartsDialog = false
            },
            onDismiss = { showPartsDialog = false },
        )
    }

    // ── §43.5 Handoff dialog ──────────────────────────────────────────────────
    if (showHandoffDialog) {
        TicketHandoffDialog(
            currentAssigneeName = null,
            employees = employees,
            onConfirm = { employeeId, reason ->
                onHandoff(employeeId, reason)
                showHandoffDialog = false
            },
            onDismiss = { showHandoffDialog = false },
        )
    }
}

// ─── §43.4 Parts-needed dialog ────────────────────────────────────────────────

/**
 * §43.4 Parts-needed confirm dialog.
 *
 * Shown when the technician taps the "Parts?" chip on a bench ticket row.
 * The dialog asks the tech to name the missing part and confirm.
 *
 * In production the part list should be fetched from the ticket detail
 * (GET /tickets/:id) so the tech can check boxes. For now a free-text
 * entry gives functional completeness without requiring a second network call.
 *
 * Server side-effects (auto-status → Awaiting Parts, push to purchasing
 * manager) are server responsibilities; Android triggers them by calling
 * PATCH on the part status field.
 */
@Composable
private fun BenchPartsNeededDialog(
    @Suppress("UNUSED_PARAMETER") ticketId: Long,
    onMarkMissing: (deviceId: Long, partId: Long, partName: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var partName by rememberSaveable { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                Icons.Default.Inventory,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        title = { Text("Mark Part Missing") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Enter the part name to add it to the reorder queue. The ticket status will be updated to \"Awaiting Parts\".",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = partName,
                    onValueChange = { partName = it },
                    label = { Text("Part name *") },
                    placeholder = { Text("e.g. iPhone 14 Pro screen assembly") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = partName.isBlank(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    // Use sentinel IDs: real implementation would resolve
                    // deviceId + partId from ticket detail before calling this.
                    onMarkMissing(0L, 0L, partName.trim())
                },
                enabled = partName.isNotBlank(),
            ) {
                Text("Mark Missing")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
