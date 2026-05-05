package com.bizarreelectronics.crm.ui.screens.activity.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * §3.16 L596 — Emoji reaction row shown below each activity event.
 *
 * Supported reactions: 👍 🎉 ✅
 * Tapping an emoji POSTs to /activity/{id}/reactions; 404 is silently tolerated.
 * Count badge is shown when > 0.
 *
 * ReduceMotion: color animation duration collapses to 0ms when reduce motion is active
 * so users who opt out of motion don't experience the color pulse.
 *
 * @param eventId         Server-assigned ID of the activity event.
 * @param reactions       Current emoji → count map (may be empty).
 * @param onReact         Called with (eventId, emoji) when the user taps a reaction.
 * @param reduceMotion    True when system/app reduce-motion preference is on.
 */
@Composable
fun EventReactionRow(
    eventId: Long,
    reactions: Map<String, Int>,
    onReact: (Long, String) -> Unit,
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current

    Row(
        modifier = modifier.padding(top = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SUPPORTED_REACTIONS.forEach { emoji ->
            ReactionChip(
                emoji = emoji,
                count = reactions[emoji] ?: 0,
                reduceMotion = reduceMotion,
                onClick = { onReact(eventId, emoji) },
            )
        }
    }
}

@Composable
private fun ReactionChip(
    emoji: String,
    count: Int,
    reduceMotion: Boolean,
    onClick: () -> Unit,
) {
    val hasReactions = count > 0
    val animDuration = if (reduceMotion) 0 else 180

    val containerColor by animateColorAsState(
        targetValue = if (hasReactions) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        },
        animationSpec = tween(durationMillis = animDuration),
        label = "reactionColor_$emoji",
    )

    val label = buildString {
        append(emoji)
        if (count > 0) append(" $count")
        append(" reaction")
    }

    Surface(
        shape = RoundedCornerShape(12.dp),
        color = containerColor,
        modifier = Modifier
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = label
                role = Role.Button
            },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(text = emoji, fontSize = 13.sp)
            if (count > 0) {
                Text(
                    text = count.toString(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }
    }
}

/** The three canonical emoji reactions surfaced in the UI. */
private val SUPPORTED_REACTIONS = listOf("👍", "🎉", "✅")
