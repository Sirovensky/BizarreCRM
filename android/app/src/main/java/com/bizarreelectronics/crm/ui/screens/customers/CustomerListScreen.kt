package com.bizarreelectronics.crm.ui.screens.customers

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.paging.LoadState
import androidx.paging.compose.collectAsLazyPagingItems
import androidx.paging.compose.itemKey
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.CustomerAvatar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerAZIndex
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilter
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilterSheet
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerSort
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerSortDropdown
import com.bizarreelectronics.crm.ui.screens.customers.components.ImportedContact
import com.bizarreelectronics.crm.ui.screens.customers.components.rememberCustomerContactImport
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CustomerListScreen(
    onCustomerClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    onCreateClickWithContact: ((ImportedContact) -> Unit)? = null,
    viewModel: CustomerListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val lazyPagingItems = viewModel.customersPaged.collectAsLazyPagingItems()
    val listState = rememberLazyListState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // ── Snackbar ──────────────────────────────────────────────────────────────
    LaunchedEffect(state.snackbarMessage) {
        val msg = state.snackbarMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSnackbar()
        }
    }

    // ── Export CSV via SAF (plan:L884) ────────────────────────────────────────
    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri ->
        if (uri != null) {
            val csv = viewModel.buildCsvContent()
            context.contentResolver.openOutputStream(uri)?.use { out ->
                out.write(csv.toByteArray())
            }
        }
    }

    // ── Contact import (plan:L886) ────────────────────────────────────────────
    val launchContactImport = rememberCustomerContactImport { contact ->
        onCreateClickWithContact?.invoke(contact) ?: onCreateClick()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = if (state.isBulkMode) "${state.selectedIds.size} selected" else "Customers",
                navigationIcon = if (state.isBulkMode) ({
                    IconButton(onClick = { viewModel.clearBulkSelection() }) {
                        Icon(Icons.Default.Close, contentDescription = "Cancel selection")
                    }
                }) else null,
                actions = {
                    if (!state.isBulkMode) {
                        // Sort
                        CustomerSortDropdown(
                            currentSort = state.currentSort,
                            onSortSelected = viewModel::onSortSelected,
                        )
                        // Filter
                        IconButton(onClick = viewModel::showFilterSheet) {
                            Icon(
                                Icons.Default.FilterList,
                                contentDescription = "Filter customers",
                                tint = if (state.currentFilter != CustomerFilter()) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        }
                        // Import from contacts
                        IconButton(onClick = { launchContactImport() }) {
                            Icon(
                                Icons.Default.Contacts,
                                contentDescription = "Import from contacts",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        // Export CSV
                        IconButton(onClick = {
                            exportLauncher.launch("customers_export.csv")
                        }) {
                            Icon(
                                Icons.Default.Download,
                                contentDescription = "Export customers CSV",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        // Refresh
                        IconButton(onClick = { viewModel.refresh(); lazyPagingItems.refresh() }) {
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "Refresh customers",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            if (!state.isBulkMode) {
                FloatingActionButton(
                    onClick = onCreateClick,
                    containerColor = MaterialTheme.colorScheme.primary,
                ) {
                    Icon(Icons.Default.PersonAdd, contentDescription = "Create new customer")
                }
            }
        },
        bottomBar = {
            if (state.isBulkMode) {
                BulkActionBar(
                    selectedCount = state.selectedIds.size,
                    onTag = { viewModel.onBulkTag("VIP") },
                    onDelete = { viewModel.onBulkDelete() },
                    onCancel = { viewModel.clearBulkSelection() },
                )
            }
        },
    ) { padding ->

        // Filter sheet
        if (state.showFilterSheet) {
            CustomerFilterSheet(
                filter = state.currentFilter,
                onFilterChange = viewModel::onFilterChanged,
                onDismiss = viewModel::dismissFilterSheet,
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search customers...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // Stats header (plan:L880)
            state.stats?.let { stats ->
                CustomerStatsHeader(stats = stats)
            }

            // Paging list with A-Z index overlay
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val isTablet = maxWidth >= 600.dp

                Box(modifier = Modifier.fillMaxSize()) {
                    CustomerPagingList(
                        lazyPagingItems = lazyPagingItems,
                        listState = listState,
                        state = state,
                        isTablet = isTablet,
                        onCustomerClick = onCustomerClick,
                        onLongPress = viewModel::onLongPress,
                        onToggleSelect = viewModel::onToggleSelect,
                        onSms = { phone ->
                            context.startActivity(
                                Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
                            )
                        },
                        onCall = { phone ->
                            context.startActivity(
                                Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
                            )
                        },
                        onMarkVip = viewModel::onMarkVip,
                        onArchive = viewModel::onArchive,
                        onCreateTicket = { /* navigate — future wiring */ },
                    )

                    // A-Z fast-scroller on the right edge (phone only, plan:L879)
                    if (!isTablet) {
                        CustomerAZIndex(
                            modifier = Modifier
                                .align(Alignment.CenterEnd)
                                .padding(end = 2.dp),
                            onLetterSelected = { letter ->
                                scope.launch {
                                    val snapshot = lazyPagingItems.itemSnapshotList
                                    val idx = snapshot.indexOfFirst { customer ->
                                        val name = customer?.firstName ?: customer?.lastName ?: "#"
                                        if (letter == "#") {
                                            name.firstOrNull()?.isLetter() == false
                                        } else {
                                            name.uppercase().startsWith(letter)
                                        }
                                    }
                                    if (idx >= 0) listState.animateScrollToItem(idx)
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

// ─── Stats header (plan:L880) ─────────────────────────────────────────────────

@Composable
private fun CustomerStatsHeader(stats: com.bizarreelectronics.crm.data.remote.dto.CustomerStats) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        StatTile("Total", stats.total.toString())
        StatTile("VIPs", stats.vips.toString())
        StatTile("At-Risk", stats.atRisk.toString())
        StatTile("Avg LTV", "$${stats.avgLtv.toLong()}")
    }
}

@Composable
private fun StatTile(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            value,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ─── Paging list ─────────────────────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun CustomerPagingList(
    lazyPagingItems: androidx.paging.compose.LazyPagingItems<CustomerEntity>,
    listState: androidx.compose.foundation.lazy.LazyListState,
    state: CustomerListUiState,
    isTablet: Boolean,
    onCustomerClick: (Long) -> Unit,
    onLongPress: (Long) -> Unit,
    onToggleSelect: (Long) -> Unit,
    onSms: (String) -> Unit,
    onCall: (String) -> Unit,
    onMarkVip: (Long) -> Unit,
    onArchive: (Long) -> Unit,
    onCreateTicket: (Long) -> Unit,
) {
    when (lazyPagingItems.loadState.refresh) {
        is LoadState.Loading -> {
            Box(
                modifier = Modifier.semantics(mergeDescendants = true) {
                    contentDescription = "Loading customers"
                },
            ) {
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = 8.dp),
                )
            }
            return
        }
        is LoadState.Error -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                ErrorState(
                    message = "Failed to load customers. Check your connection and try again.",
                    onRetry = { lazyPagingItems.refresh() },
                )
            }
            return
        }
        else -> Unit
    }

    if (lazyPagingItems.itemCount == 0 &&
        lazyPagingItems.loadState.refresh !is LoadState.Loading
    ) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            EmptyState(
                icon = Icons.Default.Add,
                title = "No customers yet.",
                subtitle = "Tap + to create one, or import from Contacts.",
            )
        }
        return
    }

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 96.dp),
    ) {
        items(
            count = lazyPagingItems.itemCount,
            key = lazyPagingItems.itemKey { it.id },
        ) { index ->
            val customer = lazyPagingItems[index] ?: return@items
            val isSelected = customer.id in state.selectedIds

            // M3 Expressive: animate row re-order on filter / sort /
            // archive-toggle using `Modifier.animateItem()`.
            Box(modifier = Modifier.animateItem()) {
                CustomerSwipeRow(
                    customer = customer,
                    onSms = { onSms(customer.mobile ?: customer.phone ?: "") },
                    onCall = { onCall(customer.mobile ?: customer.phone ?: "") },
                    onMarkVip = { onMarkVip(customer.id) },
                    onArchive = { onArchive(customer.id) },
                ) {
                    CustomerContextMenuRow(
                        customer = customer,
                        isSelected = isSelected,
                        isBulkMode = state.isBulkMode,
                        isTablet = isTablet,
                        onClick = {
                            if (state.isBulkMode) onToggleSelect(customer.id)
                            else onCustomerClick(customer.id)
                        },
                        onLongPress = { onLongPress(customer.id) },
                        onCreateTicket = { onCreateTicket(customer.id) },
                    )
                }
                BrandListItemDivider()
            }
        }

        // Append loading indicator
        if (lazyPagingItems.loadState.append is LoadState.Loading) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp))
                }
            }
        }
    }
}

// ─── Swipe row (plan:L877) ────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomerSwipeRow(
    customer: CustomerEntity,
    onSms: () -> Unit,
    onCall: () -> Unit,
    onMarkVip: () -> Unit,
    onArchive: () -> Unit,
    content: @Composable () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    val phone = customer.mobile ?: customer.phone
                    if (phone != null) onSms() else onCall()
                    false
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    onMarkVip()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
        positionalThreshold = { total -> total * 0.35f },
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
            val (bg, label) = when (direction) {
                SwipeToDismissBoxValue.StartToEnd ->
                    scheme.secondary to "SMS"
                SwipeToDismissBoxValue.EndToStart ->
                    scheme.primary to "VIP"
                else -> scheme.surface to ""
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp),
                contentAlignment = when (direction) {
                    SwipeToDismissBoxValue.StartToEnd -> Alignment.CenterStart
                    else -> Alignment.CenterEnd
                },
            ) {
                if (label.isNotBlank()) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelMedium,
                        color = scheme.onPrimary,
                    )
                }
            }
        },
        content = { content() },
    )
}

// ─── Context menu row (plan:L878) ─────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CustomerContextMenuRow(
    customer: CustomerEntity,
    isSelected: Boolean,
    isBulkMode: Boolean,
    isTablet: Boolean,
    onClick: () -> Unit,
    onLongPress: () -> Unit,
    onCreateTicket: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    val context = LocalContext.current

    val fullName = listOfNotNull(customer.firstName, customer.lastName)
        .joinToString(" ")
        .ifBlank { "Unknown" }
    val phone = (customer.mobile ?: customer.phone)?.let { formatPhoneDisplay(it) }
    val meta = listOfNotNull(
        phone,
        customer.email?.takeIf { it.isNotBlank() },
        customer.organization?.takeIf { it.isNotBlank() },
    ).firstOrNull()

    Box {
        com.bizarreelectronics.crm.ui.components.shared.BrandListItem(
            modifier = Modifier
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = {
                        if (!isBulkMode) {
                            onLongPress()
                        } else {
                            showMenu = true
                        }
                    },
                ),
            leading = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (isBulkMode) {
                        androidx.compose.material3.Checkbox(
                            checked = isSelected,
                            onCheckedChange = { onClick() },
                            modifier = Modifier.size(20.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                    }
                    CustomerAvatar(name = fullName)
                }
            },
            headline = {
                Text(
                    fullName,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            },
            support = {
                if (meta != null) {
                    Text(
                        meta,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
        )

        // Long-press context menu (plan:L878)
        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false },
        ) {
            DropdownMenuItem(
                text = { Text("Open") },
                onClick = { showMenu = false; onClick() },
            )
            val primaryPhone = customer.mobile ?: customer.phone
            if (primaryPhone != null) {
                DropdownMenuItem(
                    text = { Text("Copy phone") },
                    onClick = {
                        showMenu = false
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
                            as ClipboardManager
                        clipboard.setPrimaryClip(
                            ClipData.newPlainText("Phone", primaryPhone)
                        )
                    },
                )
                DropdownMenuItem(
                    text = { Text("SMS") },
                    onClick = {
                        showMenu = false
                        context.startActivity(
                            Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$primaryPhone"))
                        )
                    },
                )
            }
            if (!customer.email.isNullOrBlank()) {
                DropdownMenuItem(
                    text = { Text("Copy email") },
                    onClick = {
                        showMenu = false
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
                            as ClipboardManager
                        clipboard.setPrimaryClip(
                            ClipData.newPlainText("Email", customer.email)
                        )
                    },
                )
            }
            DropdownMenuItem(
                text = { Text("New ticket") },
                onClick = { showMenu = false; onCreateTicket() },
            )
        }
    }
}

// ─── Bulk action bar (plan:L882) ──────────────────────────────────────────────

@Composable
private fun BulkActionBar(
    selectedCount: Int,
    onTag: () -> Unit,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
) {
    BottomAppBar(
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "$selectedCount selected",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onTag) {
                Icon(Icons.Default.Label, contentDescription = "Tag selected")
            }
            TextButton(
                onClick = onDelete,
                colors = androidx.compose.material3.ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                Text("Delete")
            }
            TextButton(onClick = onCancel) {
                Text("Cancel")
            }
        }
    }
}
