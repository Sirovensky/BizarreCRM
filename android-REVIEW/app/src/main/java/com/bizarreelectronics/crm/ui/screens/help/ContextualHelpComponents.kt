package com.bizarreelectronics.crm.ui.screens.help

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// ---------------------------------------------------------------------------
// §72.2 — Contextual help
// ---------------------------------------------------------------------------

/**
 * §72.2 — A `?` icon button rendered in a screen's top bar. Tapping it opens
 * [HelpSheetContent] for the given [topic].
 *
 * Usage in a TopAppBar `actions` slot:
 * ```
 * HelpIconButton(topic = ALL_HELP_TOPICS.first { it.titleResId == R.string.help_topic_tickets })
 * ```
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpIconButton(
    topic: HelpTopic,
    modifier: Modifier = Modifier,
) {
    var showSheet by remember { mutableStateOf(false) }
    val contentRaw = rememberTopicContent(topic)

    IconButton(
        onClick = { showSheet = true },
        modifier = modifier,
    ) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.HelpOutline,
            contentDescription = stringResource(R.string.help_icon_cd),
        )
    }

    if (showSheet) {
        HelpBottomSheet(
            topic = topic,
            content = contentRaw,
            onDismiss = { showSheet = false },
        )
    }
}

/**
 * §72.2 — Bottom sheet shown when the `?` icon is tapped. Renders the topic
 * content using the same plain-text Markdown rendering as [HelpTopicDetailScreen].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpBottomSheet(
    topic: HelpTopic,
    content: String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = stringResource(topic.titleResId),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 4.dp),
            )
            content.lines().forEach { line ->
                when {
                    line.startsWith("## ") -> Text(
                        text = line.removePrefix("## "),
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    line.startsWith("- ") -> Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("•", style = MaterialTheme.typography.bodySmall)
                        Text(line.removePrefix("- "), style = MaterialTheme.typography.bodySmall)
                    }
                    line.isBlank() -> Spacer(Modifier.height(4.dp))
                    !line.startsWith("# ") -> Text(
                        text = line,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// §72.4 — RichTooltip long-press helper
// ---------------------------------------------------------------------------

/**
 * §72.4 — Wraps any icon-adjacent content in a Material 3 [RichTooltip] so
 * that a long-press (or hover on large-screen) surfaces a descriptive tooltip.
 *
 * Usage:
 * ```kotlin
 * HelpTooltip(
 *     title = "Ticket status",
 *     body = "Shows the current stage of the repair workflow.",
 * ) {
 *     Icon(Icons.Default.Info, contentDescription = "Help")
 * }
 * ```
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpTooltip(
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val tooltipState = rememberTooltipState()
    TooltipBox(
        positionProvider = TooltipDefaults.rememberRichTooltipPositionProvider(),
        tooltip = {
            RichTooltip(
                title = { Text(title) },
            ) {
                Text(body)
            }
        },
        state = tooltipState,
        modifier = modifier,
    ) {
        content()
    }
}

// ---------------------------------------------------------------------------
// §72.5 — Keyboard-shortcut overlay
// ---------------------------------------------------------------------------

/**
 * §72.5 — Overlay shown when the user presses Ctrl+/ on a physical keyboard.
 * Caller provides [shortcuts]: a list of (key hint, action description) pairs
 * relevant to the current screen.
 *
 * The overlay is a [AlertDialog] so it sits above all other content and is
 * dismissed by tapping outside or pressing Back.
 *
 * Wiring Ctrl+/ is done at the NavGraph level (or per-screen) via
 * `Modifier.onPreviewKeyEvent`.
 */
@Composable
fun KeyboardShortcutOverlay(
    shortcuts: List<Pair<String, String>>,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(stringResource(R.string.help_keyboard_shortcuts_title))
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                shortcuts.forEach { (key, action) ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = action,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Surface(
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            tonalElevation = 2.dp,
                        ) {
                            Text(
                                text = key,
                                style = MaterialTheme.typography.labelMedium,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            )
                        }
                    }
                }
                if (shortcuts.isEmpty()) {
                    Text(
                        text = stringResource(R.string.help_keyboard_shortcuts_empty),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.action_cancel))
            }
        },
    )
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Reads the bundled Markdown resource for [topic] on the IO dispatcher and
 * remembers the result in composition. Returns an empty string while loading.
 */
@Composable
fun rememberTopicContent(topic: HelpTopic): String {
    val context = LocalContext.current
    var content by remember(topic.rawResId) { mutableStateOf("") }
    LaunchedEffect(topic.rawResId) {
        content = withContext(Dispatchers.IO) {
            runCatching {
                context.resources.openRawResource(topic.rawResId).bufferedReader().readText()
            }.getOrDefault("")
        }
    }
    return content
}
