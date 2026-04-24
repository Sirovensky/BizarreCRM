package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

/**
 * Phase 3 stub — full check-in checkout flow will replace this composable.
 *
 * Previously held the ticket-checkout UX. Retained as a no-op stub so
 * AppNavGraph's `Screen.Checkout` route compiles until Phase 3 lands the
 * full 6-step check-in module.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckoutScreen(
    ticketId: Long,
    total: Double,
    customerName: String,
    onBack: () -> Unit,
    onSuccess: (Long) -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Checkout · #$ticketId") },
                navigationIcon = {
                    Button(onClick = onBack) { Text("‹") }
                },
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.Center,
        ) {
            // Phase 3 will implement the full checkout experience here.
            Text("Checkout coming in Phase 3")
        }
    }
}
