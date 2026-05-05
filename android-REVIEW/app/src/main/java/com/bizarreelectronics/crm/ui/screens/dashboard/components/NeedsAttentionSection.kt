package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Inventory
import androidx.compose.material.icons.filled.Message
import androidx.compose.material.icons.filled.Payment
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.util.rememberReduceMotion

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/**
 * §3.3 L510 — data model for a single needs-attention card.
 *
 * **Stub contract**: when the ViewModel has no network data it emits an
 * empty list; the composable shows the "All clear" empty state. Stub items
 * for local-only scenarios (e.g. demo mode) should use the following
 * `id` prefix convention so the dismiss cache does not collide with server
 * IDs: `"stub:<category>:<index>"`.
 *
 * @param id          Stable server-assigned ID. Used as the dismiss cache key.
 * @param title       One-line summary shown in the card header.
 * @param subtitle    Optional supporting detail (count, entity name, etc.).
 * @param actionLabel CTA button label (e.g. "View Tickets").
 * @param actionRoute Navigation route target for the CTA and the "Open" menu item.
 * @param priority    Controls card surface colour: [AttentionPriority.HIGH] →
 *                    errorContainer, [AttentionPriority.INFO] → tertiaryContainer,
 *                    [AttentionPriority.DEFAULT] → primaryContainer.
 * @param category    Category tag used to pick the leading icon.
 */
data class NeedsAttentionItem(
    val id: String,
    val title: String,
    val subtitle: String = "",
    val actionLabel: String = "View",
    val actionRoute: String = "",
    val priority: AttentionPriority = AttentionPriority.DEFAULT,
    val category: AttentionCategory = AttentionCategory.OTHER,
)

/**
 * Card surface colour tier.
 * HIGH → errorContainer (red)
 * INFO → tertiaryContainer (teal)
 * DEFAULT → primaryContainer (purple)
 */
enum class AttentionPriority { HIGH, INFO, DEFAULT }

/**
 * Category tag for icon selection and TalkBack description.
 *
 * Maps to the six chip categories specified in §3.3 L510:
 * TICKET_OVERDUE, SLA_BREACH, LOW_STOCK, PAYMENT_FAILED, UNREAD_SMS,
 * UNASSIGNED_APPOINTMENT, plus a generic OTHER fallback.
 */
enum class AttentionCategory {
    TICKET_OVERDUE,
    SLA_BREACH,
    LOW_STOCK,
    PAYMENT_FAILED,
    UNREAD_SMS,
    UNASSIGNED_APPOINTMENT,
    OTHER,
}

// ---------------------------------------------------------------------------
// Section composable
// ---------------------------------------------------------------------------

/**
 * §3.3 L510–L514 — Needs-Attention row section for the Dashboard.
 *
 * Renders a vertical column of [AttentionCard]s (one per item) with a section
 * heading and, when [items] is empty, a subtle "All clear" success banner
 * (§3.3 L514).
 *
 * **Animation**: enter/exit animations respect [ReduceMotion]. When reduce-motion
 * is active, cards appear/disappear without vertical expansion transitions.
 *
 * @param items           Items supplied by the ViewModel. Empty → empty state shown.
 * @param onItemClick     Called when the user taps the card CTA or chooses "Open"
 *                        in the context menu. Receives [NeedsAttentionItem.actionRoute].
 * @param onDismiss       Called when the user chooses "Dismiss" in the context menu.
 *                        ViewModel performs optimistic removal + server call.
 * @param onMarkSeen      Called when the user chooses "Mark seen". Local flag only.
 * @param onCreateTask    Called when the user chooses "Create task". Route TBD.
 * @param appPreferences  Required for [rememberReduceMotion] — injected from ViewModel.
 * @param modifier        Outer modifier applied to the wrapping Column.
 */
@Composable
fun NeedsAttentionSection(
    items: List<NeedsAttentionItem>,
    onItemClick: (route: String) -> Unit,
    onDismiss: (id: String) -> Unit,
    onMarkSeen: (id: String) -> Unit = {},
    onCreateTask: (id: String) -> Unit = {},
    appPreferences: AppPreferences,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = rememberReduceMotion(appPreferences)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Section heading — always rendered so TalkBack users know the section exists
        Text(
            text = "Needs Attention",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.semantics { heading() },
        )

        // §3.3 L514 — empty state
        if (items.isEmpty()) {
            AttentionEmptyState()
        } else {
            items.forEach { item ->
                val enterAnim = if (reduceMotion) {
                    fadeIn()
                } else {
                    fadeIn() + expandVertically()
                }
                val exitAnim = if (reduceMotion) {
                    fadeOut()
                } else {
                    fadeOut() + shrinkVertically()
                }
                AnimatedVisibility(
                    visible = true,
                    enter = enterAnim,
                    exit = exitAnim,
                ) {
                    AttentionCard(
                        item = item,
                        onOpen = { onItemClick(item.actionRoute) },
                        onMarkSeen = { onMarkSeen(item.id) },
                        onDismiss = { onDismiss(item.id) },
                        onCreateTask = { onCreateTask(item.id) },
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// §3.3 L514 — Empty state banner
// ---------------------------------------------------------------------------

/**
 * §3.3 L514 — Subtle success banner shown when all attention items have been
 * dismissed or none exist. Uses [Icons.Default.TaskAlt] as the success icon.
 *
 * Hidden when [NeedsAttentionSection] has at least one item.
 */
@Composable
private fun AttentionEmptyState() {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "All clear. Nothing needs your attention."
            },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Default.TaskAlt,
                contentDescription = null, // decorative — parent contentDescription covers a11y
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSecondaryContainer,
            )
            Text(
                text = "All clear. Nothing needs your attention.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSecondaryContainer,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// §3.3 L510 / L512 — Attention card + context menu
// ---------------------------------------------------------------------------

/**
 * §3.3 L510 — single attention card with long-press context menu (§3.3 L512).
 *
 * Surface colour is driven by [NeedsAttentionItem.priority]:
 *   HIGH    → `errorContainer`   (red)
 *   INFO    → `tertiaryContainer` (teal)
 *   DEFAULT → `primaryContainer`  (purple)
 *
 * Long-press reveals a [DropdownMenu] with four actions:
 *   Open | Mark seen | Dismiss | Create task
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AttentionCard(
    item: NeedsAttentionItem,
    onOpen: () -> Unit,
    onMarkSeen: () -> Unit,
    onDismiss: () -> Unit,
    onCreateTask: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var menuExpanded by remember { mutableStateOf(false) }

    val containerColor = when (item.priority) {
        AttentionPriority.HIGH -> MaterialTheme.colorScheme.errorContainer
        AttentionPriority.INFO -> MaterialTheme.colorScheme.tertiaryContainer
        AttentionPriority.DEFAULT -> MaterialTheme.colorScheme.primaryContainer
    }
    val contentColor = when (item.priority) {
        AttentionPriority.HIGH -> MaterialTheme.colorScheme.onErrorContainer
        AttentionPriority.INFO -> MaterialTheme.colorScheme.onTertiaryContainer
        AttentionPriority.DEFAULT -> MaterialTheme.colorScheme.onPrimaryContainer
    }

    Box(modifier = modifier.fillMaxWidth()) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) {
                    contentDescription = buildString {
                        append(item.title)
                        if (item.subtitle.isNotBlank()) append(". ${item.subtitle}")
                        append(". Tap to ${item.actionLabel}. Long-press for more options.")
                    }
                    role = Role.Button
                }
                .combinedClickable(
                    onClick = onOpen,
                    onLongClick = { menuExpanded = true },
                ),
            shape = MaterialTheme.shapes.medium,
            colors = CardDefaults.cardColors(containerColor = containerColor),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    imageVector = item.category.icon(),
                    contentDescription = null, // decorative — parent node covers a11y
                    modifier = Modifier.size(20.dp),
                    tint = contentColor,
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.bodyMedium,
                        color = contentColor,
                    )
                    if (item.subtitle.isNotBlank()) {
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = item.subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = contentColor.copy(alpha = 0.78f),
                        )
                    }
                }
                // Leading action label as a subtle text button
                Text(
                    text = item.actionLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = contentColor,
                )
                Spacer(modifier = Modifier.width(4.dp))
            }
        }

        // §3.3 L512 — context menu (long-press)
        DropdownMenu(
            expanded = menuExpanded,
            onDismissRequest = { menuExpanded = false },
        ) {
            DropdownMenuItem(
                text = { Text("Open") },
                leadingIcon = {
                    Icon(Icons.Default.Assignment, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onOpen()
                },
            )
            DropdownMenuItem(
                text = { Text("Mark seen") },
                leadingIcon = {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onMarkSeen()
                },
            )
            DropdownMenuItem(
                text = { Text("Dismiss") },
                leadingIcon = {
                    Icon(Icons.Default.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onDismiss()
                },
            )
            DropdownMenuItem(
                text = { Text("Create task") },
                leadingIcon = {
                    Icon(Icons.Default.Assignment, contentDescription = null, modifier = Modifier.size(18.dp))
                },
                onClick = {
                    menuExpanded = false
                    onCreateTask()
                },
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Icon mapping
// ---------------------------------------------------------------------------

private fun AttentionCategory.icon(): ImageVector = when (this) {
    AttentionCategory.TICKET_OVERDUE -> Icons.Default.AccessTime
    AttentionCategory.SLA_BREACH -> Icons.Default.Warning
    AttentionCategory.LOW_STOCK -> Icons.Default.Inventory
    AttentionCategory.PAYMENT_FAILED -> Icons.Default.Payment
    AttentionCategory.UNREAD_SMS -> Icons.Default.Message
    AttentionCategory.UNASSIGNED_APPOINTMENT -> Icons.Default.CalendarToday
    AttentionCategory.OTHER -> Icons.Default.Warning
}
