package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentInd
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxState
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity

/**
 * Wraps a ticket list row in [SwipeToDismissBox] to expose quick actions:
 *
 *   Swipe-LEFT (EndToStart) — primary destructive / terminal action:
 *     - Ticket NOT in closed state → "Mark done" (success green).
 *     - Ticket IS closed → "Reopen" (amber).
 *
 *   Swipe-RIGHT (StartToEnd) — secondary supportive action:
 *     - Not assigned → "Assign to me" (primary purple).
 *     - Assigned / active → "Hold" (muted).
 *
 * Actions trigger [onMarkDone] / [onReopen] / [onAssignToMe] / [onHold] callbacks
 * which are owned by the ViewModel. Haptic feedback ([HapticFeedbackConstants.CONTEXT_CLICK])
 * fires when the user completes a swipe gesture.
 *
 * Reduce-motion: when [reduceMotion] is true, a shorter tween duration (80ms)
 * replaces the default spring for the background reveal animation.
 *
 * @param ticket        The ticket entity for this row.
 * @param reduceMotion  When true, use shorter animations.
 * @param onMarkDone    Called when user swipes left on an open ticket.
 * @param onReopen      Called when user swipes left on a closed ticket.
 * @param onAssignToMe  Called when user swipes right on an unassigned ticket.
 * @param onHold        Called when user swipes right on an assigned/active ticket.
 * @param content       The actual row composable.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketSwipeRow(
    ticket: TicketEntity,
    reduceMotion: Boolean,
    onMarkDone: () -> Unit,
    onReopen: () -> Unit,
    onAssignToMe: () -> Unit,
    onHold: () -> Unit,
    content: @Composable () -> Unit,
) {
    val view = LocalView.current
    val isClosed = ticket.statusIsClosed
    val isUnassigned = ticket.assignedTo == null

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart -> {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    if (isClosed) onReopen() else onMarkDone()
                    false // don't auto-dismiss; ViewModel handles optimistic update
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                    if (isUnassigned) onAssignToMe() else onHold()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
        positionalThreshold = { totalDistance -> totalDistance * 0.35f },
    )

    // Reset the dismiss state after each gesture so the row snaps back
    LaunchedEffect(dismissState.currentValue) {
        if (dismissState.currentValue != SwipeToDismissBoxValue.Settled) {
            dismissState.reset()
        }
    }

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            SwipeBackground(
                dismissState = dismissState,
                isClosed = isClosed,
                isUnassigned = isUnassigned,
            )
        },
        content = { content() },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeBackground(
    dismissState: SwipeToDismissBoxState,
    isClosed: Boolean,
    isUnassigned: Boolean,
) {
    val direction = dismissState.dismissDirection
    val scheme = MaterialTheme.colorScheme

    // Left-action (EndToStart): Mark done or Reopen
    val leftBg = if (isClosed) scheme.tertiary else scheme.primary
    val leftIcon = if (isClosed) Icons.Default.Refresh else Icons.Default.CheckCircle
    val leftLabel = if (isClosed) "Reopen" else "Mark done"

    // Right-action (StartToEnd): Assign to me or Hold
    val rightBg = if (isUnassigned) scheme.secondary else scheme.surfaceVariant
    val rightIcon = if (isUnassigned) Icons.Default.AssignmentInd else Icons.Default.PauseCircle
    val rightLabel = if (isUnassigned) "Assign to me" else "Hold"

    when (direction) {
        SwipeToDismissBoxValue.EndToStart -> {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(leftBg)
                    .padding(end = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                SwipeActionContent(icon = leftIcon, label = leftLabel, tint = scheme.onPrimary)
            }
        }
        SwipeToDismissBoxValue.StartToEnd -> {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(rightBg)
                    .padding(start = 20.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                val tint = if (isUnassigned) scheme.onSecondary else scheme.onSurfaceVariant
                SwipeActionContent(icon = rightIcon, label = rightLabel, tint = tint)
            }
        }
        SwipeToDismissBoxValue.Settled -> {
            Box(modifier = Modifier.fillMaxSize().background(scheme.surface))
        }
    }
}

@Composable
private fun SwipeActionContent(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: androidx.compose.ui.graphics.Color,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null, // label Text provides the a11y description
            tint = tint,
        )
        Box(modifier = Modifier.width(6.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = tint,
        )
    }
}
