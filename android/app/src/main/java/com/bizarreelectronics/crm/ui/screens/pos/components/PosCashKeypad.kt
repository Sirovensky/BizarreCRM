package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import java.util.Locale
import kotlin.math.ceil

private val DENOMINATION_PRESETS = listOf(1, 5, 10, 20, 50, 100)

/**
 * Numeric keypad for cash payment.
 *
 * Shows denomination hints ($1/$5/$10/$20/$50/$100) and a live change calculator.
 * Plan §16.1 L1805.
 */
@Composable
fun PosCashKeypad(
    totalCents: Long,
    onCashEntered: (Long) -> Unit, // cents
    modifier: Modifier = Modifier,
) {
    var inputCents by remember { mutableLongStateOf(0L) }
    var displayString by remember { mutableStateOf("0.00") }

    val changeCents = (inputCents - totalCents).coerceAtLeast(0L)
    val totalDollars = totalCents / 100.0

    fun updateInput(cents: Long) {
        inputCents = cents
        displayString = String.format(Locale.US, "%.2f", cents / 100.0)
        onCashEntered(cents)
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Display ───────────────────────────────────────────────────────
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "Amount Tendered",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "$$displayString",
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.Bold,
                )
                if (changeCents > 0) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Change: $${String.format(Locale.US, "%.2f", changeCents / 100.0)}",
                        style = MaterialTheme.typography.titleMedium,
                        color = SuccessGreen,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics {
                            contentDescription = "Change due: $${String.format(Locale.US, "%.2f", changeCents / 100.0)}"
                        },
                    )
                }
            }
        }

        // ── Denomination hints ────────────────────────────────────────────
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            DENOMINATION_PRESETS.forEach { denom ->
                val roundedCents = (ceil(totalDollars / denom) * denom * 100).toLong()
                OutlinedButton(
                    onClick = { updateInput(roundedCents) },
                    modifier = Modifier
                        .weight(1f)
                        .semantics {
                            contentDescription = "Tender $$denom"
                            role = Role.Button
                        },
                    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 8.dp),
                ) {
                    Text("$$denom", style = MaterialTheme.typography.labelSmall)
                }
            }
        }

        // ── Keypad ────────────────────────────────────────────────────────
        val keys = listOf(
            listOf("7", "8", "9"),
            listOf("4", "5", "6"),
            listOf("1", "2", "3"),
            listOf(".", "0", "⌫"),
        )

        // Buffer of digit chars to build amount
        var rawBuffer by remember { mutableStateOf("") }

        fun appendChar(ch: String) {
            when (ch) {
                "⌫" -> rawBuffer = rawBuffer.dropLast(1)
                "." -> if (!rawBuffer.contains('.')) rawBuffer += ch
                else -> {
                    // Limit to 2 decimal places
                    val dotIdx = rawBuffer.indexOf('.')
                    if (dotIdx >= 0 && rawBuffer.length - dotIdx > 2) return
                    rawBuffer += ch
                }
            }
            val parsed = rawBuffer.toDoubleOrNull() ?: 0.0
            updateInput((parsed * 100).toLong())
        }

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            keys.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    row.forEach { key ->
                        FilledTonalButton(
                            onClick = { appendChar(key) },
                            modifier = Modifier
                                .weight(1f)
                                .height(56.dp)
                                .semantics {
                                    contentDescription = if (key == "⌫") "Backspace" else key
                                    role = Role.Button
                                },
                        ) {
                            Text(
                                key,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                }
            }
        }

        // ── Exact + clear ─────────────────────────────────────────────────
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(
                onClick = { rawBuffer = ""; updateInput(0L) },
                modifier = Modifier.weight(1f),
            ) { Text("Clear") }
            Button(
                onClick = { updateInput(totalCents) },
                modifier = Modifier.weight(1f),
            ) { Text("Exact") }
        }
    }
}
