package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 4 — Payment methods.
 *
 * Presents Cash, Card, and Other as toggleable chips. At least one must be
 * selected or the user must tap Skip.
 *
 * Server contract (step_index=4):
 *   { payment_methods: "cash,card" }  — comma-separated selected methods
 *   { skipped: "true" }               — when skipping
 *
 * TODO: Add custom payment-method entry (e.g. Interac, Store Credit) when
 * the payment-method editor is built in a future wave.
 *
 * [data] — current saved values; parsed to restore checkbox state.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun PaymentMethodsStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val savedMethods = data["payment_methods"]?.toString()?.split(",")?.toSet() ?: setOf("cash", "card")
    var cash    by remember { mutableStateOf("cash"  in savedMethods) }
    var card    by remember { mutableStateOf("card"  in savedMethods) }
    var other   by remember { mutableStateOf("other" in savedMethods) }
    var skipped by remember { mutableStateOf(data["skipped"] == "true") }

    fun emit() {
        if (skipped) {
            onDataChange(mapOf("skipped" to "true"))
            return
        }
        val selected = buildList {
            if (cash)  add("cash")
            if (card)  add("card")
            if (other) add("other")
        }.joinToString(",")
        onDataChange(mapOf("payment_methods" to selected))
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Payment Methods", style = MaterialTheme.typography.titleLarge)
        Text(
            "Which payment methods does your shop accept?",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        FilterChip(selected = cash,  onClick = { cash  = !cash;  skipped = false; emit() }, label = { Text("Cash")  })
        FilterChip(selected = card,  onClick = { card  = !card;  skipped = false; emit() }, label = { Text("Card")  })
        FilterChip(selected = other, onClick = { other = !other; skipped = false; emit() }, label = { Text("Other") })

        // TODO: Add custom payment-method row editor (future wave).

        OutlinedButton(onClick = { skipped = true; emit() }) {
            Text("Skip for now")
        }
    }
}
