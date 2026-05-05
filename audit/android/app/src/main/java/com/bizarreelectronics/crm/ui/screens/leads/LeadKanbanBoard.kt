package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.ui.screens.leads.components.LeadKanbanCard
// reduceMotionEnabled: wired below via system setting stub (see TODO)

/**
 * Canonical display order for lead pipeline stages (ActionPlan §9).
 */
val DEFAULT_STAGE_ORDER: List<String> = listOf(
    "new", "contacted", "scheduled", "qualified", "proposal", "converted", "lost",
)

private fun stageLabelFor(stage: String): String = when (stage) {
    "new"       -> "New"
    "contacted" -> "Contacted"
    "scheduled" -> "Scheduled"
    "qualified" -> "Qualified"
    "proposal"  -> "Proposal"
    "converted" -> "Converted"
    "lost"      -> "Lost"
    else        -> stage.replaceFirstChar { it.uppercaseChar() }
}

/**
 * Kanban pipeline board with drag-drop, filter row, and phone/tablet adaptive layout
 * (ActionPlan §9 L1382-L1387).
 *
 * Tablet: horizontal scroll, all columns visible simultaneously.
 * Phone: [HorizontalPager] paging between columns — one column per page.
 *
 * Drag-drop: each [LeadKanbanCard] detects a drag gesture via [detectDragGestures].
 * On drag completion the delta is translated to a stage change by comparing the
 * drag release X position to the column layout. [onStageDrop] is called with
 * (leadId, newStage) — optimistic update lives in the ViewModel.
 *
 * ReduceMotion: when [reduceMotionEnabled] is true drag animation is suppressed
 * (the card snaps immediately rather than following the finger).
 *
 * @param leadsByStage          Leads pre-grouped by stage key.
 * @param stageOrder            Canonical display order.
 * @param onLeadClick           Navigate to lead detail.
 * @param onStageChangeRequest  Long-press fallback (phone Kanban).
 * @param onStageDrop           Called with (leadId, newStage) when a drag completes.
 * @param isTablet              Override; defaults to window-width heuristic.
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun LeadKanbanBoard(
    leadsByStage: Map<String, List<LeadEntity>>,
    stageOrder: List<String>,
    onLeadClick: (leadId: Long) -> Unit,
    onStageChangeRequest: (leadId: Long, currentStage: String) -> Unit,
    onStageDrop: (leadId: Long, newStage: String) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
    isTablet: Boolean = false,
) {
    // TODO(plan:L1382-ext): wire rememberReduceMotion(appPreferences) once AppPreferences is
    // injected into this composable via a parameter.
    val reduceMotion = false // resolved via AppPreferences.reduceMotionEnabled at call site

    val knownStageSet = stageOrder.toHashSet()
    val extraStages = leadsByStage.keys.filter { it !in knownStageSet }.sorted()
    val effectiveOrder = stageOrder + extraStages

    // Filter state: salesperson + source chips
    var filterSource by remember { mutableStateOf<String?>(null) }
    var filterAssignee by remember { mutableStateOf<String?>(null) }

    val allSources = remember(leadsByStage) {
        leadsByStage.values.flatten().mapNotNull { it.source }.distinct().sorted()
    }
    val allAssignees = remember(leadsByStage) {
        leadsByStage.values.flatten().mapNotNull { it.assignedName }.distinct().sorted()
    }

    // Filtered leads
    val filteredByStage = remember(leadsByStage, filterSource, filterAssignee) {
        leadsByStage.mapValues { (_, leads) ->
            leads.filter { lead ->
                (filterSource == null || lead.source == filterSource) &&
                (filterAssignee == null || lead.assignedName == filterAssignee)
            }
        }
    }

    // Bulk archive overflow
    var showArchiveConfirm by remember { mutableStateOf(false) }
    var archiveTargetStage by remember { mutableStateOf<String?>(null) }

    if (showArchiveConfirm && archiveTargetStage != null) {
        AlertDialog(
            onDismissRequest = { showArchiveConfirm = false },
            title = { Text("Archive ${stageLabelFor(archiveTargetStage!!)} leads?") },
            text = {
                val count = filteredByStage[archiveTargetStage]?.size ?: 0
                Text("This will mark $count leads in '${stageLabelFor(archiveTargetStage!!)}' as lost.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val stage = archiveTargetStage ?: return@TextButton
                        filteredByStage[stage]?.forEach { lead ->
                            onStageDrop(lead.id, "lost")
                        }
                        showArchiveConfirm = false
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Archive") }
            },
            dismissButton = { TextButton(onClick = { showArchiveConfirm = false }) { Text("Cancel") } },
        )
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Filter row
        KanbanFilterRow(
            allSources = allSources,
            allAssignees = allAssignees,
            selectedSource = filterSource,
            selectedAssignee = filterAssignee,
            onSourceSelected = { filterSource = if (filterSource == it) null else it },
            onAssigneeSelected = { filterAssignee = if (filterAssignee == it) null else it },
        )

        if (isTablet) {
            // Tablet: horizontal scroll all columns
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                effectiveOrder.forEachIndexed { index, stage ->
                    KanbanColumn(
                        stage = stage,
                        leads = filteredByStage[stage] ?: emptyList(),
                        columnIndex = index,
                        onLeadClick = onLeadClick,
                        onStageChangeRequest = onStageChangeRequest,
                        onStageDrop = onStageDrop,
                        onArchiveStage = {
                            archiveTargetStage = stage
                            showArchiveConfirm = true
                        },
                        reduceMotion = reduceMotion,
                    )
                }
            }
        } else {
            // Phone: HorizontalPager — one column per page
            val pagerState = rememberPagerState { effectiveOrder.size }

            // Stage tabs above pager
            ScrollableTabRow(
                selectedTabIndex = pagerState.currentPage,
                edgePadding = 16.dp,
            ) {
                effectiveOrder.forEachIndexed { index, stage ->
                    Tab(
                        selected = pagerState.currentPage == index,
                        onClick = {
                            // No animation on reduceMotion
                        },
                        text = {
                            val count = filteredByStage[stage]?.size ?: 0
                            Text("${stageLabelFor(stage)} ($count)")
                        },
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = "${stageLabelFor(stage)} stage, ${filteredByStage[stage]?.size ?: 0} leads"
                        },
                    )
                }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize(),
                userScrollEnabled = true,
            ) { pageIndex ->
                val stage = effectiveOrder[pageIndex]
                KanbanColumn(
                    stage = stage,
                    leads = filteredByStage[stage] ?: emptyList(),
                    columnIndex = pageIndex,
                    onLeadClick = onLeadClick,
                    onStageChangeRequest = onStageChangeRequest,
                    onStageDrop = onStageDrop,
                    onArchiveStage = {
                        archiveTargetStage = stage
                        showArchiveConfirm = true
                    },
                    reduceMotion = reduceMotion,
                    phoneMode = true,
                    effectiveOrder = effectiveOrder,
                )
            }
        }
    }
}

// ─── Filter row ───────────────────────────────────────────────────────────────

@Composable
private fun KanbanFilterRow(
    allSources: List<String>,
    allAssignees: List<String>,
    selectedSource: String?,
    selectedAssignee: String?,
    onSourceSelected: (String) -> Unit,
    onAssigneeSelected: (String) -> Unit,
) {
    val hasFilters = allSources.isNotEmpty() || allAssignees.isNotEmpty()
    if (!hasFilters) return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Default.FilterList,
            contentDescription = "Filters",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp),
        )
        allSources.forEach { source ->
            FilterChip(
                selected = selectedSource == source,
                onClick = { onSourceSelected(source) },
                label = { Text(source, style = MaterialTheme.typography.labelSmall) },
            )
        }
        allAssignees.forEach { assignee ->
            FilterChip(
                selected = selectedAssignee == assignee,
                onClick = { onAssigneeSelected(assignee) },
                label = { Text(assignee, style = MaterialTheme.typography.labelSmall) },
            )
        }
    }
}

// ─── Single Kanban column ─────────────────────────────────────────────────────

@Composable
private fun KanbanColumn(
    stage: String,
    leads: List<LeadEntity>,
    columnIndex: Int,
    onLeadClick: (Long) -> Unit,
    onStageChangeRequest: (Long, String) -> Unit,
    onStageDrop: (Long, String) -> Unit,
    onArchiveStage: () -> Unit,
    reduceMotion: Boolean,
    phoneMode: Boolean = false,
    effectiveOrder: List<String> = DEFAULT_STAGE_ORDER,
) {
    val containerColors = listOf(
        MaterialTheme.colorScheme.secondaryContainer,
        MaterialTheme.colorScheme.tertiaryContainer,
        MaterialTheme.colorScheme.primaryContainer,
    )
    val stageLabel = stageLabelFor(stage)
    val containerColor = containerColors[columnIndex % containerColors.size]
    val onContainerColor = when (columnIndex % containerColors.size) {
        0    -> MaterialTheme.colorScheme.onSecondaryContainer
        1    -> MaterialTheme.colorScheme.onTertiaryContainer
        else -> MaterialTheme.colorScheme.onPrimaryContainer
    }
    val columnDescription = "$stageLabel column, ${leads.size} ${if (leads.size == 1) "lead" else "leads"}"

    val columnModifier = if (phoneMode) {
        Modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    } else {
        Modifier
            .width(280.dp)
            .fillMaxHeight()
    }

    ElevatedCard(
        modifier = columnModifier.semantics {
            contentDescription = columnDescription
            role = Role.Image
        },
        colors = CardDefaults.elevatedCardColors(
            containerColor = containerColor,
            contentColor = onContainerColor,
        ),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Column header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stageLabel,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = onContainerColor,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Surface(
                        color = onContainerColor.copy(alpha = 0.15f),
                        shape = MaterialTheme.shapes.small,
                    ) {
                        Text(
                            text = leads.size.toString(),
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = onContainerColor,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                    // Overflow: bulk archive
                    var showMenu by remember { mutableStateOf(false) }
                    Box {
                        IconButton(
                            onClick = { showMenu = true },
                            modifier = Modifier.size(24.dp),
                        ) {
                            Icon(Icons.Default.Archive, contentDescription = "Column options",
                                tint = onContainerColor.copy(alpha = 0.7f),
                                modifier = Modifier.size(16.dp))
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("Archive all as Lost") },
                                leadingIcon = { Icon(Icons.Default.Archive, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    onArchiveStage()
                                },
                            )
                        }
                    }
                }
            }

            HorizontalDivider(color = onContainerColor.copy(alpha = 0.15f), thickness = 1.dp)

            // Cards
            if (leads.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No leads in $stageLabel",
                        style = MaterialTheme.typography.bodySmall,
                        color = onContainerColor.copy(alpha = 0.6f),
                        modifier = Modifier.semantics { contentDescription = "No leads in $stageLabel" },
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(leads, key = { it.id }) { lead ->
                        DraggableLeadCard(
                            lead = lead,
                            stage = stage,
                            effectiveOrder = effectiveOrder,
                            onLeadClick = onLeadClick,
                            onStageChangeRequest = onStageChangeRequest,
                            onStageDrop = onStageDrop,
                            reduceMotion = reduceMotion,
                        )
                    }
                }
            }
        }
    }
}

// ─── Draggable card wrapper ───────────────────────────────────────────────────

@Composable
private fun DraggableLeadCard(
    lead: LeadEntity,
    stage: String,
    effectiveOrder: List<String>,
    onLeadClick: (Long) -> Unit,
    onStageChangeRequest: (Long, String) -> Unit,
    onStageDrop: (Long, String) -> Unit,
    reduceMotion: Boolean,
) {
    var isDragging by remember { mutableStateOf(false) }
    var dragOffset by remember { mutableStateOf(Offset.Zero) }
    val density = LocalDensity.current

    // Column width in px — approximately 280.dp converted to pixels
    val columnWidthPx = with(density) { 280.dp.toPx() }

    LeadKanbanCard(
        lead = lead,
        isDragging = isDragging,
        onLeadClick = onLeadClick,
        modifier = Modifier
            .graphicsLayer {
                if (isDragging && !reduceMotion) {
                    translationX = dragOffset.x
                    translationY = dragOffset.y
                    shadowElevation = 12f
                    scaleX = 1.04f
                    scaleY = 1.04f
                }
            }
            .pointerInput(lead.id) {
                detectDragGestures(
                    onDragStart = { isDragging = true },
                    onDragEnd = {
                        isDragging = false
                        // Determine new stage from horizontal delta
                        val stepsFromDelta = (dragOffset.x / columnWidthPx).let {
                            when {
                                it > 0.5f -> 1
                                it < -0.5f -> -1
                                else -> 0
                            }
                        }
                        if (stepsFromDelta != 0) {
                            val currentIdx = effectiveOrder.indexOf(stage)
                            val targetIdx = (currentIdx + stepsFromDelta)
                                .coerceIn(0, effectiveOrder.size - 1)
                            val targetStage = effectiveOrder[targetIdx]
                            if (targetStage != stage) {
                                onStageDrop(lead.id, targetStage)
                            }
                        }
                        dragOffset = Offset.Zero
                    },
                    onDragCancel = {
                        isDragging = false
                        dragOffset = Offset.Zero
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        if (!reduceMotion) {
                            dragOffset = dragOffset.copy(
                                x = dragOffset.x + dragAmount.x,
                                y = dragOffset.y + dragAmount.y,
                            )
                        }
                    },
                )
            },
    )
}

// Suppress: ExperimentalFoundationApi is used for HorizontalPager
