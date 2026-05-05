package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.dashboard.DashboardLayoutConfig
import kotlinx.coroutines.launch

/**
 * §3.17 L496 — Customization bottom sheet for the dashboard.
 *
 * Shown when the user long-presses any dashboard tile. Presents:
 * - A draggable reorder list of all allowed tile IDs.
 * - Checkboxes to hide/show each tile.
 * - Save button that persists to [AppPreferences].
 *
 * **Drag-to-reorder**: uses [detectDragGesturesAfterLongPress] on the drag-handle icon.
 * On phone, the handle is the sole drag trigger; on tablet the full row is also draggable.
 * When [reduceMotion] is true, reorder snaps immediately with no animated shadow elevation.
 *
 * @param layoutConfig   Current layout config providing [allowedTiles] and [hiddenTiles].
 * @param reduceMotion   When true, skip animated elevation and snap reorder immediately.
 * @param onSave         Called with the new ordered list and hidden set when the user taps Save.
 * @param onDismiss      Called when the sheet is dismissed without saving.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardCustomizationSheet(
    layoutConfig: DashboardLayoutConfig,
    reduceMotion: Boolean,
    onSave: (orderedTiles: List<String>, hiddenTiles: Set<String>) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    // Mutable working copy of the tile order; starts from visible + hidden in original order.
    val allTiles = remember(layoutConfig) {
        val ordered = layoutConfig.visibleTiles + layoutConfig.hiddenTiles
            .filter { it in layoutConfig.allowedTiles && it !in layoutConfig.visibleTiles }
        mutableStateListOf(*ordered.toTypedArray())
    }
    val hiddenSet = remember(layoutConfig) {
        mutableStateListOf(*layoutConfig.hiddenTiles.toTypedArray())
    }

    // Drag state: index of the item currently being dragged; null = no drag active.
    var dragIndex by remember { mutableStateOf<Int?>(null) }
    var dragTarget by remember { mutableStateOf<Int?>(null) }
    var dragOffsetY by remember { mutableStateOf(0f) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            // Header
            Text(
                text = "Customize dashboard",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 8.dp),
            )
            Text(
                text = "Drag to reorder. Uncheck to hide a tile.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 16.dp),
            )

            // Tile list with drag handles + checkboxes
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                itemsIndexed(allTiles, key = { _, tile -> tile }) { index, tileId ->
                    val isDragging = dragIndex == index
                    // Shadow elevation animates on drag unless ReduceMotion is on.
                    val elevation by animateDpAsState(
                        targetValue = if (isDragging) 8.dp else 0.dp,
                        animationSpec = if (reduceMotion) tween(durationMillis = 0) else tween(150),
                        label = "drag_elevation_$tileId",
                    )

                    TileCustomizationRow(
                        tileId = tileId,
                        isVisible = tileId !in hiddenSet,
                        elevation = elevation,
                        dragHandleModifier = Modifier.pointerInput(tileId) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    dragIndex = index
                                    dragTarget = index
                                    dragOffsetY = 0f
                                },
                                onDrag = { _, dragAmount ->
                                    dragOffsetY += dragAmount.y
                                    // Estimate target row index from cumulative drag distance.
                                    val rowHeight = 56f // dp approx, good enough for gesture
                                    val newTarget = (index + (dragOffsetY / rowHeight).toInt())
                                        .coerceIn(0, allTiles.lastIndex)
                                    if (newTarget != dragTarget) {
                                        dragTarget = newTarget
                                        if (!reduceMotion) {
                                            // Move item in the list immediately for live preview.
                                            val from = dragIndex ?: return@detectDragGesturesAfterLongPress
                                            if (from != newTarget) {
                                                val item = allTiles.removeAt(from)
                                                allTiles.add(newTarget, item)
                                                dragIndex = newTarget
                                            }
                                        }
                                    }
                                },
                                onDragEnd = {
                                    if (reduceMotion) {
                                        // Snap: move item to final target only on drag end.
                                        val from = dragIndex ?: return@detectDragGesturesAfterLongPress
                                        val to = dragTarget ?: from
                                        if (from != to) {
                                            val item = allTiles.removeAt(from)
                                            allTiles.add(to, item)
                                        }
                                    }
                                    dragIndex = null
                                    dragTarget = null
                                    dragOffsetY = 0f
                                },
                                onDragCancel = {
                                    dragIndex = null
                                    dragTarget = null
                                    dragOffsetY = 0f
                                },
                            )
                        },
                        onCheckedChange = { checked ->
                            if (checked) {
                                hiddenSet.remove(tileId)
                            } else {
                                if (tileId !in hiddenSet) hiddenSet.add(tileId)
                            }
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                OutlinedButton(
                    onClick = {
                        scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() }
                    },
                ) { Text("Cancel") }
                Spacer(modifier = Modifier.width(8.dp))
                Button(
                    onClick = {
                        onSave(allTiles.toList(), hiddenSet.toSet())
                    },
                ) { Text("Save") }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

/**
 * A single row in the customization sheet for tile [tileId].
 *
 * Displays a drag handle, the human-readable tile label, and a checkbox.
 *
 * @param tileId              Machine ID of the tile (e.g. "open-tickets").
 * @param isVisible           Whether the tile is currently shown.
 * @param elevation           Shadow elevation applied during drag.
 * @param dragHandleModifier  Modifier applied to the drag handle icon only.
 * @param onCheckedChange     Called when the checkbox is toggled.
 */
@Composable
private fun TileCustomizationRow(
    tileId: String,
    isVisible: Boolean,
    elevation: androidx.compose.ui.unit.Dp,
    dragHandleModifier: Modifier,
    onCheckedChange: (Boolean) -> Unit,
) {
    androidx.compose.material3.Surface(
        tonalElevation = elevation,
        shape = MaterialTheme.shapes.small,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Drag handle — the only drag trigger on phone; full row on tablet.
            Icon(
                imageVector = Icons.Default.DragHandle,
                contentDescription = "Drag to reorder ${tileLabelFor(tileId)}",
                modifier = dragHandleModifier
                    .size(24.dp)
                    .semantics { contentDescription = "Drag handle for ${tileLabelFor(tileId)}" },
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = tileLabelFor(tileId),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            Checkbox(
                checked = isVisible,
                onCheckedChange = onCheckedChange,
            )
        }
    }
}

/** Maps a machine tile ID to a human-readable label for the customization sheet. */
private fun tileLabelFor(tileId: String): String = when (tileId) {
    "open-tickets"      -> "Open Tickets"
    "revenue"           -> "Revenue"
    "appointments"      -> "Appointments"
    "low-stock"         -> "Low Stock"
    "pending-payments"  -> "Pending Payments"
    "my-queue"          -> "My Queue"
    "my-commission"     -> "My Commission"
    "tasks"             -> "Tasks"
    "today-sales"       -> "Today's Sales"
    "shift-totals"      -> "Shift Totals"
    "quick-actions"     -> "Quick Actions"
    "team-inbox"        -> "Team Inbox"
    "activity-feed"     -> "Activity Feed"
    "profit-hero"       -> "Profit Overview"
    "busy-hours"        -> "Busy Hours"
    "leaderboard"       -> "Leaderboard"
    "repeat-customer"   -> "Repeat Customers"
    "churn-alert"       -> "Churn Alert"
    "forecast"          -> "Revenue Forecast"
    "missing-parts"     -> "Missing Parts"
    else                -> tileId.replace("-", " ").replaceFirstChar { it.uppercase() }
}
