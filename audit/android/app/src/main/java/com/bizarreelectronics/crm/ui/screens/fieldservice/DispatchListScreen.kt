package com.bizarreelectronics.crm.ui.screens.fieldservice

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.DispatchJobDetail
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DispatchListScreen(
    onNavigateBack: () -> Unit,
    /** Logged-in user ID — passed through to optimizeRoute so the server can look up home coords. */
    currentUserId: Long = -1L,
    viewModel: DispatchViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Toast messages
    LaunchedEffect(state.toastMessage) {
        if (state.toastMessage != null) {
            snackbarHostState.showSnackbar(state.toastMessage!!)
            viewModel.clearToast()
        }
    }

    // Cancel confirmation dialog
    if (state.pendingCancelJobId != null) {
        ConfirmDialog(
            title = "Cancel Job",
            message = "Are you sure you want to cancel this job? This cannot be undone.",
            confirmLabel = "Cancel Job",
            isDestructive = true,
            onConfirm = { viewModel.confirmCancelJob() },
            onDismiss = { viewModel.dismissCancelDialog() },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("My Jobs — Today") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // §59.2 Optimize Route — manager/admin only; server enforces 403 for techs.
                    // Shown as a spinning indicator while in flight.
                    if (state.isOptimizing) {
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .semantics { contentDescription = "Optimising route" },
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        }
                    } else {
                        IconButton(
                            onClick = { viewModel.optimizeRoute(technicianId = currentUserId) },
                            enabled = state.jobs.isNotEmpty() && !state.isLoading,
                            modifier = Modifier.semantics { contentDescription = "Optimize route" },
                        ) {
                            Icon(
                                Icons.Default.Route,
                                contentDescription = null,
                            )
                        }
                    }
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // §59.2 — Route optimisation result banner (dismissible)
            AnimatedVisibility(
                visible = state.optimizationBanner != null,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                state.optimizationBanner?.let { banner ->
                    OptimizationResultBanner(
                        banner = banner,
                        onDismiss = { viewModel.clearOptimizationBanner() },
                    )
                }
            }

        PullToRefreshBox(
            isRefreshing = state.isRefreshing,
            onRefresh = { viewModel.refresh() },
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                state.isLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(48.dp),
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(
                            state.error!!,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = { viewModel.load() }) { Text("Retry") }
                    }
                }
                state.jobs.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Text(
                                "No jobs scheduled for today",
                                style = MaterialTheme.typography.bodyLarge,
                            )
                        }
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(state.jobs, key = { it.id }) { job ->
                            DispatchJobCard(
                                job = job,
                                isTransitioning = state.transitioningJobId == job.id,
                                onAccept = { viewModel.acceptJob(job.id) },
                                onStart = { viewModel.startJob(job.id) },
                                onComplete = { viewModel.completeJob(job.id) },
                                onCancel = { viewModel.requestCancelJob(job.id) },
                            )
                        }
                    }
                }
            }
        }
        } // end Column
    }
}

// ─── §59.2 Optimisation result banner ────────────────────────────────────────

/**
 * Dismissible info banner shown after a successful route optimisation.
 *
 * Displays the estimated driving distance, whether home coords were used as the
 * route start, and the server algorithm note (greedy nearest-neighbor caveat).
 */
@Composable
private fun OptimizationResultBanner(
    banner: OptimizationBanner,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 2.dp,
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .semantics { contentDescription = "Route optimised" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Route,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSecondaryContainer,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Route optimised — ~${
                        String.format(Locale.US, "%.1f", banner.distanceKm)
                    } km",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    fontWeight = FontWeight.SemiBold,
                )
                if (banner.startFromHome) {
                    Text(
                        text = "Starting from your home location",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(32.dp),
            ) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Dismiss optimisation banner",
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

@Composable
private fun DispatchJobCard(
    job: DispatchJobDetail,
    isTransitioning: Boolean,
    onAccept: () -> Unit,
    onStart: () -> Unit,
    onComplete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val statusColor = statusColor(job.status)

    Card(
        modifier = modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {

            // — Status badge + priority ————————————————————————————————————
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StatusBadge(status = job.status, color = statusColor)
                if (job.priority != "normal") {
                    PriorityBadge(priority = job.priority)
                }
            }

            Spacer(Modifier.height(8.dp))

            // — Customer name ——————————————————————————————————————————————
            Text(
                text = job.customerFullName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            // — Address ————————————————————————————————————————————————————
            Text(
                text = job.fullAddress,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            // — Scheduled window ——————————————————————————————————————————
            val windowLabel = buildScheduleLabel(job.scheduledWindowStart, job.scheduledWindowEnd)
            if (windowLabel != null) {
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Schedule,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = windowLabel,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // — Notes (if any) ————————————————————————————————————————————
            if (!job.notes.isNullOrBlank()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = job.notes,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            // — Action buttons ————————————————————————————————————————————
            val isTerminal = job.status == DispatchJobStatus.COMPLETED ||
                job.status == DispatchJobStatus.CANCELED

            if (!isTerminal) {
                Spacer(Modifier.height(12.dp))
                HorizontalDivider()
                Spacer(Modifier.height(12.dp))

                if (isTransitioning) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    }
                } else {
                    JobActionButtons(
                        status = job.status,
                        onAccept = onAccept,
                        onStart = onStart,
                        onComplete = onComplete,
                        onCancel = onCancel,
                    )
                }
            }
        }
    }
}

@Composable
private fun JobActionButtons(
    status: String,
    onAccept: () -> Unit,
    onStart: () -> Unit,
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        when (status) {
            DispatchJobStatus.ASSIGNED -> {
                Button(
                    onClick = onAccept,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.DirectionsCar, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Accept / On my way")
                }
            }
            DispatchJobStatus.EN_ROUTE -> {
                Button(
                    onClick = onStart,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.PinDrop, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("I've Arrived")
                }
            }
            DispatchJobStatus.ON_SITE -> {
                Button(
                    onClick = onComplete,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.secondary,
                    ),
                ) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Complete Job")
                }
            }
        }

        // Cancel button (shown for assigned, en_route, on_site)
        if (status in listOf(
                DispatchJobStatus.ASSIGNED,
                DispatchJobStatus.EN_ROUTE,
                DispatchJobStatus.ON_SITE,
            )
        ) {
            OutlinedButton(
                onClick = onCancel,
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                Icon(Icons.Default.Cancel, contentDescription = null, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun StatusBadge(status: String, color: Color) {
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = color.copy(alpha = 0.15f),
    ) {
        Text(
            text = statusLabel(status),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun PriorityBadge(priority: String) {
    val (label, color) = when (priority) {
        "high"      -> "HIGH" to Color(0xFFF57C00)
        "emergency" -> "EMERGENCY" to Color(0xFFD32F2F)
        else        -> priority.uppercase() to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = color.copy(alpha = 0.12f),
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
            fontWeight = FontWeight.Bold,
        )
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

@Composable
private fun statusColor(status: String): Color = when (status) {
    DispatchJobStatus.UNASSIGNED -> MaterialTheme.colorScheme.onSurfaceVariant
    DispatchJobStatus.ASSIGNED   -> Color(0xFF1976D2)
    DispatchJobStatus.EN_ROUTE   -> Color(0xFF7B1FA2)
    DispatchJobStatus.ON_SITE    -> Color(0xFFF57C00)
    DispatchJobStatus.COMPLETED  -> Color(0xFF388E3C)
    DispatchJobStatus.CANCELED   -> MaterialTheme.colorScheme.error
    DispatchJobStatus.DEFERRED   -> MaterialTheme.colorScheme.onSurfaceVariant
    else                          -> MaterialTheme.colorScheme.onSurfaceVariant
}

private fun statusLabel(status: String): String = when (status) {
    DispatchJobStatus.UNASSIGNED -> "Unassigned"
    DispatchJobStatus.ASSIGNED   -> "Assigned"
    DispatchJobStatus.EN_ROUTE   -> "En Route"
    DispatchJobStatus.ON_SITE    -> "On Site"
    DispatchJobStatus.COMPLETED  -> "Completed"
    DispatchJobStatus.CANCELED   -> "Canceled"
    DispatchJobStatus.DEFERRED   -> "Deferred"
    else                          -> status.replaceFirstChar { it.uppercase() }
}

private fun buildScheduleLabel(start: String?, end: String?): String? {
    if (start.isNullOrBlank()) return null
    return try {
        val fmt = DateTimeFormatter.ISO_LOCAL_DATE_TIME
        val timeFmt = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
        val startDt = LocalDateTime.parse(start.replace(' ', 'T'))
        val startStr = startDt.format(timeFmt)
        if (!end.isNullOrBlank()) {
            val endDt = LocalDateTime.parse(end.replace(' ', 'T'))
            "$startStr – ${endDt.format(timeFmt)}"
        } else {
            startStr
        }
    } catch (_: Exception) {
        start
    }
}
