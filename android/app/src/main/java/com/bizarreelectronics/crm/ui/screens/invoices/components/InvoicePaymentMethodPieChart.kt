package com.bizarreelectronics.crm.ui.screens.invoices.components

/**
 * §7.1 — Payment-method donut chart for the Invoice list stats header
 * (tablet / ChromeOS only).
 *
 * Companion to [InvoiceStatusPieChart] — same pure-Compose Canvas renderer, same
 * ReduceMotion + a11y contract.  Data comes from the `method_distribution` array
 * returned by GET /invoices/stats (server-side `payments` table aggregation).
 *
 * States:
 *  - [slices] empty → "No payment data" empty-state text.
 *  - [slices] non-empty → animated donut + tap-to-highlight legend.
 *
 * Tapping a legend row highlights the corresponding arc and shows a tooltip with
 * the count and total amount for that method.
 *
 * Respects ReduceMotion: sweep animation is suppressed when [reduceMotion] = true.
 * TalkBack: [contentDescription] enumerates each slice with count and percentage.
 */

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.InvoiceMethodDistributionItem
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.InfoBlue
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber

// ─── Data model ───────────────────────────────────────────────────────────────

/**
 * One slice of the payment-method donut chart.
 *
 * @param label       Human-readable method label (e.g. "Cash", "Card").
 * @param count       Number of payments with this method.
 * @param totalCents  Revenue sum for this method in cents.
 * @param color       Arc/legend swatch color.
 */
data class InvoicePaymentMethodSlice(
    val label: String,
    val count: Int,
    val totalCents: Long,
    val color: Color,
)

// ─── Color palette ────────────────────────────────────────────────────────────

/** Deterministic brand-consistent color for each known payment method string. */
private fun colorForMethod(method: String): Color = when (method.lowercase().trim()) {
    "cash"                        -> SuccessGreen
    "card", "credit", "debit",
    "credit_card", "debit_card"   -> InfoBlue
    "check", "cheque"             -> WarningAmber
    "store_credit", "credit_note" -> Color(0xFF9B59B6)  // purple — distinct from brand
    "gift_card", "gift card"      -> Color(0xFFE67E22)  // orange
    "ach", "bank_transfer",
    "wire", "zelle", "venmo"      -> Color(0xFF1ABC9C)  // teal
    "other", ""                   -> Color(0xFF95A5A6)  // neutral gray
    else                          -> ErrorRed
}

// ─── Factory helper ───────────────────────────────────────────────────────────

/**
 * Converts [InvoiceMethodDistributionItem] rows returned by the server into a
 * sorted [InvoicePaymentMethodSlice] list suitable for [InvoicePaymentMethodPieChart].
 *
 * Slices are sorted descending by count so the most-used method appears first.
 */
fun buildPaymentMethodSlices(
    items: List<InvoiceMethodDistributionItem>,
): List<InvoicePaymentMethodSlice> {
    if (items.isEmpty()) return emptyList()
    return items
        .filter { it.count > 0 }
        .map { item ->
            val label = item.method
                .replace('_', ' ')
                .replaceFirstChar { it.uppercase() }
                .ifBlank { "Other" }
            InvoicePaymentMethodSlice(
                label      = label,
                count      = item.count,
                totalCents = (item.total * 100).toLong(),
                color      = colorForMethod(item.method),
            )
        }
        .sortedByDescending { it.count }
}

// ─── Main composable ──────────────────────────────────────────────────────────

/**
 * Donut chart + tappable legend for invoice payment-method breakdown.
 *
 * Intended for tablet / ChromeOS only — the caller wraps it in an
 * [com.bizarreelectronics.crm.util.isMediumOrExpandedWidth] guard.
 *
 * @param slices         Slice data from [buildPaymentMethodSlices].
 * @param modifier       Applied to the root [Column].
 * @param reduceMotion   Suppress sweep animation when true.
 */
@Composable
fun InvoicePaymentMethodPieChart(
    slices: List<InvoicePaymentMethodSlice>,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    if (slices.isEmpty()) {
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(120.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "No payment data",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        return
    }

    val totalCount = slices.sumOf { it.count }

    // Accessibility: enumerate each slice
    val a11yDesc = buildString {
        append("Payment method breakdown: ")
        slices.forEach { s ->
            val pct = if (totalCount > 0) s.count * 100 / totalCount else 0
            append("${s.label} ${s.count} ($pct%), ")
        }
        append("$totalCount total payments")
    }.trimEnd(',', ' ')

    // Animated sweep progress 0 → 1
    val animProgress = remember { Animatable(0f) }
    LaunchedEffect(slices) {
        animProgress.snapTo(0f)
        animProgress.animateTo(
            targetValue   = 1f,
            animationSpec = if (reduceMotion) tween(durationMillis = 0) else tween(durationMillis = 600),
        )
    }
    val progress by animProgress.asState()

    // Highlighted legend row (null = all slices at full opacity)
    var selectedIndex by remember(slices) { mutableStateOf<Int?>(null) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = a11yDesc },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = "Payment Methods",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )

        // Donut arc + centre label
        Box(contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.size(150.dp)) {
                val strokeWidth = size.minDimension * 0.20f
                val diameter   = size.minDimension - strokeWidth
                val topLeft = Offset(
                    x = (size.width - diameter)  / 2f,
                    y = (size.height - diameter) / 2f,
                )
                val arcSize = Size(diameter, diameter)
                var startAngle = -90f

                slices.forEachIndexed { idx, slice ->
                    if (totalCount <= 0) return@forEachIndexed
                    val fullSweep = slice.count.toFloat() / totalCount * 360f
                    val sweep     = fullSweep * progress
                    drawArc(
                        color      = if (selectedIndex == null || selectedIndex == idx)
                            slice.color
                        else
                            slice.color.copy(alpha = 0.28f),
                        startAngle = startAngle,
                        sweepAngle = sweep,
                        useCenter  = false,
                        topLeft    = topLeft,
                        size       = arcSize,
                        style      = Stroke(width = strokeWidth),
                    )
                    startAngle += fullSweep
                }
            }

            // Centre: total payment count
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text  = "$totalCount",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text  = "payments",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Tooltip for selected slice
        val sel = selectedIndex?.let { slices.getOrNull(it) }
        if (sel != null) {
            val selDollars = sel.totalCents / 100.0
            Surface(
                shape          = MaterialTheme.shapes.small,
                color          = MaterialTheme.colorScheme.secondaryContainer,
                tonalElevation = 4.dp,
            ) {
                Text(
                    text  = "${sel.label}: ${sel.count} — ${'$'}${"%.0f".format(selDollars)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

        // Legend rows
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            slices.forEachIndexed { idx, slice ->
                val pct        = if (totalCount > 0) slice.count * 100f / totalCount else 0f
                val isSelected = selectedIndex == idx
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedIndex = if (isSelected) null else idx }
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Canvas(modifier = Modifier.size(10.dp)) { drawCircle(color = slice.color) }
                    Text(
                        text     = slice.label,
                        style    = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color      = if (isSelected)
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.onSurface,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                    Text(
                        text  = "${slice.count}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text  = "${"%.0f".format(pct)}%",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
