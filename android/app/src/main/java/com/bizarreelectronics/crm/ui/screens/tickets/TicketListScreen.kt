package com.bizarreelectronics.crm.ui.screens.tickets

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.paging.LoadState
import androidx.paging.compose.LazyPagingItems
import androidx.paging.compose.collectAsLazyPagingItems
import androidx.paging.compose.itemKey
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketFooterState
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketListFooter
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSavedViewSheet
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSortDropdown
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSwipeRow
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgencyChip
import com.bizarreelectronics.crm.ui.screens.tickets.components.ticketUrgencyFor
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TicketListScreen(
    onTicketClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: TicketListViewModel = hiltViewModel(),
    networkMonitor: NetworkMonitor? = null,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    // Paging3: collect the paged stream as LazyPagingItems
    val lazyPagingItems: LazyPagingItems<TicketEntity> = viewModel.ticketsPaged.collectAsLazyPagingItems()

    // Network state for offline footer
    val isOnline by (networkMonitor?.isOnline ?: kotlinx.coroutines.flow.flowOf(true))
        .collectAsState(initial = true)

    // TODO(plan:L637-ext): wire rememberReduceMotion(appPreferences) once AppPreferences is
    // injected into TicketListScreen via CompositionLocal or passed as a parameter.
    // For now defaults false (standard motion). The ReduceMotion utility is already
    // integrated in BizarreMotion / other screens.
    val reduceMotion = false

    // Window size for multi-select gate (L643) — gated on medium+ width (tablet/ChromeOS)
    val isExpandedWidth = isMediumOrExpandedWidth()

    // CROSS1: when ticket assignment feature is off (default), hide "My Tickets" chip.
    val filters = remember(state.assignmentEnabled) {
        if (state.assignmentEnabled) {
            listOf("All", "My Tickets", "Open", "In Progress", "Waiting", "Closed")
        } else {
            listOf("All", "Open", "In Progress", "Waiting", "Closed")
        }
    }
    val listState = rememberLazyListState()

    // Toast observer
    val toastMessage = state.toastMessage
    LaunchedEffect(toastMessage) {
        if (!toastMessage.isNullOrBlank()) {
            Toast.makeText(context, toastMessage, Toast.LENGTH_SHORT).show()
            viewModel.clearToast()
        }
    }

    // BackHandler: exit select mode on back press
    BackHandler(enabled = state.isSelecting) { viewModel.exitSelectMode() }

    // Saved views sheet
    var showSavedViewSheet by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            Column {
                BrandTopAppBar(
                    title = if (state.isSelecting) {
                        "${state.selectedIds.size} selected"
                    } else {
                        "Tickets"
                    },
                    navigationIcon = if (state.isSelecting) {
                        {
                            IconButton(onClick = { viewModel.exitSelectMode() }) {
                                Icon(Icons.Default.Close, contentDescription = "Exit selection")
                            }
                        }
                    } else null,
                    actions = {
                        if (!state.isSelecting) {
                            // Sort dropdown (L639)
                            TicketSortDropdown(
                                currentSort = state.currentSort,
                                onSortSelected = { viewModel.onSortChanged(it) },
                            )
                            // Saved views + overflow (L645)
                            IconButton(onClick = { showSavedViewSheet = true }) {
                                Icon(Icons.Default.BookmarkBorder, contentDescription = "Saved views")
                            }
                            IconButton(onClick = { viewModel.loadTickets() }) {
                                Icon(Icons.Default.Refresh, contentDescription = "Refresh tickets")
                            }
                        }
                    },
                )
                WaveDivider()
            }
        },
        floatingActionButton = {
            if (!state.isSelecting) {
                FloatingActionButton(
                    onClick = onCreateClick,
                    containerColor = MaterialTheme.colorScheme.primary,
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Create new ticket")
                }
            }
        },
        // Bulk action bar (L643) — bottom of screen in select mode
        bottomBar = {
            if (state.isSelecting && isExpandedWidth) {
                BulkActionBar(
                    selectedCount = state.selectedIds.size,
                    onBulkStatus = { viewModel.onBulkStatusChange("Closed") },
                    onExitSelect = { viewModel.exitSelectMode() },
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // Search bar
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search tickets...",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // List / Kanban segmented button (L644)
            TicketViewModeToggle(
                currentMode = state.viewMode,
                onModeChanged = { viewModel.onViewModeChanged(it) },
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 4.dp),
            )

            // Saved-view chip (if active) (L645)
            if (state.savedView != TicketSavedView.None) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    FilterChip(
                        selected = true,
                        onClick = { viewModel.onSavedViewSelected(TicketSavedView.None) },
                        label = { Text(state.savedView.label) },
                        trailingIcon = {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Clear saved view",
                                modifier = Modifier.size(16.dp),
                            )
                        },
                    )
                }
            }

            // a11y heading
            Text(
                "Status filter",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )

            // Filter chips + count pill
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LazyRow(
                    modifier = Modifier.weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(end = 24.dp),
                ) {
                    items(filters, key = { it }) { filter ->
                        val isSelected = state.selectedFilter == filter
                        FilterChip(
                            selected = isSelected,
                            onClick = { viewModel.onFilterChanged(filter) },
                            label = { Text(filter) },
                            modifier = Modifier.semantics {
                                role = Role.Tab
                                contentDescription = if (isSelected) {
                                    "$filter filter, selected"
                                } else {
                                    "$filter filter, not selected"
                                }
                            },
                        )
                    }
                }
                if (!state.isLoading && state.tickets.isNotEmpty()) {
                    val ticketCount = state.tickets.size
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.padding(start = 8.dp),
                    ) {
                        Text(
                            "$ticketCount",
                            modifier = Modifier
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                                .semantics {
                                    liveRegion = LiveRegionMode.Polite
                                    contentDescription = "$ticketCount tickets"
                                },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            // Kanban placeholder (L644)
            if (state.viewMode == TicketViewMode.Kanban) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Kanban view coming soon — use Leads for now.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                return@Column
            }

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading tickets"
                        },
                    ) {
                        BrandSkeleton(rows = 6, modifier = Modifier.padding(top = 8.dp))
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier.semantics {
                            liveRegion = LiveRegionMode.Assertive
                        },
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load tickets",
                            onRetry = { viewModel.loadTickets() },
                        )
                    }
                }
                state.tickets.isEmpty() -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        Box(modifier = Modifier.semantics(mergeDescendants = true) {}) {
                            EmptyState(
                                icon = Icons.Default.ConfirmationNumber,
                                title = "No tickets found",
                                subtitle = if (state.searchQuery.isNotEmpty()) {
                                    "Try a different search"
                                } else {
                                    "Create a ticket to get started"
                                },
                            )
                        }
                    }
                }
                else -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        // Derive footer state from Paging3 load states + offline signal
                        val footerState: TicketFooterState = run {
                            val appendState = lazyPagingItems.loadState.append
                            val cachedCount = lazyPagingItems.itemCount
                            when {
                                !isOnline && cachedCount > 0 -> {
                                    // Approximate hours since last sync — SyncState not directly
                                    // injected here; derive from state.tickets as best-effort.
                                    TicketFooterState.Offline(
                                        cachedCount = cachedCount,
                                        lastSyncedHoursAgo = 0L,
                                    )
                                }
                                appendState is LoadState.Loading -> TicketFooterState.Loading
                                appendState is LoadState.NotLoading && appendState.endOfPaginationReached ->
                                    TicketFooterState.EndOfList
                                else -> TicketFooterState.Partial(
                                    shown = cachedCount,
                                    approximateTotal = null,
                                )
                            }
                        }

                        LazyColumn(
                            state = listState,
                            contentPadding = PaddingValues(top = 8.dp, bottom = 80.dp),
                        ) {
                            // Paging3 items — filter + sort applied at VM/Room level
                            items(
                                count = lazyPagingItems.itemCount,
                                key = lazyPagingItems.itemKey { it.id },
                            ) { index ->
                                val ticket = lazyPagingItems[index] ?: return@items
                                // VM-side sort/filter still applies to the legacy
                                // state.tickets list (unchanged); paged list is raw.
                                val isSelected = ticket.id in state.selectedIds

                                TicketSwipeRow(
                                    ticket = ticket,
                                    reduceMotion = reduceMotion,
                                    onMarkDone = { viewModel.onMarkDone(ticket.id) },
                                    onReopen = { viewModel.onReopen(ticket.id) },
                                    onAssignToMe = { viewModel.onAssignToMe(ticket.id) },
                                    onHold = { viewModel.onHold(ticket.id) },
                                ) {
                                    TicketListRow(
                                        ticket = ticket,
                                        isSelected = isSelected,
                                        isSelecting = state.isSelecting,
                                        isExpandedWidth = isExpandedWidth,
                                        onTicketClick = {
                                            if (state.isSelecting) {
                                                viewModel.toggleSelection(ticket.id)
                                            } else {
                                                onTicketClick(ticket.id)
                                            }
                                        },
                                        onLongPress = {
                                            if (isExpandedWidth) {
                                                viewModel.enterSelectMode(ticket.id)
                                            }
                                        },
                                        onContextMenuAction = { action ->
                                            when (action) {
                                                ContextMenuAction.Open -> onTicketClick(ticket.id)
                                                ContextMenuAction.Assign -> viewModel.onContextAssign(ticket.id)
                                                ContextMenuAction.MarkDone -> viewModel.onMarkDone(ticket.id)
                                                ContextMenuAction.CopyId -> {
                                                    clipboard.setText(AnnotatedString(ticket.orderId))
                                                    Toast.makeText(context, "Copied ID: ${ticket.orderId}", Toast.LENGTH_SHORT).show()
                                                }
                                                ContextMenuAction.CopyLink -> {
                                                    val link = "bizarrecrm://tickets/${ticket.id}"
                                                    clipboard.setText(AnnotatedString(link))
                                                    Toast.makeText(context, "Copied link", Toast.LENGTH_SHORT).show()
                                                }
                                                ContextMenuAction.AddNote -> viewModel.onAddNote(ticket.id)
                                            }
                                        },
                                    )
                                }
                                BrandListItemDivider()
                            }

                            // 4-state footer
                            item(key = "ticket_list_footer") {
                                TicketListFooter(state = footerState)
                            }
                        }
                    }
                }
            }
        }
    }

    // Saved views bottom sheet (L645)
    if (showSavedViewSheet) {
        TicketSavedViewSheet(
            currentSavedView = state.savedView,
            onSavedViewSelected = { view ->
                viewModel.onSavedViewSelected(view)
                showSavedViewSheet = false
            },
            onDismiss = { showSavedViewSheet = false },
        )
    }
}

// -----------------------------------------------------------------------
// Context-menu actions
// -----------------------------------------------------------------------

private enum class ContextMenuAction {
    Open, Assign, MarkDone, CopyId, CopyLink, AddNote
}

// -----------------------------------------------------------------------
// TicketListRow — with urgency chip, context menu, multi-select checkbox
// -----------------------------------------------------------------------

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TicketListRow(
    ticket: TicketEntity,
    isSelected: Boolean,
    isSelecting: Boolean,
    isExpandedWidth: Boolean,
    onTicketClick: () -> Unit,
    onLongPress: () -> Unit,
    onContextMenuAction: (ContextMenuAction) -> Unit,
) {
    var showContextMenu by remember { mutableStateOf(false) }

    val statusLabel = ticket.statusName?.ifBlank { null }
    val deviceLabel = ticket.firstDeviceName?.ifBlank { null }
    val urgency = ticketUrgencyFor(ticket)
    val a11yDesc = buildString {
        append("Ticket ${ticket.orderId}")
        ticket.customerName?.let { append(", $it") }
        deviceLabel?.let { append(", $it") }
        statusLabel?.let { append(", status: $it") }
        append(", urgency: ${urgency.label}")
        append(", ${ticket.total.formatAsMoney()}")
        append(". Tap to open.")
    }

    Box {
        BrandListItem(
            modifier = Modifier
                .defaultMinSize(minHeight = 48.dp)
                .semantics { contentDescription = a11yDesc }
                .combinedClickable(
                    onClick = onTicketClick,
                    onLongClick = {
                        if (isExpandedWidth) {
                            onLongPress()
                        } else {
                            showContextMenu = true
                        }
                    },
                ),
            selected = isSelected,
            leading = if (isSelecting) {
                {
                    Checkbox(
                        checked = isSelected,
                        onCheckedChange = { onTicketClick() },
                    )
                }
            } else null,
            headline = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        ticket.orderId,
                        style = BrandMono.copy(
                            fontSize = MaterialTheme.typography.titleSmall.fontSize,
                        ),
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    // Urgency chip (L637)
                    TicketUrgencyChip(urgency = urgency)
                }
            },
            support = {
                Text(
                    ticket.customerName ?: "Unknown",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val deviceName = ticket.firstDeviceName
                if (!deviceName.isNullOrBlank()) {
                    Text(
                        deviceName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            trailing = {
                Column(horizontalAlignment = Alignment.End) {
                    val statusName = ticket.statusName ?: ""
                    if (statusName.isNotEmpty()) {
                        val group = ticketStatusGroupFor(ticket)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TicketGroupPill(group = group)
                            Spacer(modifier = Modifier.width(6.dp))
                            BrandStatusBadge(label = statusName, status = statusName)
                        }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        ticket.total.formatAsMoney(),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Medium,
                    )
                }
            },
            onClick = null, // click handled by combinedClickable on modifier above
        )

        // Context menu (L642) — long-press on phone, shown as DropdownMenu
        DropdownMenu(
            expanded = showContextMenu,
            onDismissRequest = { showContextMenu = false },
        ) {
            ContextMenuAction.entries.forEach { action ->
                DropdownMenuItem(
                    text = { Text(contextMenuLabel(action)) },
                    onClick = {
                        showContextMenu = false
                        onContextMenuAction(action)
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = contextMenuIcon(action),
                            contentDescription = null,
                        )
                    },
                )
            }
        }
    }
}

private fun contextMenuLabel(action: ContextMenuAction): String = when (action) {
    ContextMenuAction.Open     -> "Open"
    ContextMenuAction.Assign   -> "Assign to me"
    ContextMenuAction.MarkDone -> "Mark done"
    ContextMenuAction.CopyId   -> "Copy ID"
    ContextMenuAction.CopyLink -> "Copy link"
    ContextMenuAction.AddNote  -> "Add note…"
}

@Composable
private fun contextMenuIcon(action: ContextMenuAction) = when (action) {
    ContextMenuAction.Open     -> Icons.Default.OpenInNew
    ContextMenuAction.Assign   -> Icons.Default.AssignmentInd
    ContextMenuAction.MarkDone -> Icons.Default.CheckCircle
    ContextMenuAction.CopyId   -> Icons.Default.ContentCopy
    ContextMenuAction.CopyLink -> Icons.Default.Link
    ContextMenuAction.AddNote  -> Icons.Default.Note
}

// -----------------------------------------------------------------------
// Kanban / List view mode toggle (L644)
// -----------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TicketViewModeToggle(
    currentMode: TicketViewMode,
    onModeChanged: (TicketViewMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        TicketViewMode.entries.forEachIndexed { index, mode ->
            SegmentedButton(
                selected = currentMode == mode,
                onClick = { onModeChanged(mode) },
                shape = SegmentedButtonDefaults.itemShape(
                    index = index,
                    count = TicketViewMode.entries.size,
                ),
                label = {
                    Text(
                        text = if (mode == TicketViewMode.List) "List" else "Kanban",
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
                icon = {
                    Icon(
                        imageVector = if (mode == TicketViewMode.List) {
                            Icons.Default.ViewList
                        } else {
                            Icons.Default.ViewKanban
                        },
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
            )
        }
    }
}

// -----------------------------------------------------------------------
// Bulk action bar (L643 — tablet/ChromeOS only)
// -----------------------------------------------------------------------

@Composable
private fun BulkActionBar(
    selectedCount: Int,
    onBulkStatus: () -> Unit,
    onExitSelect: () -> Unit,
) {
    Surface(
        tonalElevation = 3.dp,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "$selectedCount selected",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )
            // Bulk status (only action exposed for now per spec)
            OutlinedButton(onClick = onBulkStatus) {
                Text("Mark done")
            }
            // Bulk assign / bulk delete — TODO per plan:L643
            TextButton(
                onClick = { /* TODO(plan:L643): Bulk assign — not yet wired */ },
                enabled = false,
            ) { Text("Assign…") }
            IconButton(onClick = onExitSelect) {
                Icon(Icons.Default.Close, contentDescription = "Exit selection")
            }
        }
    }
}

// -----------------------------------------------------------------------
// Ticket status group — same as before (internal helpers)
// -----------------------------------------------------------------------

/**
 * NOTE: The server-provided `ticket.statusColor` hex is intentionally NOT used
 * here — the rainbow parse has been replaced by the 5-hue StatusTone mapping
 * via [BrandStatusBadge]. The raw color field is left on the entity for
 * backward-compat (CROSS-PLATFORM: seed migration needed on server side).
 */
private enum class TicketStatusGroup(val label: String) {
    Complete("Complete"),
    Cancelled("Cancelled"),
    Waiting("Waiting"),
    InProgress("In Progress"),
}

private fun ticketStatusGroupFor(ticket: TicketEntity): TicketStatusGroup {
    val name = ticket.statusName?.trim()?.lowercase().orEmpty()
    val looksCancelled = name.contains("cancel") || name.contains("void")
    return when {
        looksCancelled -> TicketStatusGroup.Cancelled
        ticket.statusIsClosed -> TicketStatusGroup.Complete
        name.contains("waiting") -> TicketStatusGroup.Waiting
        else -> TicketStatusGroup.InProgress
    }
}

@Composable
private fun TicketGroupPill(group: TicketStatusGroup) {
    val extColors = LocalExtendedColors.current
    val textColor: Color = when (group) {
        TicketStatusGroup.Complete -> extColors.success
        TicketStatusGroup.Cancelled -> MaterialTheme.colorScheme.onSurfaceVariant
        TicketStatusGroup.Waiting -> MaterialTheme.colorScheme.tertiary
        TicketStatusGroup.InProgress -> MaterialTheme.colorScheme.primary
    }
    Surface(
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Text(
            text = group.label,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            fontWeight = FontWeight.Medium,
        )
    }
}
