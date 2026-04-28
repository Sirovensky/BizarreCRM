package com.bizarreelectronics.crm.ui.screens.tickets

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
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
import com.bizarreelectronics.crm.R
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
import com.bizarreelectronics.crm.ui.screens.tickets.components.CustomerPreviewPopover
import com.bizarreelectronics.crm.ui.screens.tickets.components.ExportCsvMenuItem
import com.bizarreelectronics.crm.ui.screens.tickets.components.PinToggleMenuItem
import com.bizarreelectronics.crm.ui.screens.tickets.components.SlaHeatmapMenuItem
import com.bizarreelectronics.crm.ui.screens.tickets.components.PinnedTicketsHeader
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketColumnDensityPicker
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketColumnVisibility
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketFooterState
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketListFooter
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketLabelChips
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketRowBadges
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketBulkActionBar
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSavedViewSheet
import com.bizarreelectronics.crm.ui.screens.tickets.components.SlaChip
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSortDropdown
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketSwipeRow
import com.bizarreelectronics.crm.ui.screens.tickets.components.TicketUrgencyChip
import com.bizarreelectronics.crm.ui.screens.tickets.components.ticketUrgencyFor
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.ui.theme.SharedTicketElement
import com.bizarreelectronics.crm.ui.theme.sharedTicketKey
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.bizarreelectronics.crm.util.draggableItem
import com.bizarreelectronics.crm.util.dropTarget
import com.bizarreelectronics.crm.util.textClipData
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class, ExperimentalSharedTransitionApi::class)
@Composable
fun TicketListScreen(
    sharedTransitionScope: SharedTransitionScope,
    animatedContentScope: AnimatedContentScope,
    onTicketClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    // §3.14 L586 — empty-state secondary CTA. When non-null and the list is
    // empty (zero-data tenant), the EmptyStateIllustration shows a "Or
    // import from old system" link in addition to "Create your first
    // ticket". Default no-op so existing call-sites without the wiring
    // still compile + the secondary link just doesn't render.
    onImportFromOldSystem: () -> Unit = {},
    // §4.22 — Manager SLA heatmap entry point. Default no-op so existing
    // call-sites without the wiring (tests, previews) still compile cleanly.
    // The overflow menu item only renders when this callback is non-trivial
    // (always true when wired from AppNavGraph).
    onSlaHeatmapClick: () -> Unit = {},
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
    // Overflow menu (Export CSV etc.)
    var showOverflowMenu by remember { mutableStateOf(false) }
    // §4.1 L660 — Column / density picker (tablet/ChromeOS only)
    var showColumnPicker by remember { mutableStateOf(false) }
    // §4.21 — Bulk label picker dialog
    var showBulkLabelDialog by remember { mutableStateOf(false) }
    var bulkLabelInput by remember { mutableStateOf("") }

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
                            // Overflow menu — Export CSV (L652)
                            Box {
                                IconButton(onClick = { showOverflowMenu = true }) {
                                    Icon(Icons.Default.MoreVert, contentDescription = "More options")
                                }
                                DropdownMenu(
                                    expanded = showOverflowMenu,
                                    onDismissRequest = { showOverflowMenu = false },
                                ) {
                                    ExportCsvMenuItem(
                                        state = state,
                                        onDismiss = { showOverflowMenu = false },
                                    )
                                    // §4.22 — SLA heatmap entry point (manager surface).
                                    SlaHeatmapMenuItem(
                                        onDismiss = { showOverflowMenu = false },
                                        onClick = onSlaHeatmapClick,
                                    )
                                    // §4.1 L660 — Column picker (tablet/ChromeOS only)
                                    if (isExpandedWidth) {
                                        DropdownMenuItem(
                                            text = { Text("Columns") },
                                            leadingIcon = {
                                                Icon(
                                                    Icons.Default.ViewColumn,
                                                    contentDescription = null,
                                                )
                                            },
                                            onClick = {
                                                showOverflowMenu = false
                                                showColumnPicker = true
                                            },
                                        )
                                    }
                                }
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
        // Bulk action bar (L643 / §4.21) — bottom of screen in select mode
        bottomBar = {
            if (state.isSelecting && isExpandedWidth) {
                TicketBulkActionBar(
                    selectedCount = state.selectedIds.size,
                    onBulkAssign = { /* TODO(plan:L643): Bulk assign — needs employee picker */ },
                    onBulkStatus = { viewModel.onBulkStatusChange("Closed") },
                    onBulkArchive = { /* TODO(plan:L643): Bulk archive */ },
                    onBulkTag = {
                        bulkLabelInput = ""
                        showBulkLabelDialog = true
                    },
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
                placeholder = "Order ID, customer, IMEI…",
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

            // §4.21 — Active label filter chip
            if (state.activeLabelFilter != null) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TicketLabelChips(
                        labels = listOfNotNull(state.activeLabelFilter),
                        selectedLabel = state.activeLabelFilter,
                        onLabelClick = { viewModel.onLabelFilterChanged(null) },
                        onLabelRemove = { viewModel.onLabelFilterChanged(null) },
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

            // Pinned tickets header (L653)
            val pinnedTickets = remember(state.pinnedTicketIds, state.tickets) {
                state.tickets.filter { it.id in state.pinnedTicketIds }
            }
            PinnedTicketsHeader(
                pinnedTickets = pinnedTickets,
                onTicketClick = onTicketClick,
            )

            // Kanban placeholder (L644)
            if (state.viewMode == TicketViewMode.Kanban) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        // TODO(plan:L801): Implement tablet Kanban drag-drop to assign/status rail.
                        // Pattern: extend Leads Kanban (commit e3f5579) for Tickets.
                        // Drag a ticket row to the Assign rail → PUT /tickets/:id {assignedTo}.
                        // Drag a ticket row to a status column → PUT /tickets/:id {statusId}.
                        // Full implementation deferred: requires DragAndDropTarget + ReorderableLazyColumn.
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
                            // §3.14 L586 — zero-data tenant gets the rich
                            // EmptyStateIllustration (wrench emoji + "Create
                            // your first ticket" + "Or import from old
                            // system" link). Active search empty falls back
                            // to the simpler EmptyState because the tenant
                            // already has data — they just can't find a
                            // match.
                            if (state.searchQuery.isNotEmpty()) {
                                EmptyState(
                                    icon = Icons.Default.ConfirmationNumber,
                                    title = context.getString(R.string.tickets_empty_title),
                                    subtitle = "Try a different search",
                                )
                            } else {
                                com.bizarreelectronics.crm.ui.components.EmptyStateIllustration(
                                    emoji = "🔧",   // wrench
                                    title = context.getString(R.string.tickets_empty_title),
                                    subtitle = context.getString(R.string.tickets_empty_subtitle),
                                    primaryCta = "Create your first ticket",
                                    onPrimaryCta = onCreateClick,
                                    secondaryCta = "Or import from old system",
                                    onSecondaryCta = onImportFromOldSystem,
                                )
                            }
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

                        Column(modifier = Modifier.fillMaxSize()) {
                        // §22.8 — Assignee drop zone (tablet only).
                        // Visible when isExpandedWidth; accepts text/plain drops whose
                        // text is a ticket ID. Calls onAssignToMe (optimistic); full
                        // server-side assignment pending PUT /tickets/:id {assignedTo}.
                        // NOTE: drop zone shown always on tablet so users discover the
                        // target before initiating a drag. draggableItem on rows below
                        // starts the drag on long-press.
                        if (isExpandedWidth) {
                            AssigneeDropZone(
                                onTicketDropped = { ticketId ->
                                    viewModel.onAssignToMe(ticketId)
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 4.dp),
                            )
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
                                val isPinned = ticket.id in state.pinnedTicketIds

                                // M3 Expressive: animate row re-ordering on
                                // filter / sort / status-change. Respects the
                                // system reduce-motion flag via the row's own
                                // `reduceMotion` path.
                                androidx.compose.foundation.layout.Box(
                                    // §22.8 — draggableItem: long-press on a ticket row starts a
                                    // system drag-and-drop with the ticket's orderId as text payload.
                                    // The assignee drop zone above accepts drops of this format.
                                    // Phone rows are NOT affected (draggableItem's long-press
                                    // is on top of combinedClickable; on phone isExpandedWidth
                                    // is false so the zone is not rendered, making drops no-ops).
                                    modifier = Modifier
                                        .animateItem()
                                        .then(
                                            if (isExpandedWidth) {
                                                Modifier.draggableItem(
                                                    clipData = textClipData(
                                                        label = "ticket_id",
                                                        text = ticket.id.toString(),
                                                    ),
                                                )
                                            } else Modifier
                                        ),
                                ) {
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
                                        sharedTransitionScope = sharedTransitionScope,
                                        animatedContentScope = animatedContentScope,
                                        isSelected = isSelected,
                                        isSelecting = state.isSelecting,
                                        isExpandedWidth = isExpandedWidth,
                                        isPinned = isPinned,
                                        // §4.1 L660 — pass persisted column prefs; phone uses defaults (all on)
                                        columnVisibility = if (isExpandedWidth) state.columnVisibility else TicketColumnVisibility(),
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
                                                ContextMenuAction.Pin -> viewModel.togglePin(ticket.id)
                                            }
                                        },
                                        // §4.21 — Label chip tap → filter the list by that label
                                        onLabelFilterClick = { label ->
                                            viewModel.onLabelFilterChanged(
                                                if (state.activeLabelFilter == label) null else label
                                            )
                                        },
                                        activeLabelFilter = state.activeLabelFilter,
                                    )
                                }
                                BrandListItemDivider()
                                } // animateItem Box close
                            }

                            // 4-state footer
                            item(key = "ticket_list_footer") {
                                TicketListFooter(state = footerState)
                            }
                        }
                        } // Column (AssigneeDropZone + LazyColumn)
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

    // §4.1 L660 — Column / density picker sheet (tablet/ChromeOS)
    if (showColumnPicker) {
        TicketColumnDensityPicker(
            current = state.columnVisibility,
            onApply = { updated ->
                viewModel.onColumnVisibilityChanged(updated)
                showColumnPicker = false
            },
            onDismiss = { showColumnPicker = false },
        )
    }

    // §4.21 — Bulk label dialog: staff types a label name to apply to all selected tickets.
    if (showBulkLabelDialog) {
        AlertDialog(
            onDismissRequest = { showBulkLabelDialog = false; bulkLabelInput = "" },
            title = { Text("Apply label") },
            text = {
                OutlinedTextField(
                    value = bulkLabelInput,
                    onValueChange = { bulkLabelInput = it },
                    label = { Text("Label name") },
                    singleLine = true,
                    placeholder = { Text("e.g. urgent, VIP, warranty") },
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val label = bulkLabelInput.trim()
                        if (label.isNotBlank()) {
                            viewModel.bulkApplyLabel(label)
                            showBulkLabelDialog = false
                            bulkLabelInput = ""
                        }
                    },
                    enabled = bulkLabelInput.isNotBlank(),
                ) { Text("Apply") }
            },
            dismissButton = {
                TextButton(onClick = { showBulkLabelDialog = false; bulkLabelInput = "" }) {
                    Text("Cancel")
                }
            },
        )
    }
}

// -----------------------------------------------------------------------
// Context-menu actions
// -----------------------------------------------------------------------

private enum class ContextMenuAction {
    Open, Assign, MarkDone, CopyId, CopyLink, AddNote, Pin
}

// -----------------------------------------------------------------------
// TicketListRow — with urgency chip, context menu, multi-select checkbox
// -----------------------------------------------------------------------

@OptIn(ExperimentalFoundationApi::class, ExperimentalSharedTransitionApi::class)
@Composable
private fun TicketListRow(
    ticket: TicketEntity,
    sharedTransitionScope: SharedTransitionScope,
    animatedContentScope: AnimatedContentScope,
    isSelected: Boolean,
    isSelecting: Boolean,
    isExpandedWidth: Boolean,
    isPinned: Boolean,
    // §4.1 L660 — Column / density prefs. Defaults show assignee + device + urgency dot.
    columnVisibility: TicketColumnVisibility = TicketColumnVisibility(),
    onTicketClick: () -> Unit,
    onLongPress: () -> Unit,
    onContextMenuAction: (ContextMenuAction) -> Unit,
    // §4.21 — Label filter callback: tap a label chip to filter the list
    onLabelFilterClick: ((String) -> Unit)? = null,
    // §4.21 — Currently active label filter (for chip highlight)
    activeLabelFilter: String? = null,
) {
    var showContextMenu by remember { mutableStateOf(false) }
    // Customer preview popover (L654) — null means hidden
    var showCustomerPopover by remember { mutableStateOf(false) }

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
                    with(sharedTransitionScope) {
                    Text(
                        ticket.orderId,
                        style = BrandMono.copy(
                            fontSize = MaterialTheme.typography.titleSmall.fontSize,
                        ),
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.sharedElement(
                            sharedContentState = rememberSharedContentState(key = "ticket-${ticket.id}-orderid"),
                            animatedVisibilityScope = animatedContentScope,
                        ),
                    )
                    } // with(sharedTransitionScope)
                    Spacer(modifier = Modifier.width(6.dp))
                    // §4.1 L660 — Urgency chip gated on columnVisibility.showUrgencyDot
                    if (columnVisibility.showUrgencyDot) {
                        TicketUrgencyChip(urgency = urgency)
                    }
                    // Pin indicator (L653)
                    if (isPinned) {
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(
                            imageVector = Icons.Default.Star,
                            contentDescription = "Pinned",
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            },
            support = {
                // Customer name — tappable to show popover (L654)
                with(sharedTransitionScope) {
                Text(
                    ticket.customerName ?: "Unknown",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .sharedElement(
                            sharedContentState = rememberSharedContentState(key = "ticket-${ticket.id}-customer"),
                            animatedVisibilityScope = animatedContentScope,
                        )
                        .combinedClickable(
                            onClick = { showCustomerPopover = true },
                            onLongClick = {},
                        ),
                )
                } // with(sharedTransitionScope)
                // §4.1 L660 — Device name gated on columnVisibility.showDevice
                val deviceName = ticket.firstDeviceName
                if (!deviceName.isNullOrBlank() && columnVisibility.showDevice) {
                    Text(
                        deviceName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                // §4.1 L660 — Assignee ID badge gated on columnVisibility.showAssignee
                // Shows "Assigned" indicator when a tech is assigned; full name deferred until
                // TicketEntity is extended with an assignedToName denormalized column.
                if (columnVisibility.showAssignee && ticket.assignedTo != null) {
                    Text(
                        "Assigned #${ticket.assignedTo}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
                // §4.1 L660 — internalNote / diagnosticNote: columns reserved for future
                // TicketEntity extension; flags stored in prefs already, no UI output yet.
                // §4.21 — Label chips from comma-separated labels field
                val labelList = remember(ticket.labels) {
                    ticket.labels?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
                }
                if (labelList.isNotEmpty()) {
                    TicketLabelChips(
                        labels = labelList,
                        selectedLabel = activeLabelFilter,
                        onLabelClick = onLabelFilterClick,
                        modifier = Modifier.padding(top = 2.dp),
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
                            // §70.3 — STATUS_CHIP shared-element: the badge morphs
                            // into the TicketStatePill in the detail header row during
                            // the list→detail nav transition. Key is scoped to this
                            // ticket id so multiple rows never collide.
                            with(sharedTransitionScope) {
                                BrandStatusBadge(
                                    label = statusName,
                                    status = statusName,
                                    modifier = Modifier.sharedElement(
                                        sharedContentState = rememberSharedContentState(
                                            key = sharedTicketKey(ticket.id, SharedTicketElement.STATUS_CHIP),
                                        ),
                                        animatedVisibilityScope = animatedContentScope,
                                    ),
                                )
                            }
                        }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    // Age + due-date badges (L655)
                    TicketRowBadges(
                        createdAtStr = ticket.createdAt,
                        dueAtStr = ticket.dueOn,
                    )
                    // §4.22 — SLA chip: simple deadline-based tier from dueOn field.
                    // Full SLA tracking with pause/resume is §4.19 (deferred — needs server SLA defs).
                    val dueOnStr = ticket.dueOn
                    if (dueOnStr != null) {
                        val (slaTier, slaLabel) = remember(dueOnStr) {
                            val dueMs = runCatching {
                                java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
                                    .parse(dueOnStr)?.time ?: 0L
                            }.getOrDefault(0L)
                            val remainingMs = dueMs - System.currentTimeMillis()
                            val pct = if (dueMs > 0L) {
                                // Approximate 24h SLA budget for display only
                                val budgetMs = 24L * 60 * 60 * 1000
                                ((1.0 - remainingMs.toDouble() / budgetMs) * 100).toInt().coerceIn(0, 200)
                            } else 100
                            val tier = com.bizarreelectronics.crm.util.SlaCalculator.tier(100 - pct)
                            val label = com.bizarreelectronics.crm.ui.screens.tickets.components.formatSlaRemaining(remainingMs)
                            tier to label
                        }
                        Spacer(modifier = Modifier.height(2.dp))
                        SlaChip(tier = slaTier, label = slaLabel)
                    }
                    Spacer(modifier = Modifier.height(2.dp))
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
            // Standard actions (excluding Pin which gets its own component)
            ContextMenuAction.entries
                .filter { it != ContextMenuAction.Pin }
                .forEach { action ->
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
            // Pin toggle (L653)
            PinToggleMenuItem(
                isPinned = isPinned,
                onClick = {
                    showContextMenu = false
                    onContextMenuAction(ContextMenuAction.Pin)
                },
            )
        }

        // Customer preview popover (L654)
        if (showCustomerPopover && ticket.customerId != null) {
            // Build a lightweight CustomerEntity from ticket's denormalised fields
            // for the popover (full entity loaded via CustomerRepository in future iterations).
            val previewCustomer = remember(ticket.customerId) {
                com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity(
                    id = ticket.customerId,
                    firstName = ticket.customerName,
                    phone = ticket.customerPhone,
                    createdAt = ticket.createdAt,
                    updatedAt = ticket.updatedAt,
                )
            }
            CustomerPreviewPopover(
                customer = previewCustomer,
                recentTicketCount = 0, // full count fetched async in full implementation
                onDismiss = { showCustomerPopover = false },
            )
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
    ContextMenuAction.Pin      -> "Pin / Unpin"
}

@Composable
private fun contextMenuIcon(action: ContextMenuAction) = when (action) {
    ContextMenuAction.Open     -> Icons.Default.OpenInNew
    ContextMenuAction.Assign   -> Icons.Default.AssignmentInd
    ContextMenuAction.MarkDone -> Icons.Default.CheckCircle
    ContextMenuAction.CopyId   -> Icons.Default.ContentCopy
    ContextMenuAction.CopyLink -> Icons.Default.Link
    ContextMenuAction.AddNote  -> Icons.Default.Note
    ContextMenuAction.Pin      -> Icons.Default.Star
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

// -----------------------------------------------------------------------
// §22.8 — Assignee drop zone (tablet/desktop only)
// -----------------------------------------------------------------------

/**
 * A drop zone strip rendered above the ticket list on medium+ width screens.
 *
 * Accepts text/plain drops where the text is a ticket ID (Long string).
 * When a ticket row is dropped here, [onTicketDropped] is called with the
 * parsed ticket ID so the ViewModel can call `onAssignToMe`.
 *
 * NOTE(server): Full multi-user assignment (drop → pick-assignee dialog →
 * PUT /tickets/:id {assignedTo}) requires a staff-list endpoint and an
 * assignee picker sheet. Until that lands, drops always assign to the
 * currently logged-in user (same as swipe-right behaviour).
 */
@Composable
private fun AssigneeDropZone(
    onTicketDropped: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    var isHovered by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier
            .defaultMinSize(minHeight = 48.dp)
            .dropTarget(
                acceptedMimeTypes = listOf("text/plain"),
                onDrop = { clipData ->
                    val text = clipData.getItemAt(0)?.text?.toString() ?: return@dropTarget false
                    val ticketId = text.toLongOrNull() ?: return@dropTarget false
                    onTicketDropped(ticketId)
                    isHovered = false
                    true
                },
            ),
        shape = MaterialTheme.shapes.medium,
        color = if (isHovered) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerLow
        },
        tonalElevation = if (isHovered) 4.dp else 1.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.AssignmentInd,
                contentDescription = null,
                tint = if (isHovered) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = "Drop ticket here to assign to me",
                style = MaterialTheme.typography.labelMedium,
                color = if (isHovered) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
    }
}
