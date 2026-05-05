package com.bizarreelectronics.crm.ui.screens.leads

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.statusToneFor
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadContextMenu
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadScoreIndicator
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadSort
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadSortDropdown
import com.bizarreelectronics.crm.ui.screens.leads.components.applySortOrder
import com.bizarreelectronics.crm.util.PhoneFormatter
import com.bizarreelectronics.crm.util.PhoneIntents
import kotlinx.coroutines.launch

private fun statusLabelFor(status: String?): String {
    if (status.isNullOrBlank()) return ""
    return LEAD_STATUSES.firstOrNull { it.key.equals(status, ignoreCase = true) }?.label ?: status
}

private data class LeadStatusMeta(val key: String, val label: String)

private val LEAD_STATUSES = listOf(
    LeadStatusMeta("new", "New"),
    LeadStatusMeta("contacted", "Contacted"),
    LeadStatusMeta("scheduled", "Scheduled"),
    LeadStatusMeta("qualified", "Qualified"),
    LeadStatusMeta("proposal", "Proposal"),
    LeadStatusMeta("converted", "Converted"),
    LeadStatusMeta("lost", "Lost"),
)

enum class ViewMode { LIST, KANBAN }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun LeadListScreen(
    onLeadClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    onConvertToCustomer: (Long) -> Unit = {},
    onScheduleAppointment: (Long) -> Unit = {},
    viewModel: LeadListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val filters = listOf(
        "All", "Open", "New", "Contacted", "Scheduled",
        "Qualified", "Proposal", "Converted", "Lost",
    )
    val listState = rememberLazyListState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val view = LocalView.current

    var viewMode by remember { mutableStateOf(ViewMode.LIST) }
    var showDeleteConfirm by rememberSaveable { mutableStateOf(false) }
    var pendingDeleteIds by rememberSaveable { mutableStateOf<Set<Long>>(emptySet()) }

    // Context-menu state
    var contextMenuLeadId by remember { mutableStateOf<Long?>(null) }
    var contextMenuLead by remember { mutableStateOf<LeadEntity?>(null) }

    // Preview popover state
    var previewLead by remember { mutableStateOf<LeadEntity?>(null) }

    val leadsByStage by remember(state.leads) {
        derivedStateOf { state.leads.groupBy { it.status ?: "new" } }
    }

    // Sorted leads for list view
    val sortedLeads by remember(state.leads, state.currentSort) {
        derivedStateOf { applySortOrder(state.leads, state.currentSort) }
    }

    // Bulk-delete confirm
    if (showDeleteConfirm && pendingDeleteIds.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = {
                showDeleteConfirm = false
                pendingDeleteIds = emptySet()
            },
            title = { Text("Delete ${pendingDeleteIds.size} leads?") },
            text = { Text("This will mark the selected leads as lost. This action can be reversed by changing each lead's status.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.bulkDelete(pendingDeleteIds)
                        val count = pendingDeleteIds.size
                        showDeleteConfirm = false
                        pendingDeleteIds = emptySet()
                        scope.launch {
                            val result = snackbarHostState.showSnackbar(
                                message = "$count leads deleted",
                                actionLabel = "Undo",
                                duration = SnackbarDuration.Short,
                            )
                            if (result == SnackbarResult.ActionPerformed) {
                                viewModel.undoBulkDelete()
                            }
                        }
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    pendingDeleteIds = emptySet()
                }) { Text("Cancel") }
            },
        )
    }

    // Preview popover
    if (previewLead != null) {
        LeadPreviewPopover(
            lead = previewLead!!,
            onDismiss = { previewLead = null },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        if (state.selectedLeadIds.isNotEmpty()) {
                            Text("${state.selectedLeadIds.size} selected")
                        } else {
                            Text("Leads")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
                    actions = {
                        if (state.selectedLeadIds.isNotEmpty()) {
                            // Bulk-action bar: only Delete for now
                            IconButton(
                                onClick = {
                                    pendingDeleteIds = state.selectedLeadIds
                                    showDeleteConfirm = true
                                },
                                modifier = Modifier.semantics { contentDescription = "Delete selected leads" },
                            ) {
                                Icon(
                                    Icons.Default.Delete,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error,
                                )
                            }
                            IconButton(
                                onClick = { viewModel.clearSelection() },
                                modifier = Modifier.semantics { contentDescription = "Clear selection" },
                            ) {
                                Icon(Icons.Default.Close, contentDescription = null)
                            }
                        } else {
                            LeadSortDropdown(
                                currentSort = state.currentSort,
                                onSortSelected = { viewModel.onSortChanged(it) },
                            )
                            IconButton(
                                onClick = { viewMode = ViewMode.LIST },
                                modifier = Modifier.semantics {
                                    role = Role.Button
                                    contentDescription = if (viewMode == ViewMode.LIST)
                                        "List view, selected" else "List view, not selected"
                                },
                            ) {
                                Icon(
                                    Icons.Default.ViewList,
                                    contentDescription = null,
                                    tint = if (viewMode == ViewMode.LIST)
                                        MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            IconButton(
                                onClick = { viewMode = ViewMode.KANBAN },
                                modifier = Modifier.semantics {
                                    role = Role.Button
                                    contentDescription = if (viewMode == ViewMode.KANBAN)
                                        "Kanban view, selected" else "Kanban view, not selected"
                                },
                            ) {
                                Icon(
                                    Icons.Default.ViewKanban,
                                    contentDescription = null,
                                    tint = if (viewMode == ViewMode.KANBAN)
                                        MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            IconButton(onClick = { viewModel.loadLeads() }) {
                                Icon(
                                    Icons.Default.Refresh,
                                    contentDescription = "Refresh leads",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    },
                )
                WaveDivider()
            }
        },
        floatingActionButton = {
            if (state.selectedLeadIds.isEmpty()) {
                FloatingActionButton(
                    onClick = onCreateClick,
                    containerColor = MaterialTheme.colorScheme.primary,
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Create new lead")
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            com.bizarreelectronics.crm.ui.components.shared.SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search leads...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            Text(
                "Status filter",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filters, key = { it }) { filter ->
                    val isSelected = state.selectedStatus == filter
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onStatusChanged(filter) },
                        label = { Text(filter) },
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) "$filter filter, selected"
                            else "$filter filter, not selected"
                        },
                    )
                }
            }

            if (!state.isLoading && state.leads.isNotEmpty()) {
                val leadCount = state.leads.size
                val countLabel = "$leadCount ${if (leadCount == 1) "lead" else "leads"}"
                Text(
                    countLabel,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 4.dp)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = countLabel
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    Box(modifier = Modifier.semantics(mergeDescendants = true) {
                        contentDescription = "Loading leads"
                    }) {
                        BrandSkeleton(rows = 6, modifier = Modifier.padding(horizontal = 16.dp))
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Error loading leads",
                            onRetry = { viewModel.loadLeads() },
                        )
                    }
                }
                state.leads.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.PersonSearch,
                            title = "No leads found",
                            subtitle = "Add a lead with the + button below",
                        )
                    }
                }
                viewMode == ViewMode.KANBAN -> {
                    LeadKanbanBoard(
                        leadsByStage = leadsByStage,
                        stageOrder = DEFAULT_STAGE_ORDER,
                        onLeadClick = onLeadClick,
                        onStageChangeRequest = { leadId, _ ->
                            contextMenuLeadId = leadId
                            contextMenuLead = state.leads.firstOrNull { it.id == leadId }
                        },
                        onStageDrop = { leadId, newStage -> viewModel.advanceStage(leadId, newStage) },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                else -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            state = listState,
                            contentPadding = PaddingValues(
                                start = 16.dp, end = 16.dp,
                                top = 8.dp, bottom = 80.dp,
                            ),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(sortedLeads, key = { it.id }) { lead ->
                                val isSelected = lead.id in state.selectedLeadIds
                                var showContextMenu by remember { mutableStateOf(false) }

                                LeadSwipeRow(
                                    lead = lead,
                                    onAdvanceStage = { viewModel.advanceStage(lead.id, nextStageFor(lead.status)) },
                                    onDropStage = { viewModel.dropStage(lead.id, prevStageFor(lead.status)) },
                                ) {
                                    Box {
                                        LeadCard(
                                            lead = lead,
                                            isSelected = isSelected,
                                            onClick = {
                                                if (state.selectedLeadIds.isNotEmpty()) {
                                                    viewModel.toggleSelection(lead.id)
                                                } else {
                                                    onLeadClick(lead.id)
                                                }
                                            },
                                            onLongClick = {
                                                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                                                if (state.selectedLeadIds.isEmpty()) {
                                                    showContextMenu = true
                                                } else {
                                                    viewModel.toggleSelection(lead.id)
                                                }
                                            },
                                            onAvatarClick = { previewLead = lead },
                                        )
                                        LeadContextMenu(
                                            expanded = showContextMenu,
                                            onDismiss = { showContextMenu = false },
                                            onOpen = { onLeadClick(lead.id) },
                                            onCall = {
                                                lead.phone?.let { PhoneIntents.call(context, it) }
                                            },
                                            onSms = {
                                                lead.phone?.let { PhoneIntents.sms(context, it) }
                                            },
                                            onEmail = {
                                                lead.email?.let { PhoneIntents.email(context, it) }
                                            },
                                            onConvertToCustomer = { onConvertToCustomer(lead.id) },
                                            onScheduleAppointment = { onScheduleAppointment(lead.id) },
                                            onDelete = {
                                                pendingDeleteIds = setOf(lead.id)
                                                showDeleteConfirm = true
                                            },
                                            hasPhone = !lead.phone.isNullOrBlank(),
                                            hasEmail = !lead.email.isNullOrBlank(),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Swipe row ────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun LeadSwipeRow(
    lead: LeadEntity,
    onAdvanceStage: () -> Unit,
    onDropStage: () -> Unit,
    content: @Composable () -> Unit,
) {
    val view = LocalView.current

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    onAdvanceStage()
                    false
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    onDropStage()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
        positionalThreshold = { totalDistance -> totalDistance * 0.35f },
    )

    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue != SwipeToDismissBoxValue.Settled) {
            dismissState.reset()
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            val scheme = MaterialTheme.colorScheme
            when (direction) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(scheme.primaryContainer)
                            .padding(start = 20.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.ArrowForward, contentDescription = null,
                                tint = scheme.onPrimaryContainer)
                            Spacer(Modifier.width(4.dp))
                            Text("Advance stage", color = scheme.onPrimaryContainer,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(scheme.errorContainer)
                            .padding(end = 20.dp),
                        contentAlignment = Alignment.CenterEnd,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Drop stage", color = scheme.onErrorContainer,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.Default.ArrowBack, contentDescription = null,
                                tint = scheme.onErrorContainer)
                        }
                    }
                }
                SwipeToDismissBoxValue.Settled -> {
                    Box(modifier = Modifier.fillMaxSize()
                        .background(MaterialTheme.colorScheme.surface))
                }
            }
        },
        content = { content() },
    )
}

// ─── Lead list card ───────────────────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LeadCard(
    lead: LeadEntity,
    isSelected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onAvatarClick: () -> Unit,
) {
    val fullName = listOfNotNull(lead.firstName, lead.lastName)
        .joinToString(" ").ifBlank { "Unknown" }
    val stageLabel = statusLabelFor(lead.status).ifBlank { lead.status ?: "Unknown" }
    val a11yDesc = buildString {
        append("Lead $fullName")
        lead.phone?.takeIf { it.isNotBlank() }?.let { append(", phone ${PhoneFormatter.format(it)}") }
        append(", stage $stageLabel")
        append(", score ${lead.leadScore}")
        lead.source?.takeIf { it.isNotBlank() }?.let { append(", source $it") }
        append(". Tap to open.")
    }

    val containerColor = if (isSelected)
        MaterialTheme.colorScheme.primaryContainer
    else
        MaterialTheme.colorScheme.surface

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics(mergeDescendants = true) { contentDescription = a11yDesc },
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Row(
            modifier = Modifier
                .padding(12.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Avatar / score ring — tap triggers preview popover
            LeadScoreIndicator(
                score = lead.leadScore,
                size = 44.dp,
                modifier = Modifier
                    .combinedClickable(onClick = onAvatarClick)
                    .semantics { contentDescription = "Score ${lead.leadScore}. Tap for preview." },
            )

            // Main content
            Column(modifier = Modifier.weight(1f)) {
                if (!lead.orderId.isNullOrBlank()) {
                    Text(
                        lead.orderId,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    fullName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (!lead.phone.isNullOrBlank()) {
                    Text(
                        PhoneFormatter.format(lead.phone),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!lead.email.isNullOrBlank()) {
                    Text(
                        lead.email,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!lead.source.isNullOrBlank()) {
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        "Source: ${lead.source}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Right column: status + value
            Column(horizontalAlignment = Alignment.End) {
                BrandStatusBadge(
                    label = stageLabel,
                    status = lead.status ?: "",
                )
                if (lead.leadScore > 0) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Score ${lead.leadScore}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// ─── Lead preview popover ─────────────────────────────────────────────────────

@Composable
private fun LeadPreviewPopover(lead: LeadEntity, onDismiss: () -> Unit) {
    val fullName = listOfNotNull(lead.firstName, lead.lastName).joinToString(" ").ifBlank { "Unknown" }

    LaunchedEffect(lead.id) {
        kotlinx.coroutines.delay(3_000L)
        onDismiss()
    }

    androidx.compose.ui.window.Popup(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.PopupProperties(focusable = true),
    ) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            shadowElevation = 8.dp,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier
                .width(260.dp)
                .semantics { contentDescription = "Lead preview for $fullName" },
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    LeadScoreIndicator(score = lead.leadScore, size = 40.dp)
                    Column {
                        Text(fullName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        if (!lead.phone.isNullOrBlank()) {
                            Text(PhoneFormatter.format(lead.phone), style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                if (!lead.source.isNullOrBlank()) {
                    Text("Source: ${lead.source}", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                val statusLabel = statusLabelFor(lead.status).ifBlank { lead.status ?: "" }
                if (statusLabel.isNotBlank()) {
                    BrandStatusBadge(label = statusLabel, status = lead.status ?: "")
                }
            }
        }
    }
}

// ─── Stage navigation helpers ─────────────────────────────────────────────────

private fun nextStageFor(current: String?): String {
    val stages = DEFAULT_STAGE_ORDER
    val idx = stages.indexOf(current?.lowercase())
    return if (idx in 0 until stages.size - 1) stages[idx + 1] else current ?: stages.first()
}

private fun prevStageFor(current: String?): String {
    val stages = DEFAULT_STAGE_ORDER
    val idx = stages.indexOf(current?.lowercase())
    return if (idx > 0) stages[idx - 1] else current ?: stages.first()
}
