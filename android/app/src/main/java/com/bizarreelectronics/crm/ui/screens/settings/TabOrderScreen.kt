package com.bizarreelectronics.crm.ui.screens.settings

/**
 * §1.5 line 202 — Tab Order customisation screen.
 *
 * ## Navigation
 * Settings → "Tab Order" row → this screen.
 *
 * ## What this screen does
 * Shows the four reorderable primary navigation tabs (Dashboard, Tickets, POS,
 * Messages) as a reorderable list. The user can move any tab up or down using
 * the arrow icon buttons; the "More" tab is shown as a disabled fifth row to
 * communicate that it is always last.
 *
 * Changes persist immediately to [AppPreferences.tabNavOrder] via
 * [TabOrderViewModel] so the bottom navigation bar reorders without a restart.
 *
 * The screen intentionally uses simple up/down [IconButton]s rather than
 * drag-handles because Compose's reorder-by-drag pattern (LazyListState +
 * detectDragGesturesAfterLongPress) requires significant boilerplate and a
 * third-party or foundation-draggable dependency that does not yet ship in
 * the project's dependency set. Up/down arrows satisfy the use-case cleanly
 * and are fully accessible (TalkBack announces "Move up / Move down").
 */

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.TabNavPrefs
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class TabOrderViewModel @Inject constructor(
    val appPreferences: AppPreferences,
) : ViewModel() {

    private val _order = MutableStateFlow(
        TabNavPrefs.decodeOrder(appPreferences.tabNavOrder),
    )
    val order: StateFlow<List<String>> = _order.asStateFlow()

    /** Move the tab at [fromIndex] one position toward [toIndex] and persist. */
    fun moveTab(fromIndex: Int, toIndex: Int) {
        val updated = TabNavPrefs.move(_order.value, fromIndex, toIndex)
        _order.value = updated
        appPreferences.tabNavOrder = TabNavPrefs.encodeOrder(updated)
    }

    /** Reset to default order and persist. */
    fun resetDefault() {
        val default = TabNavPrefs.REORDERABLE_TABS
        _order.value = default
        appPreferences.tabNavOrder = TabNavPrefs.encodeOrder(default)
    }
}

// ---------------------------------------------------------------------------
// Screen composable
// ---------------------------------------------------------------------------

@Composable
fun TabOrderScreen(
    onBack: () -> Unit,
    viewModel: TabOrderViewModel = hiltViewModel(),
) {
    val order by viewModel.order.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Tab Order",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    // Reset-to-default text button in the top-bar action area.
                    TextButton(onClick = { viewModel.resetDefault() }) {
                        Text("Reset")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            // Explanatory caption.
            Text(
                text = "Choose the order of tabs in the bottom navigation bar. " +
                    "The “More” tab is always last.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )

            HorizontalDivider()

            // Reorderable tab rows.
            order.forEachIndexed { index, route ->
                TabOrderRow(
                    label = TabNavPrefs.labelFor(route),
                    position = index + 1,
                    total = order.size,
                    onMoveUp = {
                        if (index > 0) viewModel.moveTab(index, index - 1)
                    },
                    onMoveDown = {
                        if (index < order.size - 1) viewModel.moveTab(index, index + 1)
                    },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 56.dp))
            }

            // "More" row — always last, not reorderable.
            TabOrderRow(
                label = "More",
                position = order.size + 1,
                total = order.size + 1,
                onMoveUp = null,   // null = disabled
                onMoveDown = null,
                isFixed = true,
            )
            HorizontalDivider()

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Row composable
// ---------------------------------------------------------------------------

@Composable
private fun TabOrderRow(
    label: String,
    position: Int,
    total: Int,
    onMoveUp: (() -> Unit)?,
    onMoveDown: (() -> Unit)?,
    isFixed: Boolean = false,
) {
    ListItem(
        headlineContent = {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                color = if (isFixed) MaterialTheme.colorScheme.onSurfaceVariant
                        else MaterialTheme.colorScheme.onSurface,
            )
        },
        leadingContent = {
            // Position badge using SuggestionChip-style surface.
            Surface(
                shape = MaterialTheme.shapes.small,
                color = if (isFixed) MaterialTheme.colorScheme.surfaceVariant
                        else MaterialTheme.colorScheme.secondaryContainer,
                modifier = Modifier.size(32.dp),
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = position.toString(),
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isFixed) MaterialTheme.colorScheme.onSurfaceVariant
                                else MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }
        },
        trailingContent = {
            if (!isFixed) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(
                        onClick = { onMoveUp?.invoke() },
                        enabled = onMoveUp != null && position > 1,
                        modifier = Modifier.semantics {
                            contentDescription = "Move $label up"
                        },
                    ) {
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowUp,
                            contentDescription = null,
                            tint = if (onMoveUp != null && position > 1)
                                MaterialTheme.colorScheme.onSurface
                            else
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                        )
                    }
                    IconButton(
                        onClick = { onMoveDown?.invoke() },
                        enabled = onMoveDown != null && position < total,
                        modifier = Modifier.semantics {
                            contentDescription = "Move $label down"
                        },
                    ) {
                        Icon(
                            imageVector = Icons.Default.KeyboardArrowDown,
                            contentDescription = null,
                            tint = if (onMoveDown != null && position < total)
                                MaterialTheme.colorScheme.onSurface
                            else
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                        )
                    }
                }
            }
        },
    )
}
