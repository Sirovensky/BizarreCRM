package com.bizarreelectronics.crm.ui.screens.team.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddReaction
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.TeamChatMessage
import com.bizarreelectronics.crm.data.remote.api.TeamChatReaction
import com.bizarreelectronics.crm.util.MarkdownLiteParser

// ─── Reaction chips ──────────────────────────────────────────────────────────

/**
 * Horizontal row of emoji reaction chips for a message.
 * Shows a "+" button to add a new reaction when [onAdd] is provided.
 */
@Composable
fun ReactionRow(
    reactions: List<TeamChatReaction>,
    onToggle: (emoji: String) -> Unit,
    onAdd: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    if (reactions.isEmpty() && onAdd == null) return

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        reactions.forEach { reaction ->
            ReactionChip(
                reaction = reaction,
                onToggle = { onToggle(reaction.emoji) },
            )
        }
        if (onAdd != null) {
            IconButton(
                onClick = onAdd,
                modifier = Modifier.size(28.dp),
            ) {
                Icon(
                    Icons.Default.AddReaction,
                    contentDescription = "Add reaction",
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ReactionChip(
    reaction: TeamChatReaction,
    onToggle: () -> Unit,
) {
    val background = if (reaction.reactedByMe) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        MaterialTheme.colorScheme.surfaceContainerHigh
    }

    Surface(
        shape = RoundedCornerShape(12.dp),
        color = background,
        modifier = Modifier
            .clickable(onClick = onToggle)
            .semantics { contentDescription = "${reaction.emoji} ${reaction.count} reactions" },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(reaction.emoji, style = MaterialTheme.typography.bodySmall)
            Text(
                "${reaction.count}",
                style = MaterialTheme.typography.labelSmall,
                color = if (reaction.reactedByMe) MaterialTheme.colorScheme.onPrimaryContainer
                else MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = if (reaction.reactedByMe) FontWeight.SemiBold else FontWeight.Normal,
            )
        }
    }
}

// ─── Reaction picker sheet ────────────────────────────────────────────────────

private val TEAM_EMOJI = listOf("👍", "✅", "🎉", "❤️", "🔥", "😂", "😢", "🤔", "👀", "🚀")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReactionPickerSheet(
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
        ) {
            Text("React", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                TEAM_EMOJI.forEach { emoji ->
                    TextButton(onClick = { onSelect(emoji) }) {
                        Text(emoji, style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

/**
 * Chat message bubble reusing the SMS bubble visual language.
 * @param isMe  true when the message was sent by the current user.
 * @param onLongPress  optional long-press callback (used to show reaction picker).
 */
@Composable
fun TeamMessageBubble(
    message: TeamChatMessage,
    isMe: Boolean,
    onReactionToggle: (emoji: String) -> Unit = {},
    onLongPress: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val bubbleShape = RoundedCornerShape(
        topStart = 14.dp,
        topEnd = 14.dp,
        bottomStart = if (isMe) 14.dp else 2.dp,
        bottomEnd = if (isMe) 2.dp else 14.dp,
    )
    val bubbleBg = if (isMe) MaterialTheme.colorScheme.primaryContainer
    else MaterialTheme.colorScheme.surfaceContainerHigh
    val textColor = if (isMe) MaterialTheme.colorScheme.onPrimaryContainer
    else MaterialTheme.colorScheme.onSurface

    val timeDisplay = message.createdAt.take(16).replace("T", " ")
    val bodyAnnotated = MarkdownLiteParser.parse(
        message.body,
        linkColor = MaterialTheme.colorScheme.primary,
    )
    val a11yLabel = "${if (isMe) "You" else message.authorName} at $timeDisplay: ${message.body}"

    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = if (isMe) Alignment.End else Alignment.Start,
    ) {
        // Author name (not shown for self)
        if (!isMe) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(start = 4.dp, bottom = 2.dp),
            ) {
                AvatarInitial(name = message.authorName, size = 20)
                Text(
                    message.authorName,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        Box(
            modifier = Modifier
                .widthIn(max = 280.dp)
                .clip(bubbleShape)
                .background(bubbleBg)
                .padding(12.dp)
                .semantics { contentDescription = a11yLabel }
                .then(if (onLongPress != null) Modifier.clickable(onClick = onLongPress) else Modifier),
        ) {
            Column {
                Text(
                    text = bodyAnnotated,
                    color = textColor,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    timeDisplay,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isMe) MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                )
            }
        }

        if (message.reactions.isNotEmpty()) {
            ReactionRow(
                reactions = message.reactions,
                onToggle = onReactionToggle,
                modifier = Modifier.padding(top = 2.dp, start = if (!isMe) 4.dp else 0.dp),
            )
        }

        if (message.isPinned) {
            Text(
                "Pinned",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

// ─── Avatar initial ──────────────────────────────────────────────────────────

@Composable
fun AvatarInitial(name: String, size: Int = 36) {
    val initial = name.firstOrNull()?.uppercaseChar()?.toString() ?: "?"
    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initial,
            style = if (size >= 32) MaterialTheme.typography.labelLarge
            else MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
