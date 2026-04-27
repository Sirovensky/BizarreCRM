package com.bizarreelectronics.crm.ui.components.shared

// NOTE: [BrandSkeleton] (shimmer list-row placeholder) lives in SharedComponents.kt
// (same package). This file adds two supplementary skeleton shapes for non-list
// contexts (card-grid and detail-screen header) so Wave 4 agents have composables
// to use without duplicating the shimmer logic.
//
// §66.2: "Skeleton shimmer ≤ 300ms before real data."
// The shimmer animation uses tween(durationMillis = 300) + RepeatMode.Reverse — the
// same spec as BrandSkeleton — so all skeletons share identical timing.

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp

/**
 * Shimmer placeholder for card-grid layouts (e.g. Reports screen, Dashboard tiles).
 *
 * Renders [columns] × [rows] rounded rectangle cards. Uses the same 300ms shimmer
 * timing as [BrandSkeleton].
 *
 * @param rows    Number of card rows.
 * @param columns Number of cards per row (default 2).
 * @param modifier Applied to the outer [Column].
 */
@Composable
fun CardGridSkeleton(
    rows: Int = 2,
    columns: Int = 2,
    modifier: Modifier = Modifier,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "cardGridSkeleton")
    val shimmerAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 300, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "shimmerAlpha",
    )
    val surface2 = MaterialTheme.colorScheme.surfaceVariant

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        repeat(rows) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                repeat(columns) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(80.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(surface2.copy(alpha = shimmerAlpha)),
                    )
                }
            }
        }
    }
}

/**
 * Shimmer placeholder for detail-screen headers (e.g. Customer detail,
 * Ticket detail — avatar + 2-line name / ID block).
 *
 * Wave 4 targets: CustomerDetailScreen, TicketDetailScreen.
 *
 * @param modifier Applied to the outer [Row].
 */
@Composable
fun DetailHeaderSkeleton(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "detailHeaderSkeleton")
    val shimmerAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 300, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "shimmerAlpha",
    )
    val surface2 = MaterialTheme.colorScheme.surfaceVariant
    val surfaceVar = MaterialTheme.colorScheme.surfaceContainerHigh

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Avatar placeholder
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(28.dp)) // circle
                .background(surface2.copy(alpha = shimmerAlpha)),
        )
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.55f)
                    .height(18.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(surface2.copy(alpha = shimmerAlpha)),
            )
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.35f)
                    .height(13.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(surfaceVar.copy(alpha = shimmerAlpha * 0.6f)),
            )
        }
        // Trailing action placeholder (e.g. call / sms buttons)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(2) {
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(surfaceVar.copy(alpha = shimmerAlpha * 0.5f)),
                )
            }
        }
    }
}
