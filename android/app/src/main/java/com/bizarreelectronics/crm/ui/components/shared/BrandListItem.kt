package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Brand-aligned list item.
 *
 * - Normal state: standard surface background.
 * - Selected state: 2dp purple (primary) left accent bar — NOT full-row fill.
 *   The bar is an inset decoration on the leading edge.
 *
 * Caller renders [HorizontalDivider] between rows using the helper
 * [BrandListItemDivider] below (1px outline at 40% alpha), so this
 * composable does not include a built-in divider.
 *
 * Usage pattern (Wave 3):
 * ```kotlin
 * items(tickets) { ticket ->
 *     BrandListItem(
 *         leading = { /* Avatar / icon */ },
 *         headline = { Text(ticket.title) },
 *         support = { Text(ticket.customer) },
 *         trailing = { BrandStatusBadge(ticket.status, ticket.status) },
 *         selected = ticket.id == selectedId,
 *         onClick = { onTicketClick(ticket.id) },
 *     )
 *     BrandListItemDivider()
 * }
 * ```
 *
 * @param leading   Optional leading content (icon, avatar, checkbox).
 * @param headline  Primary text content (required).
 * @param support   Secondary / supporting text content.
 * @param trailing  Optional trailing content (badge, status, price).
 * @param selected  When true, renders a 2dp purple left accent bar.
 * @param onClick   Row tap callback. If null, row is not clickable.
 * @param modifier  Applied to the outer Row.
 */
@Composable
fun BrandListItem(
    headline: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
    support: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    selected: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val accentColor = MaterialTheme.colorScheme.primary

    // D5-3: explicit ripple + MutableInteractionSource so the row flashes on
    // tap. The prior plain .clickable(onClick = ...) relied on LocalIndication
    // being auto-provided, which in some Material3 1.3+ contexts silently
    // resolves to no-op, producing a "ghost" tap with no visual ack.
    val interactionSource = remember { MutableInteractionSource() }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (onClick != null) {
                    // §26.1 — merge descendants + Role.Button so TalkBack
                    // announces the headline + support + trailing-badge text
                    // as one labeled button instead of focusing each
                    // composable individually and reading them as unrelated
                    // pieces. clickable() is still applied on top so the
                    // ripple / tap target keeps working.
                    // §22.3 — tablet / ChromeOS / desktop-mode cursor
                    // affordance: hovering shows the hand pointer on any
                    // clickable list row. No-op on phones with no cursor.
                    Modifier
                        .semantics(mergeDescendants = true) {
                            role = Role.Button
                        }
                        .pointerHoverIcon(PointerIcon.Hand)
                        .clickable(
                            interactionSource = interactionSource,
                            indication = ripple(),
                            onClick = onClick,
                        )
                } else {
                    Modifier
                },
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 2dp purple left accent bar for selected state
        if (selected) {
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(48.dp)
                    .background(accentColor),
            )
        } else {
            Spacer(modifier = Modifier.width(2.dp))
        }

        // Leading slot
        if (leading != null) {
            Box(
                modifier = Modifier.padding(start = 14.dp, top = 12.dp, bottom = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                leading()
            }
        }

        // Headline + support column
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(
                    start = if (leading != null) 12.dp else 14.dp,
                    end = if (trailing != null) 8.dp else 14.dp,
                    top = 12.dp,
                    bottom = 12.dp,
                ),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            headline()
            if (support != null) {
                support()
            }
        }

        // Trailing slot
        if (trailing != null) {
            Box(
                modifier = Modifier.padding(end = 14.dp, top = 12.dp, bottom = 12.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                trailing()
            }
        }
    }
}

/**
 * Divider to place between [BrandListItem] rows.
 * 1px outline color at 40% alpha — present but not Material-heavy.
 */
@Composable
fun BrandListItemDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(
        modifier = modifier,
        thickness = 1.dp,
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
    )
}
