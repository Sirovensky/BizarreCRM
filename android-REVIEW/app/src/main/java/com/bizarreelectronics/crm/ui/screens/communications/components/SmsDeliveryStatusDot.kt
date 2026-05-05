package com.bizarreelectronics.crm.ui.screens.communications.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.BrandMono

/**
 * Small delivery status indicator rendered inside outbound message bubbles.
 *
 * Status mapping:
 *   sending / pending / queued  → gray pulsing single dot
 *   sent                        → single gray check
 *   delivered                   → double gray check
 *   failed                      → red "!" icon
 *   read                        → double blue check
 *
 * [readAt] non-null while status == "delivered" → renders "Read HH:MM" caption.
 */
@Composable
fun SmsDeliveryStatusDot(
    status: String?,
    readAt: String? = null,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme

    when (status) {
        "pending", "queued", "sending" -> PulsingDot(modifier = modifier)

        "sent" -> Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "Sent",
                modifier = Modifier.size(12.dp),
                tint = scheme.onSurfaceVariant.copy(alpha = 0.6f),
            )
        }

        "delivered" -> Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
            DoubleCheck(tint = scheme.onSurfaceVariant.copy(alpha = 0.6f))
            if (readAt != null) {
                Spacer(Modifier.width(4.dp))
                Text(
                    text = "Read ${readAt.takeLast(5)}",
                    style = BrandMono.copy(fontSize = MaterialTheme.typography.labelSmall.fontSize),
                    color = scheme.primary,
                )
            }
        }

        "read" -> Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
            DoubleCheck(tint = scheme.primary)
        }

        "failed" -> Icon(
            imageVector = Icons.Default.Close,
            contentDescription = "Failed",
            modifier = modifier.size(12.dp),
            tint = scheme.error,
        )

        else -> { /* unknown status: render nothing */ }
    }
}

@Composable
private fun PulsingDot(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse_alpha",
    )
    Icon(
        imageVector = Icons.Default.Check,
        contentDescription = "Sending",
        modifier = modifier
            .size(12.dp)
            .alpha(alpha),
        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
    )
}

@Composable
private fun DoubleCheck(tint: Color) {
    Row {
        Icon(
            imageVector = Icons.Default.Check,
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = tint,
        )
        Spacer(Modifier.width((-4).dp))
        Icon(
            imageVector = Icons.Default.Check,
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = tint,
        )
    }
}
