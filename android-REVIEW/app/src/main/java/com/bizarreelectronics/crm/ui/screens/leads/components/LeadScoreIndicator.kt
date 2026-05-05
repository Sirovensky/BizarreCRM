package com.bizarreelectronics.crm.ui.screens.leads.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Circular progress ring displaying a 0-100 lead score (ActionPlan §9 L1392).
 *
 * Tap triggers an explanation [ModalBottomSheet] describing what factors
 * contribute to the score. The ring uses [CircularProgressIndicator] with
 * the track color set to surfaceVariant so the empty portion is always visible.
 *
 * ReduceMotion: [CircularProgressIndicator] uses no entrance animation by
 * default — the composable simply renders at the target progress value.
 *
 * @param score     0–100 integer score. Values outside that range are clamped.
 * @param size      Diameter of the ring. Defaults to 56.dp for list use; 72.dp for detail.
 * @param showLabel Whether to render the numeric label inside the ring.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeadScoreIndicator(
    score: Int,
    modifier: Modifier = Modifier,
    size: Dp = 56.dp,
    showLabel: Boolean = true,
) {
    val clamped = score.coerceIn(0, 100)
    val progress = clamped / 100f

    // Colour the ring based on band: <40 error-red, 40-69 warning-amber, 70+ primary-purple
    val ringColor = when {
        clamped >= 70 -> MaterialTheme.colorScheme.primary
        clamped >= 40 -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.error
    }

    var showExplanation by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()

    val a11yLabel = "Lead score $clamped out of 100. Tap for explanation."

    Box(
        modifier = modifier
            .size(size)
            .clickable { showExplanation = true }
            .semantics { contentDescription = a11yLabel },
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(
            progress = { progress },
            modifier = Modifier
                .size(size),
            color = ringColor,
            trackColor = MaterialTheme.colorScheme.surfaceVariant,
            strokeWidth = (size.value * 0.08f).dp,
        )
        if (showLabel) {
            Text(
                text = clamped.toString(),
                style = MaterialTheme.typography.labelMedium.copy(
                    fontSize = (size.value * 0.22f).sp,
                ),
                fontWeight = FontWeight.Bold,
                color = ringColor,
            )
        }
    }

    if (showExplanation) {
        ModalBottomSheet(
            onDismissRequest = { showExplanation = false },
            sheetState = sheetState,
        ) {
            LeadScoreExplanationSheet(score = clamped)
        }
    }
}

/**
 * Bottom-sheet content explaining the lead score breakdown.
 * Factors are heuristic until the server exposes a /leads/:id/score-factors endpoint.
 */
@Composable
private fun LeadScoreExplanationSheet(score: Int) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Lead Score: $score / 100",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "The lead score reflects engagement and qualification signals:",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        ScoreFactorRow("Contact info completeness", "Name, phone, email all present")
        ScoreFactorRow("Stage progress", "Further in pipeline = higher score")
        ScoreFactorRow("Source quality", "Referral and direct score higher")
        ScoreFactorRow("Recent activity", "Leads updated recently score higher")
        ScoreFactorRow("Appointment booked", "+10 when an appointment is scheduled")
        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun ScoreFactorRow(factor: String, description: String) {
    Column {
        Text(
            text = factor,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
        )
        Text(
            text = description,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
