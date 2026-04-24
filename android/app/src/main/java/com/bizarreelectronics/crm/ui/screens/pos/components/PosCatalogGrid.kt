package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.QuickAddItem
import com.bizarreelectronics.crm.data.remote.dto.InventoryListItem
import com.bizarreelectronics.crm.ui.screens.pos.PosUiState
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth

private val CATEGORIES = listOf(
    "All", "Accessories", "Parts", "Services", "Cables", "Batteries", "Screens",
)

/**
 * POS catalog grid — tablet 4-col / phone 2-col.
 *
 * Debounced search, category chips, quick-add bar, HID scanner via [onKeyEvent].
 * Plan §16.1 L1789-L1793.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosCatalogGrid(
    uiState: PosUiState,
    inventoryItems: List<InventoryListItem>,
    onSearchChange: (String) -> Unit,
    onCategorySelect: (String?) -> Unit,
    onItemTap: (InventoryListItem) -> Unit,
    onQuickAddTap: (QuickAddItem) -> Unit,
    onBarcodeScan: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val isTablet = isMediumOrExpandedWidth()
    val columns = if (isTablet) 4 else 2

    // HID scanner buffer — accumulates characters until Enter
    var hidBuffer by remember { mutableStateOf("") }

    val filteredItems = remember(inventoryItems, uiState.catalogSearch, uiState.catalogCategory) {
        inventoryItems.filter { item ->
            val matchesSearch = uiState.catalogSearch.isBlank() ||
                item.name?.contains(uiState.catalogSearch, ignoreCase = true) == true ||
                item.sku?.contains(uiState.catalogSearch, ignoreCase = true) == true
            val matchesCat = uiState.catalogCategory == null ||
                uiState.catalogCategory == "All" ||
                item.itemType?.equals(uiState.catalogCategory, ignoreCase = true) == true
            matchesSearch && matchesCat
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            // HID barcode scanner: accumulate keystroke chars; Enter = submit
            .onKeyEvent { event ->
                if (event.type == KeyEventType.KeyUp) {
                    if (event.key == Key.Enter) {
                        if (hidBuffer.isNotBlank()) {
                            onBarcodeScan(hidBuffer)
                            hidBuffer = ""
                        }
                        true
                    } else {
                        // Append printable chars — Key.nativeKeyCode maps to char
                        val ch = event.key.keyCode.toInt().toChar()
                        if (ch.isLetterOrDigit() || ch == '-') {
                            hidBuffer += ch
                        }
                        false
                    }
                } else false
            },
    ) {
        // ── Search bar ────────────────────────────────────────────────────
        OutlinedTextField(
            value = uiState.catalogSearch,
            onValueChange = onSearchChange,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            placeholder = { Text("Search items or SKU…") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            trailingIcon = {
                IconButton(
                    onClick = { /* open barcode scanner dialog */ },
                    modifier = Modifier.semantics {
                        contentDescription = "Scan barcode"
                    },
                ) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                }
            },
            singleLine = true,
        )

        // ── Category chips ────────────────────────────────────────────────
        SingleChoiceSegmentedButtonRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
        ) {
            CATEGORIES.forEachIndexed { index, cat ->
                val selected = when {
                    cat == "All" -> uiState.catalogCategory == null || uiState.catalogCategory == "All"
                    else -> uiState.catalogCategory == cat
                }
                SegmentedButton(
                    selected = selected,
                    onClick = { onCategorySelect(if (cat == "All") null else cat) },
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = CATEGORIES.size),
                    label = { Text(cat, style = MaterialTheme.typography.labelSmall) },
                )
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        // ── Quick-add bar ─────────────────────────────────────────────────
        if (uiState.quickAddVisible && uiState.quickAddItems.isNotEmpty()) {
            Text(
                "Quick Add",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 12.dp),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                uiState.quickAddItems.take(5).forEach { item ->
                    AssistChip(
                        onClick = { onQuickAddTap(item) },
                        label = {
                            Text(
                                item.name,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        modifier = Modifier.semantics {
                            contentDescription = "Quick add ${item.name}"
                            role = Role.Button
                        },
                    )
                }
            }
            Spacer(modifier = Modifier.height(4.dp))
        }

        // ── Catalog grid ──────────────────────────────────────────────────
        if (filteredItems.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (uiState.catalogSearch.isBlank()) "No items in catalog"
                    else "No results for \"${uiState.catalogSearch}\"",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filteredItems, key = { it.id }) { item ->
                    CatalogItemTile(item = item, onClick = { onItemTap(item) })
                }
            }
        }
    }
}

@Composable
private fun CatalogItemTile(
    item: InventoryListItem,
    onClick: () -> Unit,
) {
    val price = item.price ?: 0.0
    val priceLabel = "$${String.format("%.2f", price)}"
    val name = item.name ?: "Unknown"

    Card(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(0.9f)
            .semantics(mergeDescendants = true) {
                contentDescription = "$name, $priceLabel. Tap to add to cart."
                role = Role.Button
            },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Photo placeholder (coil not wired here — shown as initial)
            Surface(
                modifier = Modifier.size(48.dp),
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        name.take(1).uppercase(),
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                name,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                priceLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
