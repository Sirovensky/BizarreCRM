package com.bizarreelectronics.crm.ui.screens.inventory.components

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

// §6.1 Columns picker — tablet/ChromeOS inventory list column visibility.
//
// Persisted per-user via plain SharedPreferences (no PII, no Room needed).
// Available columns: SKU / Name / Type / Category / Stock / Cost / Retail /
// Supplier / Bin. Name is mandatory and cannot be hidden.
//
// Usage: show via ModalBottomSheet when the column-picker icon is tapped
// (tablet-gated — caller checks isTablet before rendering the icon).

/** Stable list of all optional columns. */
enum class InventoryColumn(val label: String, val mandatory: Boolean = false) {
    NAME("Name", mandatory = true),  // always visible, shown greyed out in picker
    SKU("SKU"),
    TYPE("Type"),
    CATEGORY("Category"),
    STOCK("Stock"),
    COST("Cost"),
    RETAIL("Retail"),
    SUPPLIER("Supplier"),
    BIN("Bin"),
}

private const val PREFS_NAME = "inventory_columns"
private const val PREFS_KEY = "visible_columns"
private val DEFAULT_VISIBLE = setOf(
    InventoryColumn.NAME,
    InventoryColumn.SKU,
    InventoryColumn.STOCK,
    InventoryColumn.RETAIL,
)

/** Load persisted column set from SharedPreferences. */
fun loadInventoryColumns(context: Context): Set<InventoryColumn> {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val raw = prefs.getString(PREFS_KEY, null) ?: return DEFAULT_VISIBLE
    return raw.split(",")
        .mapNotNull { name -> InventoryColumn.entries.firstOrNull { it.name == name } }
        .toSet()
        .ifEmpty { DEFAULT_VISIBLE }
}

/** Persist column set to SharedPreferences. */
fun saveInventoryColumns(context: Context, columns: Set<InventoryColumn>) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    prefs.edit().putString(PREFS_KEY, columns.joinToString(",") { it.name }).apply()
}

/**
 * Modal bottom sheet for picking which inventory columns to display.
 * Tablet/ChromeOS first — caller should gate on [isMediumOrExpandedWidth()].
 *
 * @param visibleColumns Currently visible columns.
 * @param onColumnsChanged Called when the user toggles a column. Caller
 *   should persist via [saveInventoryColumns] and re-compose the list.
 * @param onDismiss Called when the sheet is dismissed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryColumnsPickerSheet(
    visibleColumns: Set<InventoryColumn>,
    onColumnsChanged: (Set<InventoryColumn>) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    // Local mutable copy so toggling is immediate without waiting for recompose
    var localVisible by remember(visibleColumns) { mutableStateOf(visibleColumns) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            // Handle + title
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Visible columns",
                    style = MaterialTheme.typography.titleMedium,
                )
                TextButton(onClick = {
                    saveInventoryColumns(context, localVisible)
                    onColumnsChanged(localVisible)
                    onDismiss()
                }) {
                    Text("Done")
                }
            }

            HorizontalDivider()

            LazyColumn(
                contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                items(InventoryColumn.entries) { column ->
                    val isVisible = column in localVisible
                    val isMandatory = column.mandatory

                    ListItem(
                        headlineContent = {
                            Text(
                                column.label,
                                color = if (isMandatory)
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                else
                                    MaterialTheme.colorScheme.onSurface,
                            )
                        },
                        trailingContent = {
                            Checkbox(
                                checked = isVisible,
                                onCheckedChange = { checked ->
                                    if (!isMandatory) {
                                        localVisible = if (checked) {
                                            localVisible + column
                                        } else {
                                            localVisible - column
                                        }
                                        // Persist immediately on each toggle
                                        saveInventoryColumns(context, localVisible)
                                        onColumnsChanged(localVisible)
                                    }
                                },
                                enabled = !isMandatory,
                            )
                        },
                        leadingContent = if (isVisible) {
                            {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                        } else null,
                    )
                }
            }
        }
    }
}
