package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.ui.theme.contrastTextColor

// ---------------------------------------------------------------------------
// StatusTone — rainbow-status discipline (5-hue, maps server statuses to brand)
// ---------------------------------------------------------------------------

/**
 * The 5-hue brand status discipline.
 * Purple = active/in-progress, Teal = qualified/info,
 * Magenta = scheduled/highlight, Success = converted/completed,
 * Error = lost/no-show, Muted = cancelled.
 *
 * Wave 3 agents: call [brandStatusColor] with the server status string, or
 * map to [StatusTone] explicitly for typed callers.
 */
enum class StatusTone {
    Purple,   // active, in-progress, open
    Teal,     // qualified, info, draft
    Magenta,  // scheduled, highlight, pending
    Success,  // converted, completed, paid
    Error,    // lost, no-show, overdue
    Muted,    // cancelled, archived, inactive
}

/**
 * Maps a server-provided status string (lower-case comparison) to a
 * [StatusTone]. Covers ticket, lead, appointment, and invoice statuses.
 */
fun statusToneFor(status: String): StatusTone {
    return when (status.trim().lowercase()) {
        // Active / in-progress
        "open", "active", "in progress", "in_progress", "in repair",
        "repair started", "diagnosed", "waiting for parts", "new" -> StatusTone.Purple

        // Qualified / info
        "qualified", "contacted", "draft", "estimate sent", "quote sent",
        "sent", "info" -> StatusTone.Teal

        // Scheduled / highlight
        "scheduled", "pending", "awaiting", "appointment",
        "follow-up", "follow_up", "on hold" -> StatusTone.Magenta

        // Success / completed
        "converted", "completed", "repaired", "closed", "paid",
        "resolved", "done", "won", "delivered" -> StatusTone.Success

        // Error / lost
        "lost", "no-show", "no_show", "overdue", "failed",
        "rejected", "declined", "unrepairable" -> StatusTone.Error

        // Muted / cancelled
        "cancelled", "canceled", "archived", "inactive",
        "void", "voided", "deleted" -> StatusTone.Muted

        else -> StatusTone.Muted
    }
}

/**
 * Returns the foreground [Color] for a status string using the 5-hue discipline.
 *
 * Callers should use this color as text on a [surfaceVariant] background
 * (e.g. in [BrandStatusBadge]). Do not use as a background fill on its own.
 *
 * Wave 3 Leads/Appointments agents: replace per-screen colour maps with this.
 */
@Composable
fun brandStatusColor(status: String): Color {
    val scheme = MaterialTheme.colorScheme
    return when (statusToneFor(status)) {
        StatusTone.Purple  -> scheme.primary
        StatusTone.Teal    -> scheme.secondary
        StatusTone.Magenta -> scheme.tertiary
        StatusTone.Success -> LocalExtendedColors.current.success  // AND-036
        StatusTone.Error   -> scheme.error
        StatusTone.Muted   -> scheme.onSurfaceVariant
    }
}

// ---------------------------------------------------------------------------
// BrandStatusBadge — replaces StatusBadge (deprecated below)
// ---------------------------------------------------------------------------

/**
 * On-brand status pill. Uses surfaceVariant bg + single-hue text colour from
 * the 5-hue discipline. Replaces the full-saturation [StatusBadge].
 *
 * §26.3 — Pass [statusIcon] to ensure the badge conveys status via icon + text,
 * not by colour alone (colour-blind safe). When non-null, the icon is rendered
 * at 10dp before the label text and the parent Surface announces both via
 * `clearAndSetSemantics { contentDescription = label }` so TalkBack reads the
 * label once rather than icon + label separately.
 *
 * Wave 3: migrate all [StatusBadge] call sites to this.
 */
@Composable
fun BrandStatusBadge(
    label: String,
    tone: StatusTone,
    modifier: Modifier = Modifier,
    /** §26.3 — optional status icon so the badge is not colour-only. */
    statusIcon: ImageVector? = null,
) {
    val extColors = LocalExtendedColors.current
    val textColor: Color = when (tone) {
        StatusTone.Purple  -> MaterialTheme.colorScheme.primary
        StatusTone.Teal    -> MaterialTheme.colorScheme.secondary
        StatusTone.Magenta -> MaterialTheme.colorScheme.tertiary
        StatusTone.Success -> extColors.success  // AND-036
        StatusTone.Error   -> MaterialTheme.colorScheme.error
        StatusTone.Muted   -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    // §26.3 — merge icon + label into a single accessible node so TalkBack
    // announces "In Repair" not "icon In Repair".
    Surface(
        modifier = modifier.clearAndSetSemantics { contentDescription = label },
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (statusIcon != null) {
                Icon(
                    imageVector = statusIcon,
                    contentDescription = null, // §26.3 — merged via clearAndSetSemantics above
                    tint = textColor,
                    modifier = Modifier.size(10.dp),
                )
            }
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = textColor,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

/**
 * Convenience overload: looks up [StatusTone] from a server status string.
 */
@Composable
fun BrandStatusBadge(
    label: String,
    status: String,
    modifier: Modifier = Modifier,
    statusIcon: ImageVector? = null,
) {
    BrandStatusBadge(label = label, tone = statusToneFor(status), modifier = modifier, statusIcon = statusIcon)
}

/**
 * Legacy badge: full-saturation fill, parses arbitrary hex colour from server.
 *
 * @deprecated Replace with [BrandStatusBadge]. Kept for source-compatibility
 * during Wave 3 migration. Will be removed in a follow-up cleanup pass.
 */
@Deprecated(
    message = "Use BrandStatusBadge(label, tone) or BrandStatusBadge(label, status) instead.",
    replaceWith = ReplaceWith(
        "BrandStatusBadge(label = name, status = name)",
        "com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge",
    ),
)
@Composable
fun StatusBadge(name: String, color: String) {
    val fallbackBg = MaterialTheme.colorScheme.primary
    val bgColor = try {
        Color(android.graphics.Color.parseColor(color))
    } catch (_: Exception) {
        fallbackBg
    }
    // D5-4: avoid hardcoding Color.White — some server-supplied status hex
    // values are light enough that white text disappears. Use the luminance
    // helper so the foreground adapts to whatever bgColor the server returns.
    val fgColor = contrastTextColor(bgColor)
    Surface(shape = MaterialTheme.shapes.small, color = bgColor) {
        Text(
            name,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = fgColor,
            fontWeight = FontWeight.Medium,
        )
    }
}

// ---------------------------------------------------------------------------
// EmptyState — upgraded: WaveDivider at top, display-condensed headline, teal sub
// ---------------------------------------------------------------------------

/**
 * Unified empty-state component. Injects a [WaveDivider] at the top (the
 * sanctioned placement for empty states). Headline uses headlineMedium
 * (Barlow Condensed SemiBold via Wave 1 Typography). Subline in teal secondary.
 *
 * Wave 3: replace every hand-rolled empty Column in list screens with this.
 * Signature is preserved from the original; no callers need updating except
 * to add the `import`.
 */
@Composable
fun EmptyState(
    icon: ImageVector = Icons.Default.Inbox,
    title: String,
    subtitle: String? = null,
    action: (@Composable () -> Unit)? = null,
    includeWave: Boolean = true,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (includeWave) WaveDivider()
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 48.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                icon,
                // decorative — illustrative empty-state icon; sibling title + subtitle Text carry the announcement
                contentDescription = null,
                modifier = Modifier.size(36.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
            Text(
                title,
                style = MaterialTheme.typography.headlineMedium, // Barlow Condensed
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    // CROSS21/CROSS24: empty-state subtext is neutral info, not an action
                    // target. Teal (secondary) reads as interactive/link; use the muted
                    // onSurfaceVariant tone instead.
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            action?.invoke()
        }
    }
}

// ---------------------------------------------------------------------------
// LoadingIndicator — retained for in-button / in-toolbar use
// ---------------------------------------------------------------------------

/**
 * Small centered spinner. Keep for in-button / in-toolbar loading only.
 * For list-loading, use [BrandSkeleton] instead.
 */
@Composable
fun LoadingIndicator(modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

// ---------------------------------------------------------------------------
// BrandSkeleton — shimmer placeholder replacing CircularProgressIndicator in lists
// ---------------------------------------------------------------------------

/**
 * Placeholder list rows with shimmer animation. Use in list screens while
 * data is loading. Replaces bare [CircularProgressIndicator] at list level.
 *
 * Wave 3 targets:
 *   - TicketListScreen.kt:202, InventoryListScreen.kt:238, LeadListScreen.kt:229,
 *     AppointmentListScreen.kt:277, NotificationListScreen.kt:176,
 *     InvoiceListScreen.kt, CustomerListScreen.kt, ReportsScreen.kt:344
 *
 * @param rows Number of placeholder rows to render (default 5).
 * @param modifier Applied to the outer Column.
 */
@Composable
fun BrandSkeleton(
    rows: Int = 5,
    modifier: Modifier = Modifier,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "skeleton")
    val shimmerAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 300, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "shimmerAlpha",
    )

    val surface2 = MaterialTheme.colorScheme.surfaceVariant
    val surfaceVar = MaterialTheme.colorScheme.surfaceContainerHigh

    Column(modifier = modifier.fillMaxWidth()) {
        repeat(rows) { index ->
            SkeletonRow(shimmerAlpha = shimmerAlpha, surface2 = surface2, surfaceVar = surfaceVar)
            if (index < rows - 1) {
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    thickness = 1.dp,
                )
            }
        }
    }
}

@Composable
private fun SkeletonRow(
    shimmerAlpha: Float,
    surface2: Color,
    surfaceVar: Color,
) {
    val shimmerColor = surface2.copy(alpha = shimmerAlpha)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Leading avatar/icon placeholder
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(shimmerColor),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // Headline placeholder
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.65f)
                    .height(14.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(shimmerColor),
            )
            // Support placeholder
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.45f)
                    .height(11.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(surfaceVar.copy(alpha = shimmerAlpha * 0.6f)),
            )
        }
        // Trailing placeholder
        Box(
            modifier = Modifier
                .width(48.dp)
                .height(20.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(surfaceVar.copy(alpha = shimmerAlpha * 0.5f)),
        )
    }
}

// ---------------------------------------------------------------------------
// ErrorState — tuned to brand: quiet, body-sans, teal Retry
// ---------------------------------------------------------------------------

/**
 * Branded error surface. Hue-shifted red via [MaterialTheme.colorScheme.error],
 * icon at 28dp, body-sans text, teal Retry text button.
 *
 * Signature unchanged from original — Wave 3 can drop-in replace.
 */
@Composable
fun ErrorState(message: String, onRetry: (() -> Unit)? = null) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            Icons.Default.Error,
            // decorative — error state icon; sibling message Text carries the announcement
            contentDescription = null,
            modifier = Modifier.size(28.dp),
            tint = MaterialTheme.colorScheme.error,
        )
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (onRetry != null) {
            TextButton(
                onClick = onRetry,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.secondary, // teal
                ),
            ) {
                Text("Retry")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// ConfirmDialog — verified: surface2 container, purple/error buttons
// ---------------------------------------------------------------------------

/**
 * Brand-aligned confirmation dialog.
 * Container = surface2 (surfaceContainerHigh).
 * Confirm = purple primary; destructive confirm = error.
 * Cancel = teal TextButton.
 *
 * §26.1 — Focus management: on dialog open, focus is automatically moved to
 * the Confirm button via [FocusRequester]. This satisfies the "focus sets
 * first-responder on screen open" requirement without relying on Material3's
 * default traversal order (which varies across M3 versions).
 *
 * Existing callers already pass [isDestructive] (param already present);
 * signature unchanged.
 */
@Composable
fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String = "Confirm",
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    isDestructive: Boolean = false,
) {
    // §26.1 — move focus to Confirm button when the dialog enters composition.
    val confirmFocusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        try { confirmFocusRequester.requestFocus() } catch (_: Exception) { /* safe to ignore */ }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        title = { Text(title, style = MaterialTheme.typography.titleMedium) },
        text = { Text(message, style = MaterialTheme.typography.bodyMedium) },
        confirmButton = {
            Button(
                onClick = onConfirm,
                colors = if (isDestructive) {
                    ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                } else {
                    ButtonDefaults.buttonColors()
                },
                modifier = Modifier.focusRequester(confirmFocusRequester),
            ) {
                Text(confirmLabel)
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.secondary, // teal
                ),
            ) {
                Text("Cancel")
            }
        },
    )
}

// ---------------------------------------------------------------------------
// SearchBar — tuned to brand: filled surface2, 16dp radius, teal/muted icons
// ---------------------------------------------------------------------------

/**
 * Brand-aligned search field. Filled [surfaceVariant] bg (not outlined),
 * 16dp radius, teal leading icon, muted clear icon.
 *
 * Signature unchanged from original — Wave 3 can migrate call sites.
 *
 * Wave 3 targets:
 *   - TicketListScreen.kt:155-171, InventoryListScreen.kt:200-216,
 *     CustomerListScreen.kt hand-rolled fields.
 */
@Composable
fun SearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    placeholder: String = "Search...",
    modifier: Modifier = Modifier,
) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = {
            Text(
                placeholder,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        leadingIcon = {
            Icon(
                Icons.Default.Search,
                // decorative — leadingIcon on a labeled TextField; the field's placeholder announces the purpose
                contentDescription = null,
                tint = MaterialTheme.colorScheme.secondary, // teal
            )
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(
                        Icons.Default.Clear,
                        contentDescription = "Clear",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
    )
}

// ---------------------------------------------------------------------------
// §26.1 Accessibility — toggle-row stateDescription helper
// ---------------------------------------------------------------------------

/**
 * §26.1 — Returns a [Modifier] that attaches [stateDescription] and [Role.Switch]
 * semantics to a composable that acts as a toggle row (a Row with a label + Switch).
 *
 * Use on the clickable wrapper of any settings row that houses a [Switch] to ensure
 * TalkBack announces "On / Off" after the label, and Switch Access maps the row
 * correctly.
 *
 * ```kotlin
 * Row(
 *     modifier = Modifier
 *         .fillMaxWidth()
 *         .toggleRowSemantics("Keep screen on", checked = keepScreenOn)
 *         .clickable { viewModel.toggle() },
 * ) { … }
 * ```
 */
fun Modifier.toggleRowSemantics(label: String, checked: Boolean): Modifier =
    this.semantics(mergeDescendants = true) {
        // §26.1 — stateDescription replaces the default "on" / "off" announcement
        // with a phrase that includes the setting name so blind users never hear
        // a context-free "Switch, off" when focus lands on the row.
        stateDescription = if (checked) "$label, on" else "$label, off"
        role = Role.Switch
    }
