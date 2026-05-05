package com.bizarreelectronics.crm.ui.screens.customers.healthscore

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.CustomerHealthScore
import com.bizarreelectronics.crm.data.remote.dto.HealthScoreComponent

/**
 * §45.1 — Customer Health Score screen.
 *
 * Displays:
 *  - Animated ring showing the 0–100 score with risk-tier tonal colour.
 *  - Row of four AssistChips for Recency / Frequency / Spend / Engagement.
 *  - "Explain" action opens a ModalBottomSheet with per-component breakdown.
 *  - "Recalculate" action calls POST …/health-score/recalculate.
 *
 * Route: Screen.CustomerHealthScore.createRoute(customerId)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerHealthScoreScreen(
    customerId: Long,
    onBack: () -> Unit,
    viewModel: CustomerHealthScoreViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(customerId) { viewModel.load(customerId) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_health_score)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
                actions = {
                    // Recalculate action
                    if (state.isRecalculating) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .padding(end = 12.dp)
                                .size(24.dp),
                            strokeWidth = 2.dp,
                        )
                    } else {
                        IconButton(
                            onClick = { viewModel.recalculate(customerId) },
                        ) {
                            Icon(
                                imageVector = Icons.Default.Refresh,
                                contentDescription = stringResource(R.string.cd_recalculate_health_score),
                            )
                        }
                    }
                    // Explanation sheet action
                    IconButton(onClick = { viewModel.openExplanationSheet() }) {
                        Icon(
                            imageVector = Icons.Default.Info,
                            contentDescription = stringResource(R.string.cd_health_score_explanation),
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
                        modifier = Modifier.semantics {
                            contentDescription = "Loading health score"
                        }
                    )
                }
            }

            state.healthScore == null && !state.isLoading -> {
                // 404-tolerant empty state
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = stringResource(R.string.health_score_unavailable),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                val hs = state.healthScore!!
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    // Ring
                    HealthScoreRing(score = hs.score, tier = hs.tier)

                    // Tier label
                    hs.tier?.let { tier ->
                        AssistChip(
                            onClick = {},
                            label = { Text(tier) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = tierContainerColor(tier),
                                labelColor = tierOnContainerColor(tier),
                            ),
                        )
                    }

                    // Last-calculated timestamp
                    hs.lastCalculatedAt?.let {
                        Text(
                            text = stringResource(R.string.health_score_last_calculated, it),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    // Component chips
                    val components = hs.components ?: defaultComponents(hs.score)
                    ComponentChipRow(components = components)

                    // Component breakdown card
                    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(vertical = 8.dp)) {
                            components.forEach { component ->
                                ComponentRow(component = component)
                            }
                        }
                    }

                    // Explanation
                    hs.explanation?.let { explanation ->
                        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                text = explanation,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.padding(16.dp),
                            )
                        }
                    }
                }
            }
        }

        // Explanation sheet
        if (state.showExplanationSheet) {
            val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
            ModalBottomSheet(
                onDismissRequest = { viewModel.dismissExplanationSheet() },
                sheetState = sheetState,
            ) {
                ExplanationSheetContent(
                    healthScore = state.healthScore,
                    onDismiss = { viewModel.dismissExplanationSheet() },
                )
            }
        }
    }
}

// ── Ring ──────────────────────────────────────────────────────────────────────

@Composable
private fun HealthScoreRing(
    score: Int,
    tier: String?,
    modifier: Modifier = Modifier,
) {
    val animatedSweep = remember { Animatable(0f) }
    LaunchedEffect(score) {
        animatedSweep.animateTo(
            targetValue = score.coerceIn(0, 100) / 100f * 270f,
            animationSpec = tween(durationMillis = 800),
        )
    }

    val trackColor = MaterialTheme.colorScheme.surfaceVariant
    val fillColor = tierRingColor(tier)
    val ringSize = 160.dp
    val strokeWidth = 16.dp

    val a11yDesc = "Health score: $score out of 100. Risk tier: ${tier ?: "unknown"}."

    Box(
        modifier = modifier
            .size(ringSize)
            .semantics { contentDescription = a11yDesc }
            .drawWithCache {
                val stroke = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
                val arcSize = Size(
                    size.width - strokeWidth.toPx(),
                    size.height - strokeWidth.toPx(),
                )
                val arcTopLeft = Offset(strokeWidth.toPx() / 2, strokeWidth.toPx() / 2)
                onDrawBehind {
                    // Track
                    drawArc(
                        color = trackColor,
                        startAngle = 135f,
                        sweepAngle = 270f,
                        useCenter = false,
                        topLeft = arcTopLeft,
                        size = arcSize,
                        style = stroke,
                    )
                    // Fill
                    drawArc(
                        color = fillColor,
                        startAngle = 135f,
                        sweepAngle = animatedSweep.value,
                        useCenter = false,
                        topLeft = arcTopLeft,
                        size = arcSize,
                        style = stroke,
                    )
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = score.toString(),
                style = MaterialTheme.typography.displayMedium.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "/ 100",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── Component chip row ────────────────────────────────────────────────────────

@Composable
private fun ComponentChipRow(components: List<HealthScoreComponent>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        components.take(4).forEach { component ->
            val pct = (component.score.toFloat() / component.maxScore.toFloat()).coerceIn(0f, 1f)
            AssistChip(
                onClick = {},
                label = {
                    Text(
                        text = "${component.name}\n${component.score}/${component.maxScore}",
                        style = MaterialTheme.typography.labelSmall,
                    )
                },
                colors = AssistChipDefaults.assistChipColors(
                    containerColor = when {
                        pct >= 0.7f -> MaterialTheme.colorScheme.tertiaryContainer
                        pct >= 0.4f -> MaterialTheme.colorScheme.primaryContainer
                        else -> MaterialTheme.colorScheme.errorContainer
                    },
                    labelColor = when {
                        pct >= 0.7f -> MaterialTheme.colorScheme.onTertiaryContainer
                        pct >= 0.4f -> MaterialTheme.colorScheme.onPrimaryContainer
                        else -> MaterialTheme.colorScheme.onErrorContainer
                    },
                ),
            )
        }
    }
}

// ── Component list row ────────────────────────────────────────────────────────

@Composable
private fun ComponentRow(component: HealthScoreComponent) {
    val pct = (component.score.toFloat() / component.maxScore.toFloat()).coerceIn(0f, 1f)
    val trackColor = MaterialTheme.colorScheme.surfaceVariant
    val fillColor = when {
        pct >= 0.7f -> MaterialTheme.colorScheme.tertiary
        pct >= 0.4f -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.error
    }

    ListItem(
        headlineContent = { Text(component.name) },
        supportingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                LinearProgressIndicator(
                    progress = { pct },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp)
                        .semantics { contentDescription = "${component.name}: ${component.score} of ${component.maxScore}" },
                    color = fillColor,
                    trackColor = trackColor,
                )
                component.explanation?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        trailingContent = {
            Text(
                text = "${component.score}",
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                color = fillColor,
            )
        },
    )
}

// ── Explanation sheet ─────────────────────────────────────────────────────────

@Composable
private fun ExplanationSheetContent(
    healthScore: CustomerHealthScore?,
    onDismiss: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = stringResource(R.string.health_score_explanation_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
        )

        val components = healthScore?.components ?: defaultComponents(healthScore?.score ?: 0)
        components.forEach { component ->
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = component.name,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            text = "${component.score} / ${component.maxScore}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    component.explanation?.let {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        healthScore?.explanation?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(modifier = Modifier.width(1.dp)) // bottom padding in sheet
    }
}

// ── Colour helpers ─────────────────────────────────────────────────────────────

@Composable
private fun tierRingColor(tier: String?) = when (tier?.lowercase()) {
    "healthy", "good", "excellent" -> MaterialTheme.colorScheme.tertiary
    "fair", "average", "moderate" -> MaterialTheme.colorScheme.primary
    "at-risk", "at risk", "poor", "low" -> MaterialTheme.colorScheme.error
    else -> MaterialTheme.colorScheme.primary
}

@Composable
private fun tierContainerColor(tier: String) = when (tier.lowercase()) {
    "healthy", "good", "excellent" -> MaterialTheme.colorScheme.tertiaryContainer
    "fair", "average", "moderate" -> MaterialTheme.colorScheme.primaryContainer
    else -> MaterialTheme.colorScheme.errorContainer
}

@Composable
private fun tierOnContainerColor(tier: String) = when (tier.lowercase()) {
    "healthy", "good", "excellent" -> MaterialTheme.colorScheme.onTertiaryContainer
    "fair", "average", "moderate" -> MaterialTheme.colorScheme.onPrimaryContainer
    else -> MaterialTheme.colorScheme.onErrorContainer
}

// ── Fallback components when server omits breakdown ───────────────────────────

private fun defaultComponents(totalScore: Int): List<HealthScoreComponent> {
    val each = (totalScore / 4f).toInt()
    return listOf(
        HealthScoreComponent("Recency", each, 25),
        HealthScoreComponent("Frequency", each, 25),
        HealthScoreComponent("Spend", each, 25),
        HealthScoreComponent("Engagement", totalScore - each * 3, 25),
    )
}
