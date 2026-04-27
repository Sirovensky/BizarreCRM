package com.bizarreelectronics.crm.ui.commandpalette

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * §54 — Command palette overlay.
 *
 * Triggered by Ctrl+K keyboard chord (wired in AppNavGraph's KeyboardShortcutsHost)
 * or via a floating action button on phones (wired at call site).
 *
 * Behaviour:
 *  - Renders as a full-screen scrim dialog with a centered card.
 *  - Auto-focuses the search field on show.
 *  - Arrow-key navigation and Enter to execute top result (keyboard UX).
 *  - Escape key closes the dialog.
 *  - Tapping the scrim closes the dialog.
 *  - Commands grouped by [CommandGroup] with a sticky header.
 *  - Admin-only commands hidden automatically via [CommandPaletteViewModel].
 *
 * @param onNavigate called when a command with a route is executed; caller
 *                   (AppNavGraph) pushes the destination.
 * @param onDismiss  called when the palette should close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommandPaletteScreen(
    onNavigate: (route: String) -> Unit,
    onDismiss: () -> Unit,
    viewModel: CommandPaletteViewModel = hiltViewModel(),
) {
    val query by viewModel.query.collectAsState()
    val results by viewModel.results.collectAsState()

    // §54.3 — arrow-key selected index (-1 = none)
    var selectedIndex by remember { mutableIntStateOf(-1) }

    // Reset selection whenever the results list changes
    LaunchedEffect(results) { selectedIndex = -1 }

    val focusRequester = remember { FocusRequester() }

    // Group results for display
    val grouped = remember(results) {
        results.groupBy { it.group }
    }

    /**
     * Execute [cmd] — invoke its side-effect, navigate if it has a route,
     * persist recency, and close the palette.
     */
    fun executeCommand(cmd: Command) {
        cmd.action?.invoke()
        cmd.route?.let { route -> onNavigate(route) }
        viewModel.onCommandExecuted(cmd.id)
        onDismiss()
    }

    Dialog(
        onDismissRequest = {
            viewModel.clear()
            onDismiss()
        },
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            dismissOnClickOutside = true,
            dismissOnBackPress = true,
        ),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f))
                .clickable(
                    interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                    indication = null,
                    onClick = {
                        viewModel.clear()
                        onDismiss()
                    },
                ),
            contentAlignment = Alignment.TopCenter,
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth(fraction = 0.92f)
                    .padding(top = 80.dp)
                    .shadow(elevation = 16.dp, shape = RoundedCornerShape(16.dp))
                    .clickable(
                        interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
                        indication = null,
                        onClick = { /* consume clicks so scrim dismissal doesn't fire */ },
                    )
                    .onKeyEvent { keyEvent ->
                        if (keyEvent.type != KeyEventType.KeyDown) return@onKeyEvent false
                        when (keyEvent.key) {
                            Key.Escape -> {
                                viewModel.clear()
                                onDismiss()
                                true
                            }
                            Key.DirectionDown -> {
                                if (results.isNotEmpty()) {
                                    selectedIndex = (selectedIndex + 1).coerceAtMost(results.lastIndex)
                                }
                                true
                            }
                            Key.DirectionUp -> {
                                if (results.isNotEmpty()) {
                                    selectedIndex = (selectedIndex - 1).coerceAtLeast(0)
                                }
                                true
                            }
                            Key.Enter, Key.NumPadEnter -> {
                                val target = if (selectedIndex in results.indices) {
                                    results[selectedIndex]
                                } else {
                                    results.firstOrNull()
                                }
                                target?.let { executeCommand(it) }
                                true
                            }
                            else -> false
                        }
                    }
                    .semantics { contentDescription = "Command palette" },
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surface,
                tonalElevation = 8.dp,
            ) {
                Column {
                    // Search field
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Search,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        androidx.compose.foundation.text.BasicTextField(
                            value = query,
                            onValueChange = viewModel::onQueryChange,
                            modifier = Modifier
                                .weight(1f)
                                .focusRequester(focusRequester),
                            textStyle = MaterialTheme.typography.bodyLarge.copy(
                                color = MaterialTheme.colorScheme.onSurface,
                            ),
                            singleLine = true,
                            decorationBox = { inner ->
                                if (query.isEmpty()) {
                                    Text(
                                        text = "Search commands…",
                                        style = MaterialTheme.typography.bodyLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                inner()
                            },
                        )
                        if (query.isNotEmpty()) {
                            IconButton(onClick = { viewModel.onQueryChange("") }) {
                                Icon(Icons.Default.Close, contentDescription = "Clear search")
                            }
                        }
                    }

                    HorizontalDivider(thickness = 0.5.dp)

                    // Results list
                    if (results.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = if (query.isBlank()) "Type to search commands" else "No commands found",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(bottom = 8.dp),
                        ) {
                            // Flatten to a single indexed list for arrow-key selection tracking
                            var flatIndex = 0
                            grouped.forEach { (group, cmds) ->
                                item(key = "header:${group.name}") {
                                    Text(
                                        text = group.displayName,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(
                                            horizontal = 16.dp,
                                            vertical = 6.dp,
                                        ),
                                    )
                                }
                                cmds.forEach { cmd ->
                                    val itemIndex = flatIndex++
                                    item(key = cmd.id) {
                                        CommandRow(
                                            command = cmd,
                                            isSelected = itemIndex == selectedIndex,
                                            onClick = { executeCommand(cmd) },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Auto-focus search field when palette opens.
    LaunchedEffect(Unit) {
        runCatching { focusRequester.requestFocus() }
    }
}

// ─── Command row ──────────────────────────────────────────────────────────────

@Composable
private fun CommandRow(
    command: Command,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    // §54.3 — keyboard-selected row gets a tinted container so the user can
    // see which command Enter will activate without leaving the search field.
    val containerColor = if (isSelected) {
        MaterialTheme.colorScheme.secondaryContainer
    } else {
        Color.Transparent
    }

    ListItem(
        headlineContent = {
            Text(
                text = command.label,
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        leadingContent = command.icon?.let { icon ->
            {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        },
        modifier = Modifier
            .clickable(onClick = onClick)
            .semantics { contentDescription = command.label },
        colors = ListItemDefaults.colors(
            containerColor = containerColor,
        ),
    )
}
