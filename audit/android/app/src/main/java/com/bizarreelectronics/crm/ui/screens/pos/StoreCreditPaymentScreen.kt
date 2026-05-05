package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Placeholder screen for the store-credit payment flow (AUDIT-030).
 *
 * The cashier lands here when they tap the "Store credit · payment" path tile
 * after a customer is attached. This screen will eventually let the cashier
 * apply an outstanding store-credit balance against the current cart total.
 *
 * TODO: implement payment flow — call store-credit debit endpoint, re-seed
 *   the coordinator with the remaining balance, then navigate to PosTender.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoreCreditPaymentScreen(
    onBack: () -> Unit = {},
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Store credit payment") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            Text(
                "💳",
                style = MaterialTheme.typography.displayMedium,
            )
            Text(
                "Store credit payment",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "Customer pays an outstanding balance using store credit.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.weight(1f))

            // TODO: implement payment flow
            Button(
                onClick = { /* TODO: debit store credit and navigate to tender */ },
                modifier = Modifier.fillMaxWidth(),
                enabled = false,
            ) {
                Text("Apply store credit")
            }
        }
    }
}
