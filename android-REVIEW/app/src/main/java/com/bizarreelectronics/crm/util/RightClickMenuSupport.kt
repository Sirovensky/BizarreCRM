package com.bizarreelectronics.crm.util

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp

/**
 * RightClickMenuSupport -- Section 22 L2247 / L2262-L2263 (plan:L2247, plan:L2262)
 *
 * Provides two utilities:
 *
 * ### [Modifier.rightClickable]
 * Fires [onRightClick] when the secondary mouse button is released over the
 * composable. Uses pointerInput + awaitPointerEventScope to detect secondary
 * button release events from mouse/trackpad/stylus.
 *
 * ### [ContextMenuHost]
 * Composable wrapper that combines long-press (via combinedClickable) AND
 * right-click (via rightClickable) to open a DropdownMenu populated from
 * [ContextMenuAction] items. Supports nested [ContextMenuAction.Submenu] items.
 *
 * ChromeOS / desktop note:
 * On ChromeOS and large-screen Android devices with a mouse or trackpad,
 * right-click events arrive as secondary-button pointer events in Compose.
 * This modifier surfaces them without any platform-specific code.
 *
 * Where to consume:
 * - Ticket list rows: "Open, Edit, Delete, Assign" menu
 * - Customer list rows: "View, SMS, Call, Email" menu
 * - Inventory items: "Edit, Duplicate, Archive" menu
 * - Invoice rows: "View PDF, Send, Void" menu
 */

// ---- Data types ---------------------------------------------------------------

/** A single entry in a context menu. */
sealed interface ContextMenuAction {
    /** A leaf action. */
    data class Item(
        val label: String,
        val onClick: () -> Unit,
    ) : ContextMenuAction

    /** A divider between groups. */
    data object Divider : ContextMenuAction

    /**
     * A submenu whose [children] are revealed inline on tap.
     * Callers may nest at most one level deep for usability.
     */
    data class Submenu(
        val label: String,
        val children: List<Item>,
    ) : ContextMenuAction
}

// ---- Modifier extension -------------------------------------------------------

/**
 * Fires [onRightClick] when the secondary (right) mouse button is released
 * over this composable. The [offset] parameter carries the pointer position
 * relative to the composable's top-left corner in pixels.
 *
 * Uses [pointerInput] + [awaitPointerEventScope] to listen for
 * [PointerEventType.Release] events where [PointerEvent.buttons.isSecondaryPressed]
 * was true at the preceding Press event.
 */
fun Modifier.rightClickable(onRightClick: (offset: Offset) -> Unit): Modifier =
    this.pointerInput(onRightClick) {
        awaitPointerEventScope {
            while (true) {
                val event = awaitPointerEvent()
                if (event.type == PointerEventType.Press &&
                    event.buttons.isSecondaryPressed
                ) {
                    val position = event.changes.firstOrNull()?.position ?: Offset.Zero
                    onRightClick(position)
                }
            }
        }
    }

// ---- Composable host ---------------------------------------------------------

/**
 * Wraps [content] with context-menu gesture detection and renders a
 * [DropdownMenu] anchored near the gesture point.
 *
 * Both long-press (via [combinedClickable]) and right-click (via [rightClickable])
 * open the same menu. Submenus expand inline beneath their parent entry.
 *
 * @param actions  Menu entries (leaf items, dividers, submenus).
 * @param modifier Applied to the outer [Box].
 * @param content  The composable to attach context-menu gestures to.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ContextMenuHost(
    actions: List<ContextMenuAction>,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    var menuOffset by remember { mutableStateOf(DpOffset.Zero) }
    var openSubmenuLabel by remember { mutableStateOf<String?>(null) }

    Box(
        modifier = modifier
            .rightClickable { offset ->
                menuOffset = DpOffset(offset.x.dp, offset.y.dp)
                openSubmenuLabel = null
                expanded = true
            }
            .combinedClickable(
                onLongClick = {
                    menuOffset = DpOffset.Zero
                    openSubmenuLabel = null
                    expanded = true
                },
                onClick = {},
            ),
    ) {
        content()

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = {
                expanded = false
                openSubmenuLabel = null
            },
            offset = menuOffset,
        ) {
            actions.forEach { action ->
                when (action) {
                    is ContextMenuAction.Divider -> HorizontalDivider()

                    is ContextMenuAction.Item -> DropdownMenuItem(
                        text = { Text(action.label) },
                        onClick = {
                            expanded = false
                            action.onClick()
                        },
                    )

                    is ContextMenuAction.Submenu -> {
                        DropdownMenuItem(
                            text = { Text("${action.label} >") },
                            onClick = {
                                openSubmenuLabel =
                                    if (openSubmenuLabel == action.label) null else action.label
                            },
                        )
                        if (openSubmenuLabel == action.label) {
                            action.children.forEach { child ->
                                DropdownMenuItem(
                                    text = { Text("  ${child.label}") },
                                    onClick = {
                                        expanded = false
                                        openSubmenuLabel = null
                                        child.onClick()
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
