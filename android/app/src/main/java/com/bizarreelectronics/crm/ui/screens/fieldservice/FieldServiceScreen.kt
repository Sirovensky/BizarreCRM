package com.bizarreelectronics.crm.ui.screens.fieldservice

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AltRoute
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.FieldServiceJobListData
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

/**
 * FieldServiceScreen — §59 Field-Service / Dispatch
 *
 * Full-screen dispatch dashboard for mobile technicians. Provides:
 * - §59.1 List view: today's jobs sorted by ETA + priority.
 * - §59.1 Map stub: NOTE-defer (maps-compose not in libs.versions.toml).
 * - §59.2 Route optimization trigger button.
 * - §59.3 "On my way" action (sends status → en_route; SMS to customer is
 *   a server-side side effect handled by server dispatch route).
 * - §59.4 Simplified job cards with "On my way", "Mark on-site", "Mark
 *   complete", "Cancel job" actions gated behind [ConfirmDialog].
 *
 * Geofence auto-arrived (§59.5) and offline queue (§59.6) and panic button
 * (§59.7) are NOTE-deferred — see inline comments.
 *
 * Location permission ([ACCESS_FINE_LOCATION]) is requested on screen entry
 * with a rationale dialog if denied once.
 *
 * @param onBack              Navigate back (pop the back stack).
 * @param onNavigateToTicket  Open TicketDetail for the associated ticket ID.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FieldServiceScreen(
    onBack: () -> Unit,
    onNavigateToTicket: (Long) -> Unit = {},
    viewModel: FieldServiceViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // ─── §59 ACCESS_FINE_LOCATION permission ─────────────────────────────────
    var showLocationRationale by rememberSaveable { mutableStateOf(false) }
    val locationPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) showLocationRationale = true
    }

    LaunchedEffect(Unit) {
        val hasPerm = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPerm) {
            locationPermLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    // Show snackbar messages from the ViewModel.
    LaunchedEffect(state.snackMessage) {
        state.snackMessage?.let { msg ->
            scope.launch { snackbarHostState.showSnackbar(msg) }
            viewModel.clearSnackMessage()
        }
    }

    if (showLocationRationale) {
        AlertDialog(
            onDismissRequest = { showLocationRationale = false },
            icon = {
                Icon(
                    Icons.Default.LocationOn,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
            },
            title = { Text(stringResource(R.string.field_service_location_rationale_title)) },
            text = { Text(stringResource(R.string.field_service_location_rationale_body)) },
            confirmButton = {
                TextButton(onClick = {
                    showLocationRationale = false
                    locationPermLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                }) {
                    Text(stringResource(R.string.field_service_location_grant))
                }
            },
            dismissButton = {
                TextButton(onClick = { showLocationRationale = false }) {
                    Text(stringResource(R.string.field_service_location_skip))
                }
            },
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.nav_field_service),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.action_back),
                        )
                    }
                },
                actions = {
                    // §59.2 — Route optimization button
                    IconButton(
                        onClick = { viewModel.optimizeRoute() },
                        enabled = !state.isOptimizing && state.jobs.isNotEmpty(),
                    ) {
                        Icon(
                            Icons.Default.AltRoute,
                            contentDescription = stringResource(R.string.field_service_optimize_route),
                        )
                    }
                    IconButton(onClick = { viewModel.loadJobs() }) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = stringResource(R.string.action_refresh),
                        )
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
                        icon = Icons.Default.Work,
                        title = stringResource(R.string.field_service_offline_title),
                        subtitle = stringResource(R.string.field_service_offline_subtitle),
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
                        message = state.error ?: "",
                        onRetry = { viewModel.loadJobs() },
                    )
                }
            }

            state.jobs.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Work,
                        title = stringResource(R.string.field_service_empty_title),
                        subtitle = stringResource(R.string.field_service_empty_subtitle),
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
                    // §59.1 Map view — NOTE-defer: maps-compose not in
                    // libs.versions.toml. Placeholder shown instead.
                    item {
                        MapViewStub(jobCount = state.jobs.size)
                    }

                    // §59.1 List view: jobs ranked by ETA + priority.
                    items(
                        items = state.jobs,
                        key = { it.id },
                    ) { job ->
                        DispatchJobCard(
                            job = job,
                            onEnRoute = { viewModel.markEnRoute(job.id) },
                            onMarkOnSite = { viewModel.markOnSite(job.id) },
                            onMarkComplete = { viewModel.markComplete(job.id) },
                            onCancelJob = { viewModel.cancelJob(job.id) },
                            onOpenTicket = { onNavigateToTicket(job.id) },
                        )
                    }
                }
            }
        }
    }
}

// ─── §59.1 Map view stub ──────────────────────────────────────────────────────

/**
 * Stub shown in place of the real map view.
 *
 * <!-- NOTE-defer: Map view deferred — com.google.maps.android:maps-compose is
 * not present in libs.versions.toml. Add maps-compose + maps-android-sdk to
 * libs.versions.toml and replace this composable with a real GoogleMap()
 * cluster showing tech location + open job markers. -->
 */
@Composable
private fun MapViewStub(jobCount: Int) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(160.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = MaterialTheme.shapes.medium,
        tonalElevation = 1.dp,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.Map,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = stringResource(R.string.field_service_map_stub, jobCount),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── §59.4 Dispatch job card ──────────────────────────────────────────────────

/**
 * A single dispatch job card showing job metadata and action chips.
 *
 * Uses [OutlinedCard] per M3-Expressive guidelines. Touch targets ≥ 48dp.
 * Confirm dialogs protect the "Mark on-site", "Mark complete", and "Cancel"
 * destructive/important actions.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DispatchJobCard(
    job: FieldServiceJobListData.DispatchJob,
    onEnRoute: () -> Unit,
    onMarkOnSite: () -> Unit,
    onMarkComplete: () -> Unit,
    onCancelJob: () -> Unit,
    onOpenTicket: () -> Unit,
) {
    var showOnSiteDialog by rememberSaveable { mutableStateOf(false) }
    var showCompleteDialog by rememberSaveable { mutableStateOf(false) }
    var showCancelDialog by rememberSaveable { mutableStateOf(false) }

    val currencyFmt = remember { NumberFormat.getCurrencyInstance(Locale.US) }

    OutlinedCard(
        onClick = onOpenTicket,
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // ── Header: order ID + status badge ──────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = job.orderId?.let { "#$it" } ?: "#${job.id}",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                    job.description?.takeIf { it.isNotBlank() }?.let { desc ->
                        Text(
                            text = desc,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                job.status?.let { status ->
                    Surface(
                        color = statusColor(status),
                        shape = MaterialTheme.shapes.small,
                        tonalElevation = 0.dp,
                    ) {
                        Text(
                            text = statusLabel(status),
                            style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        )
                    }
                }
            }

            // ── Customer + address ───────────────────────────────────────────
            ListItem(
                headlineContent = {
                    Text(
                        job.customerName ?: "Unknown customer",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                },
                supportingContent = job.address?.takeIf { it.isNotBlank() }?.let { addr ->
                    {
                        Text(
                            addr,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                leadingContent = {
                    Icon(
                        Icons.Default.LocationOn,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                modifier = Modifier.padding(horizontal = 0.dp),
            )

            // ── ETA + total ───────────────────────────────────────────────────
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                job.etaMinutes?.let { eta ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(
                            Icons.Default.Schedule,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = stringResource(R.string.field_service_eta_minutes, eta),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                job.totalCents?.takeIf { it > 0L }?.let { cents ->
                    Text(
                        text = currencyFmt.format(cents / 100.0),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ── Action chips ──────────────────────────────────────────────────
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // §59.3 On my way — no confirm needed (not destructive)
                if (job.status == "scheduled") {
                    FilledTonalButton(
                        onClick = onEnRoute,
                        modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                    ) {
                        Icon(
                            Icons.Default.DirectionsCar,
                            contentDescription = stringResource(R.string.field_service_action_en_route),
                            modifier = Modifier.padding(end = 4.dp),
                        )
                        Text(
                            text = stringResource(R.string.field_service_action_en_route),
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                    Spacer(Modifier.width(4.dp))
                }

                // §59.4 Mark on-site — confirm dialog
                if (job.status in listOf("scheduled", "en_route")) {
                    FilterChip(
                        selected = job.status == "on_site",
                        onClick = { showOnSiteDialog = true },
                        label = {
                            Text(
                                stringResource(R.string.field_service_action_on_site),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.LocationOn,
                                contentDescription = stringResource(R.string.field_service_action_on_site),
                            )
                        },
                        modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                    )
                }

                // §59.4 Mark complete — confirm dialog
                if (job.status in listOf("scheduled", "en_route", "on_site")) {
                    FilterChip(
                        selected = job.status == "completed",
                        onClick = { showCompleteDialog = true },
                        label = {
                            Text(
                                stringResource(R.string.field_service_action_complete),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = stringResource(R.string.field_service_action_complete),
                            )
                        },
                        modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                    )
                }

                // §59.4 Cancel job — confirm dialog (destructive)
                if (job.status !in listOf("completed", "cancelled")) {
                    FilterChip(
                        selected = false,
                        onClick = { showCancelDialog = true },
                        label = {
                            Text(
                                stringResource(R.string.field_service_action_cancel),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Cancel,
                                contentDescription = stringResource(R.string.field_service_action_cancel),
                            )
                        },
                        modifier = Modifier.defaultMinSize(minHeight = 48.dp),
                    )
                }
            }
        }
    }

    // ── Confirm dialogs ───────────────────────────────────────────────────────

    if (showOnSiteDialog) {
        ConfirmDialog(
            title = stringResource(R.string.field_service_confirm_on_site_title),
            message = stringResource(R.string.field_service_confirm_on_site_message),
            confirmLabel = stringResource(R.string.field_service_action_on_site),
            onConfirm = {
                onMarkOnSite()
                showOnSiteDialog = false
            },
            onDismiss = { showOnSiteDialog = false },
        )
    }

    if (showCompleteDialog) {
        ConfirmDialog(
            title = stringResource(R.string.field_service_confirm_complete_title),
            message = stringResource(R.string.field_service_confirm_complete_message),
            confirmLabel = stringResource(R.string.field_service_action_complete),
            onConfirm = {
                onMarkComplete()
                showCompleteDialog = false
            },
            onDismiss = { showCompleteDialog = false },
        )
    }

    if (showCancelDialog) {
        ConfirmDialog(
            title = stringResource(R.string.field_service_confirm_cancel_title),
            message = stringResource(R.string.field_service_confirm_cancel_message),
            confirmLabel = stringResource(R.string.field_service_action_cancel),
            onConfirm = {
                onCancelJob()
                showCancelDialog = false
            },
            onDismiss = { showCancelDialog = false },
            isDestructive = true,
        )
    }
}

// ─── Status helpers ───────────────────────────────────────────────────────────

@Composable
private fun statusColor(status: String) = when (status) {
    "en_route"  -> MaterialTheme.colorScheme.secondaryContainer
    "on_site"   -> MaterialTheme.colorScheme.primaryContainer
    "completed" -> MaterialTheme.colorScheme.tertiaryContainer
    "cancelled" -> MaterialTheme.colorScheme.errorContainer
    else        -> MaterialTheme.colorScheme.surfaceVariant
}

private fun statusLabel(status: String): String = when (status) {
    "scheduled" -> "Scheduled"
    "en_route"  -> "En route"
    "on_site"   -> "On site"
    "completed" -> "Completed"
    "cancelled" -> "Cancelled"
    else        -> status.replaceFirstChar { it.uppercase() }
}
