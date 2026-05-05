package com.bizarreelectronics.crm.ui.navigation

import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier

/**
 * AdaptiveListDetailScaffold -- Section 22 L2235 (plan:L2235)
 *
 * Thin wrapper around [NavigableListDetailPaneScaffold] from the material3-adaptive
 * library. Renders a single-pane stack on compact widths and a side-by-side
 * list+detail layout on medium (>=600 dp) and expanded (>=840 dp) windows.
 *
 * Where to consume:
 * Tickets, Customers, Inventory, Invoices, and SMS list screens should replace
 * their top-level scaffold with this composable when windowMode >= Tablet.
 * Example:
 *
 *   val mode = rememberWindowMode()
 *   if (mode != WindowMode.Phone) {
 *       AdaptiveListDetailScaffold(
 *           listContent = { TicketListPane(onSelect = { id -> selectedId = id }) },
 *           detailContent = { id -> TicketDetailPane(ticketId = id) },
 *           selectedId = selectedId,
 *       )
 *   }
 *
 * @param listContent   Composable rendered in the list pane.
 * @param detailContent Composable rendered in the detail pane; receives [selectedId].
 * @param selectedId    Currently selected entity ID. null means no selection.
 * @param modifier      Layout modifier applied to the scaffold root.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun AdaptiveListDetailScaffold(
    listContent: @Composable () -> Unit,
    detailContent: @Composable (selectedId: Long?) -> Unit,
    selectedId: Long?,
    modifier: Modifier = Modifier,
) {
    val navigator = rememberListDetailPaneScaffoldNavigator<Long>()

    // Navigate to Detail pane whenever caller signals a selection.
    LaunchedEffect(selectedId) {
        if (selectedId != null) {
            navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, selectedId)
        }
    }

    NavigableListDetailPaneScaffold(
        navigator = navigator,
        listPane = {
            AnimatedPane(modifier = Modifier) {
                listContent()
            }
        },
        detailPane = {
            AnimatedPane(modifier = Modifier) {
                detailContent(navigator.currentDestination?.contentKey)
            }
        },
        modifier = modifier,
    )
}
