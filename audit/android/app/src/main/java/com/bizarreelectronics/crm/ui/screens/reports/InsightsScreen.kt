package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.dashboard.components.BusyHoursHeatmap

/**
 * Insights / BI report screen (ActionPlan §15.7).
 *
 * Surfaces:
 *   - BusyHoursHeatmap — 7×24 Canvas grid loaded from `GET /reports/busy-hours-heatmap`.
 *   - Additional BI cards (Churn, Forecast, Missing Parts) are shared with Dashboard §3.2
 *     and are shown as informational pointers here.
 *
 * Data is loaded on-demand via [ReportsViewModel.loadBusyHoursHeatmap].
 * 404 from the server → empty heatmap state (stub rendering).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsightsScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        if (state.busyHoursData.isEmpty() && !state.isBusyHoursLoading) {
            viewModel.loadBusyHoursHeatmap()
        }
    }

    Scaffold(
        topBar = { BrandTopAppBar(title = "Insights") },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Busy Hours heatmap ────────────────────────────────────────────
            item {
                Text(
                    "Busy Hours",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
            }
            item {
                when {
                    state.isBusyHoursLoading -> {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 24.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.semantics {
                                    contentDescription = "Loading busy hours heatmap"
                                },
                            )
                        }
                    }
                    state.busyHoursError != null -> {
                        ErrorState(
                            message = state.busyHoursError ?: "Failed to load heatmap.",
                            onRetry = { viewModel.loadBusyHoursHeatmap() },
                        )
                    }
                    else -> {
                        // BusyHoursHeatmap handles empty-array stub state internally.
                        BusyHoursHeatmap(data = state.busyHoursData)
                    }
                }
            }

            // ── BI summary cards ──────────────────────────────────────────────
            item {
                Text(
                    "Business Intelligence",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .semantics { heading() },
                )
            }

            item {
                InsightCard(
                    title = "Profit Overview",
                    body = "Gross / net profit trend and margin tracking — available via the Dashboard's Profit Hero widget.",
                )
            }

            item {
                InsightCard(
                    title = "Customer Churn",
                    body = "Customers not returning within 90 days — available via the Dashboard's Churn widget.",
                )
            }

            item {
                InsightCard(
                    title = "Revenue Forecast",
                    body = "30-day forward revenue projection based on ticket pipeline — available via the Dashboard's Forecast widget.",
                )
            }

            item {
                InsightCard(
                    title = "Missing Parts Alerts",
                    body = "Tickets blocked on missing parts — available via the Dashboard's Missing Parts widget.",
                )
            }

            // ── Trend indicator ───────────────────────────────────────────────
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.TrendingUp,
                            contentDescription = "Insights trend",
                            tint = MaterialTheme.colorScheme.onPrimaryContainer,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            "Full AI-powered insights",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                        Text(
                            "Anomaly detection, predictive restock, and NPS trend analysis are on the roadmap. " +
                                "Check the Dashboard for the current set of live widgets.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun InsightCard(title: String, body: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                body,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
