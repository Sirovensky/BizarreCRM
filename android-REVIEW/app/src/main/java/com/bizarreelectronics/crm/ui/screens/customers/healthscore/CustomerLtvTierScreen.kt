package com.bizarreelectronics.crm.ui.screens.customers.healthscore

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MonetizationOn
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import java.text.NumberFormat
import java.util.Locale

/**
 * §45.2 — Customer LTV Tier screen.
 *
 * Displays:
 *  - Tier chip (VIP / Regular / At-Risk) using tonal color pairs from M3.
 *  - Lifetime value formatted as USD currency.
 *  - Explanation text when the server provides it.
 *
 * Note: tier threshold configuration ("VIP ≥ $1000") lives server-side.
 * Auto-apply pricing rules by tier is server-side.
 *
 * Route: Screen.CustomerLtvTier.createRoute(customerId)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerLtvTierScreen(
    customerId: Long,
    onBack: () -> Unit,
    viewModel: CustomerLtvTierViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(customerId) { viewModel.load(customerId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_ltv_tier)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.semantics { contentDescription = "Loading LTV tier" }
                    )
                }
            }

            state.ltvTier == null && !state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = stringResource(R.string.ltv_tier_unavailable),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                val ltv = state.ltvTier!!
                val currencyFormat = NumberFormat.getCurrencyInstance(Locale.US)
                // lifetimeValue from server is a double (dollars); multiply by 100 for cents
                // then format back to dollars for display.
                val lifetimeValueCents = (ltv.lifetimeValue * 100).toLong()
                val formattedLtv = currencyFormat.format(lifetimeValueCents / 100.0)

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    // Tier chip (large, centered)
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                text = ltv.tier,
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                ),
                            )
                        },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.MonetizationOn,
                                contentDescription = stringResource(R.string.cd_ltv_tier_icon),
                                modifier = Modifier.padding(start = 4.dp),
                            )
                        },
                        colors = AssistChipDefaults.assistChipColors(
                            containerColor = ltvTierContainerColor(ltv.tier),
                            labelColor = ltvTierOnContainerColor(ltv.tier),
                            leadingIconContentColor = ltvTierOnContainerColor(ltv.tier),
                        ),
                        modifier = Modifier.semantics {
                            contentDescription = "LTV tier: ${ltv.tier}"
                        },
                    )

                    // Lifetime value card
                    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                        ListItem(
                            headlineContent = {
                                Text(stringResource(R.string.ltv_lifetime_value_label))
                            },
                            trailingContent = {
                                Text(
                                    text = formattedLtv,
                                    style = MaterialTheme.typography.titleLarge.copy(
                                        fontWeight = FontWeight.Bold,
                                    ),
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                            },
                        )
                    }

                    // Explanation
                    ltv.explanation?.let { explanation ->
                        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    text = stringResource(R.string.ltv_tier_explanation_title),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = explanation,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                        }
                    }

                    // Info note about server-side thresholds
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            text = stringResource(R.string.ltv_tier_threshold_note),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// ── Colour helpers ─────────────────────────────────────────────────────────────

@Composable
private fun ltvTierContainerColor(tier: String) = when (tier.lowercase()) {
    "vip" -> MaterialTheme.colorScheme.tertiaryContainer
    "regular" -> MaterialTheme.colorScheme.primaryContainer
    "at-risk", "at risk" -> MaterialTheme.colorScheme.errorContainer
    else -> MaterialTheme.colorScheme.surfaceVariant
}

@Composable
private fun ltvTierOnContainerColor(tier: String) = when (tier.lowercase()) {
    "vip" -> MaterialTheme.colorScheme.onTertiaryContainer
    "regular" -> MaterialTheme.colorScheme.onPrimaryContainer
    "at-risk", "at risk" -> MaterialTheme.colorScheme.onErrorContainer
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}
