package com.bizarreelectronics.crm.ui.screens.stocktake

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCountLine
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar

/**
 * §60.2 Active count sheet.
 *
 * Shows the running list of counted items, their system qty, counted qty, and
 * variance. Provides:
 *   - Barcode-scan FAB (opens BarcodeScanScreen via [onScanClick]).
 *   - Search field to look up items by name/SKU and add them manually.
 *   - Inline quantity editor per line.
 *   - "Commit Count" button → [ConfirmDialog] guard (§60.1 ACTIVE → COMMITTED).
 *   - "Discard Session" button → [ConfirmDialog] guard (destructive).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StocktakeCountScreen(
    uiState: StocktakeUiState,
    onScanClick: () -> Unit,
    onSearchQueryChanged: (String) -> Unit,
    onAddItemFromSearch: (InventoryItemEntity) -> Unit,
    onQuantityChanged: (itemId: Long, qty: Int) -> Unit,
    onRemoveLine: (itemId: Long) -> Unit,
    onCommitClick: () -> Unit,
    onDiscardClick: () -> Unit,
    onBack: () -> Unit,
) {
    var showCommitDialog by remember { mutableStateOf(false) }
    var showDiscardDialog by remember { mutableStateOf(false) }

    if (showCommitDialog) {
        ConfirmDialog(
            title = stringResource(R.string.stocktake_commit_title),
            message = stringResource(R.string.stocktake_commit_message, uiState.lines.size),
            confirmLabel = stringResource(R.string.stocktake_commit_confirm),
            onConfirm = {
                showCommitDialog = false
                onCommitClick()
            },
            onDismiss = { showCommitDialog = false },
        )
    }

    if (showDiscardDialog) {
        ConfirmDialog(
            title = stringResource(R.string.stocktake_discard_title),
            message = stringResource(R.string.stocktake_discard_message),
            confirmLabel = stringResource(R.string.stocktake_discard_confirm),
            onConfirm = {
                showDiscardDialog = false
                onDiscardClick()
            },
            onDismiss = { showDiscardDialog = false },
            isDestructive = true,
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(stringResource(R.string.stocktake_count_title, uiState.lines.size))
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = { showDiscardDialog = true },
                        modifier = Modifier.semantics {
                            contentDescription = "Discard stocktake session"
                        },
                    ) {
                        Icon(
                            Icons.Default.DeleteForever,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onScanClick,
                containerColor = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Icon(
                    Icons.Default.QrCodeScanner,
                    contentDescription = stringResource(R.string.stocktake_scan_fab_cd),
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ── Search / add item ─────────────────────────────────────────────
            SearchBar(
                query = uiState.searchQuery,
                onQueryChange = onSearchQueryChanged,
                placeholder = stringResource(R.string.stocktake_search_hint),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (uiState.searchResults.isNotEmpty()) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) {
                    LazyColumn(modifier = Modifier.heightIn(max = 240.dp)) {
                        items(uiState.searchResults, key = { it.id }) { item ->
                            ListItem(
                                headlineContent = { Text(item.name) },
                                supportingContent = {
                                    Text(
                                        buildString {
                                            item.sku?.let { append("SKU: $it") }
                                            if (item.sku != null && item.upcCode != null) append(" · ")
                                            item.upcCode?.let { append(it) }
                                        },
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                },
                                trailingContent = {
                                    FilledTonalButton(
                                        onClick = { onAddItemFromSearch(item) },
                                        modifier = Modifier.semantics {
                                            contentDescription = "Add ${item.name} to count"
                                        },
                                    ) {
                                        Text(stringResource(R.string.stocktake_add_item))
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            HorizontalDivider()
                        }
                    }
                }
                Spacer(Modifier.height(4.dp))
            }

            // ── Error banner ──────────────────────────────────────────────────
            if (uiState.error != null) {
                OutlinedCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                ) {
                    Text(
                        uiState.error,
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            // ── Count lines ───────────────────────────────────────────────────
            if (uiState.lines.isEmpty()) {
                EmptyState(
                    icon = Icons.Default.Inventory2,
                    title = stringResource(R.string.stocktake_empty_title),
                    subtitle = stringResource(R.string.stocktake_empty_subtitle),
                )
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = 88.dp), // clear FAB
                ) {
                    items(uiState.lines, key = { it.itemId }) { line ->
                        StocktakeCountLineItem(
                            line = line,
                            onQuantityChanged = { qty -> onQuantityChanged(line.itemId, qty) },
                            onRemove = { onRemoveLine(line.itemId) },
                        )
                        HorizontalDivider()
                    }
                }
            }

            // ── Commit button ─────────────────────────────────────────────────
            if (uiState.lines.isNotEmpty()) {
                Surface(
                    tonalElevation = 2.dp,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    FilledTonalButton(
                        onClick = { showCommitDialog = true },
                        enabled = !uiState.isLoading,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp)
                            .semantics { contentDescription = "Commit stocktake count" },
                    ) {
                        if (uiState.isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                            )
                            Spacer(Modifier.width(8.dp))
                        } else {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(Modifier.width(8.dp))
                        }
                        Text(stringResource(R.string.stocktake_commit_cta))
                    }
                }
            }
        }
    }
}

// ─── Single count-line card ───────────────────────────────────────────────────

@Composable
private fun StocktakeCountLineItem(
    line: StocktakeCountLine,
    onQuantityChanged: (Int) -> Unit,
    onRemove: () -> Unit,
) {
    var qtyText by remember(line.countedQty) { mutableStateOf(line.countedQty.toString()) }

    ListItem(
        headlineContent = { Text(line.itemName, style = MaterialTheme.typography.bodyMedium) },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "System: ${line.systemQty}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                val varianceColor = when {
                    line.variance > 0 -> MaterialTheme.colorScheme.secondary
                    line.variance < 0 -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                }
                Text(
                    "Variance: ${if (line.variance >= 0) "+${line.variance}" else "${line.variance}"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = varianceColor,
                )
            }
        },
        trailingContent = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                OutlinedTextField(
                    value = qtyText,
                    onValueChange = { text ->
                        qtyText = text
                        text.toIntOrNull()?.let { qty -> if (qty >= 0) onQuantityChanged(qty) }
                    },
                    modifier = Modifier
                        .width(72.dp)
                        .semantics { contentDescription = "Counted quantity for ${line.itemName}" },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    label = { Text("Qty", style = MaterialTheme.typography.labelSmall) },
                )
                IconButton(
                    onClick = onRemove,
                    modifier = Modifier.semantics {
                        contentDescription = "Remove ${line.itemName} from count"
                    },
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
    )
}
