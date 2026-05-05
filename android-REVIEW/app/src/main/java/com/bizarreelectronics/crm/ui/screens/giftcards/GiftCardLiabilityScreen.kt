package com.bizarreelectronics.crm.ui.screens.giftcards

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Gift-card and store-credit liability reconciliation screen.
 *
 * §40.4 — Reports on gift-card liability (outstanding balance owed to customers)
 * and store-credit liability.
 *
 * Data source:
 *  - Gift card total: [GiftCardLiabilityViewModel.giftCardState] → [GiftCardLiabilityApi]
 *    GET /gift-cards returns summary.total_outstanding (floating dollars).
 *  - Store-credit total: not yet available as a dedicated summary endpoint;
 *    aggregate is derived from the gift-cards summary response.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GiftCardLiabilityScreen(
    onBack: () -> Unit,
    viewModel: GiftCardLiabilityViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state) {
        if (state is LiabilityState.Error) {
            snackbarHostState.showSnackbar((state as LiabilityState.Error).message)
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Liability Report",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when (val s = state) {
            is LiabilityState.Loading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }
            }
            is LiabilityState.NotAvailable -> {
                Column(modifier = Modifier.padding(padding).padding(16.dp)) {
                    BrandCard(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(24.dp).fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.BarChart,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(40.dp),
                            )
                            Text(
                                "Liability report not available on this server",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            is LiabilityState.Error -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        s.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    OutlinedButton(onClick = { viewModel.refresh() }) { Text("Retry") }
                }
            }
            is LiabilityState.Loaded -> LiabilityContent(
                state = s,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        }
    }
}

// ─── Content ──────────────────────────────────────────────────────────────────

@Composable
private fun LiabilityContent(
    state: LiabilityState.Loaded,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            "Outstanding liabilities",
            style = MaterialTheme.typography.titleMedium,
        )

        // §40.4 — Gift-card liability card
        LiabilityCard(
            icon = Icons.Default.CardGiftcard,
            iconDescription = "Gift cards",
            title = "Gift Card Liability",
            subtitle = "${state.activeGiftCardCount} active card(s)",
            amountCents = state.giftCardOutstandingCents,
            accentContainer = MaterialTheme.colorScheme.primaryContainer,
            accentOnContainer = MaterialTheme.colorScheme.onPrimaryContainer,
        )

        // §40.4 — Store-credit liability card
        LiabilityCard(
            icon = Icons.Default.Loyalty,
            iconDescription = "Store credit",
            title = "Store Credit Liability",
            subtitle = "Cumulative unspent balance",
            amountCents = state.storeCreditOutstandingCents,
            accentContainer = MaterialTheme.colorScheme.secondaryContainer,
            accentOnContainer = MaterialTheme.colorScheme.onSecondaryContainer,
        )

        // Combined total
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.padding(16.dp).fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Total Liability",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    (state.giftCardOutstandingCents + state.storeCreditOutstandingCents)
                        .formatAsMoney(),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }

        Text(
            "Gift-card balance owed to customers represents unredeemed value. " +
                "Store-credit balance represents credit issued via refunds or goodwill.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun LiabilityCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconDescription: String,
    title: String,
    subtitle: String,
    amountCents: Long,
    accentContainer: androidx.compose.ui.graphics.Color,
    accentOnContainer: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier,
) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = accentContainer,
                modifier = Modifier.size(40.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        icon,
                        contentDescription = iconDescription,
                        tint = accentOnContainer,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                amountCents.formatAsMoney(),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
