package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import com.bizarreelectronics.crm.ui.components.shared.brandColors
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import java.text.NumberFormat
import java.util.Locale

/**
 * Mockup CI-5 pattern: each repair line renders name + status helper row +
 * right-aligned primary price. Status enum drives the helper-line colour so
 * the UI reads: reserved = green, ordered = amber, labor/meta = muted.
 */
data class RepairLinePreview(
    val name: String,
    val status: RepairLineStatus,
    val statusDetail: String,   // "stock 7 → 6", "ETA Mon Apr 27", "~60 min · tech: Mike"
    val amountCents: Long,
)

enum class RepairLineStatus { RESERVED, ORDERED, LABOR }

private val currencyFmt = NumberFormat.getCurrencyInstance(Locale.US)
private fun centsToDisplay(cents: Long) = currencyFmt.format(cents / 100.0)

private val DEPOSIT_PRESETS_CENTS = listOf(0L, 2500L, 5000L, 10000L)

@Composable
fun CheckInStep5Quote(
    subtotalCents: Long,
    taxRateBps: Int,
    depositCents: Long,
    depositFullBalance: Boolean,
    laborMinutes: Int,
    quoteTotalCents: Long,
    dueOnPickupCents: Long,
    onDepositChange: (Long) -> Unit,
    onDepositFullBalance: (Boolean) -> Unit,
    onLaborMinutesChange: (Int) -> Unit,
    onLaborTechChange: (Long) -> Unit,
    onSubtotalChange: (Long) -> Unit,
    repairLines: List<RepairLinePreview> = emptyList(),
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(key = "repair_lines_header") {
            Text(
                "REPAIR LINES",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (repairLines.isEmpty()) {
            item(key = "repair_lines_placeholder") {
                RepairLinesPlaceholder(
                    subtotalCents = subtotalCents,
                    onSubtotalChange = onSubtotalChange,
                )
            }
        } else {
            items(repairLines, key = { it.name }) { line ->
                RepairLineRow(line = line)
            }
        }

        item(key = "labor_row") {
            LaborRow(
                minutes = laborMinutes,
                onMinutesChange = onLaborMinutesChange,
            )
        }

        item(key = "eta_row") {
            EtaRow(laborMinutes = laborMinutes)
        }

        item(key = "divider_totals") { HorizontalDivider() }

        item(key = "totals_card") {
            TotalsCard(
                subtotalCents = subtotalCents,
                taxRateBps = taxRateBps,
                depositCents = depositCents,
                quoteTotalCents = quoteTotalCents,
                dueOnPickupCents = dueOnPickupCents,
            )
        }

        item(key = "deposit_section") {
            DepositSection(
                depositCents = depositCents,
                depositFullBalance = depositFullBalance,
                quoteTotalCents = quoteTotalCents,
                onDepositChange = onDepositChange,
                onDepositFullBalance = onDepositFullBalance,
            )
        }
    }
}

@Composable
private fun RepairLineRow(line: RepairLinePreview) {
    val ext = LocalExtendedColors.current
    val (glyph, statusColor) = when (line.status) {
        RepairLineStatus.RESERVED -> "✓ Reserved · ${line.statusDetail}" to ext.success
        RepairLineStatus.ORDERED -> "⏳ Ordered · ${line.statusDetail}" to ext.warning
        RepairLineStatus.LABOR -> line.statusDetail to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(line.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(glyph, style = MaterialTheme.typography.bodySmall, color = statusColor)
        }
        Text(
            centsToDisplay(line.amountCents),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
        )
    }
    HorizontalDivider()
}

@Composable
private fun RepairLinesPlaceholder(
    subtotalCents: Long,
    onSubtotalChange: (Long) -> Unit,
) {
    var input by remember(subtotalCents) {
        mutableStateOf(if (subtotalCents > 0) "%.2f".format(subtotalCents / 100.0) else "")
    }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                "Parts reserved by tech appear here after ticket creation. Enter a labor/repair estimate now:",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                value = input,
                onValueChange = { raw ->
                    input = raw
                    val cents = Math.round((raw.toDoubleOrNull() ?: 0.0) * 100)
                    onSubtotalChange(cents)
                },
                label = { Text("Estimated repair cost") },
                prefix = { Text("$") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Estimated repair cost in dollars" },
            )
        }
    }
}

@Composable
private fun LaborRow(
    minutes: Int,
    onMinutesChange: (Int) -> Unit,
) {
    var input by remember(minutes) {
        mutableStateOf(if (minutes > 0) minutes.toString() else "")
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = input,
            onValueChange = { raw ->
                input = raw
                onMinutesChange(raw.toIntOrNull() ?: 0)
            },
            label = { Text("Labor time") },
            suffix = { Text("min") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier
                .weight(1f)
                .semantics { contentDescription = "Labor time in minutes" },
        )
    }
}

@Composable
private fun EtaRow(laborMinutes: Int) {
    if (laborMinutes <= 0) return
    // Mockup CI-5 pattern: ⏱️ card with absolute "Est. ready: <date, time>"
    // headline + muted helper line. We only have labor minutes here (no
    // supplier / tech-queue inputs yet), so ETA = now + laborMinutes rounded
    // up to the next 15-min mark. Helper line documents the caveat.
    val now = remember(laborMinutes) { java.time.LocalDateTime.now() }
    val ready = remember(now, laborMinutes) {
        val raw = now.plusMinutes(laborMinutes.toLong())
        val mins = raw.minute
        val roundUp = ((mins / 15) + if (mins % 15 == 0) 0 else 1) * 15
        raw.withMinute(0).withSecond(0).withNano(0).plusMinutes(roundUp.toLong())
    }
    val readyFmt = remember(ready) {
        ready.format(java.time.format.DateTimeFormatter.ofPattern("EEE MMM d, h:mma"))
    }
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("⏱️", style = MaterialTheme.typography.headlineSmall)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Est. ready: $readyFmt",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "Based on labor only — parts ETA not yet factored",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun TotalsCard(
    subtotalCents: Long,
    taxRateBps: Int,
    depositCents: Long,
    quoteTotalCents: Long,
    dueOnPickupCents: Long,
) {
    val taxCents = subtotalCents * taxRateBps / 10_000
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            TotalsRow("Subtotal", centsToDisplay(subtotalCents))
            TotalsRow("Tax (${"%.2f".format(taxRateBps / 100.0)}%)", centsToDisplay(taxCents))
            if (depositCents > 0L) {
                TotalsRow(
                    "Deposit",
                    "- ${centsToDisplay(depositCents)}",
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            HorizontalDivider()
            TotalsRow("Due on pickup", centsToDisplay(dueOnPickupCents), bold = true)
        }
    }
}

@Composable
private fun TotalsRow(
    label: String,
    value: String,
    bold: Boolean = false,
    color: androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color.Unspecified,
) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            label,
            style = if (bold) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
        )
        Text(
            value,
            style = if (bold) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
            color = color,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DepositSection(
    depositCents: Long,
    depositFullBalance: Boolean,
    quoteTotalCents: Long,
    onDepositChange: (Long) -> Unit,
    onDepositFullBalance: (Boolean) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Collect deposit", style = MaterialTheme.typography.titleSmall)

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(vertical = 4.dp),
        ) {
            items(DEPOSIT_PRESETS_CENTS, key = { it }) { preset ->
                FilterChip(
                    selected = !depositFullBalance && depositCents == preset,
                    onClick = {
                        onDepositFullBalance(false)
                        onDepositChange(preset)
                    },
                    label = { Text(centsToDisplay(preset)) },
                    colors = FilterChipDefaults.brandColors(),
                    modifier = Modifier.semantics {
                        contentDescription = "Deposit preset: ${centsToDisplay(preset)}"
                    },
                )
            }
            item(key = "full") {
                FilterChip(
                    selected = depositFullBalance,
                    onClick = {
                        onDepositFullBalance(true)
                        onDepositChange(quoteTotalCents)
                    },
                    label = { Text("Full") },
                    colors = FilterChipDefaults.brandColors(),
                    modifier = Modifier.semantics {
                        contentDescription = "Collect full balance as deposit"
                    },
                )
            }
        }
    }
}
