package com.bizarreelectronics.crm.ui.screens.team.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddReaction
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.TeamChatMessage
import com.bizarreelectronics.crm.data.remote.api.TeamChatReaction
import com.bizarreelectronics.crm.util.MarkdownLiteParser

// ─── §47.3 Task embed — inline @ticket / @customer mini-cards ────────────────

/**
 * Parsed segment from a chat message body.
 *
 * Plain text segments are rendered via [MarkdownLiteParser]; ticket and
 * customer embed segments are rendered as tappable [OutlinedCard] mini-chips.
 */
sealed interface ChatSegment {
    /** A run of plain / markdown text. */
    data class Text(val value: String) : ChatSegment

    /**
     * `@ticket <id>` embed.
     * @param ticketId  The numeric ticket id extracted from the mention.
     * @param label     Raw token as it appeared in the message (e.g. "@ticket 4821").
     */
    data class TicketEmbed(val ticketId: Long, val label: String) : ChatSegment

    /**
     * `@customer <name>` embed.
     * @param customerName  The name token following @customer.
     * @param label         Raw token as it appeared in the message.
     */
    data class CustomerEmbed(val customerName: String, val label: String) : ChatSegment
}

private val TICKET_RE = Regex("""@ticket\s+(\d+)""", RegexOption.IGNORE_CASE)
private val CUSTOMER_RE = Regex("""@customer\s+([A-Za-z0-9 _\-]+)""", RegexOption.IGNORE_CASE)

/**
 * Splits a chat message body into a list of [ChatSegment]s.
 *
 * Patterns are matched in document order; overlapping matches are not
 * possible because each pattern is consumed as it is found.  Text between
 * embed tokens (and any trailing text) is emitted as [ChatSegment.Text].
 */
fun parseChatSegments(body: String): List<ChatSegment> {
    if (body.isBlank()) return listOf(ChatSegment.Text(body))

    // Combine the two embed patterns into a single alternation so we process
    // them in document order without a second pass.
    val combined = Regex(
        """(@ticket\s+\d+)|(@customer\s+[A-Za-z0-9 _\-]+)""",
        RegexOption.IGNORE_CASE,
    )

    val segments = mutableListOf<ChatSegment>()
    var cursor = 0

    for (match in combined.findAll(body)) {
        // Emit leading text before this embed
        if (match.range.first > cursor) {
            segments += ChatSegment.Text(body.substring(cursor, match.range.first))
        }
        val token = match.value
        when {
            TICKET_RE.matches(token) -> {
                val id = TICKET_RE.find(token)!!.groupValues[1].toLongOrNull() ?: 0L
                segments += ChatSegment.TicketEmbed(ticketId = id, label = token)
            }
            CUSTOMER_RE.matches(token) -> {
                val name = CUSTOMER_RE.find(token)!!.groupValues[1].trim()
                segments += ChatSegment.CustomerEmbed(customerName = name, label = token)
            }
            else -> segments += ChatSegment.Text(token)
        }
        cursor = match.range.last + 1
    }
    if (cursor < body.length) {
        segments += ChatSegment.Text(body.substring(cursor))
    }
    return segments
}

/**
 * Renders a chat message body as a vertical sequence of text runs and
 * inline embed mini-cards.
 *
 * @param body          Raw message body string.
 * @param linkColor     Color applied to auto-detected links inside text segments.
 * @param onTicketClick Called with the ticket id when a ticket embed is tapped.
 * @param onCustomerClick Called with the customer name when a customer embed is tapped.
 */
@Composable
fun TeamMessageBody(
    body: String,
    linkColor: Color,
    onTicketClick: ((ticketId: Long) -> Unit)? = null,
    onCustomerClick: ((name: String) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val segments = remember(body) { parseChatSegments(body) }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        segments.forEach { segment ->
            when (segment) {
                is ChatSegment.Text -> {
                    val annotated = remember(segment.value, linkColor) {
                        MarkdownLiteParser.parse(segment.value, linkColor)
                    }
                    if (annotated.text.isNotEmpty()) {
                        Text(
                            text = annotated,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
                is ChatSegment.TicketEmbed -> {
                    TicketEmbedChip(
                        ticketId = segment.ticketId,
                        onClick = if (onTicketClick != null) {
                            { onTicketClick(segment.ticketId) }
                        } else null,
                    )
                }
                is ChatSegment.CustomerEmbed -> {
                    CustomerEmbedChip(
                        name = segment.customerName,
                        onClick = if (onCustomerClick != null) {
                            { onCustomerClick(segment.customerName) }
                        } else null,
                    )
                }
            }
        }
    }
}

/**
 * `@ticket NNNN` mini-card.  Tappable if [onClick] is provided.
 */
@Composable
fun TicketEmbedChip(
    ticketId: Long,
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val a11y = "Ticket $ticketId. ${if (onClick != null) "Tap to open." else ""}"
    OutlinedCard(
        modifier = modifier
            .then(
                if (onClick != null) Modifier.clickable(onClick = onClick)
                else Modifier,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = a11y
                if (onClick != null) role = Role.Button
            },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.ConfirmationNumber,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                "#$ticketId",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

/**
 * `@customer Name` mini-card with avatar initial.  Tappable if [onClick] is provided.
 */
@Composable
fun CustomerEmbedChip(
    name: String,
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val a11y = "Customer $name. ${if (onClick != null) "Tap to open." else ""}"
    OutlinedCard(
        modifier = modifier
            .then(
                if (onClick != null) Modifier.clickable(onClick = onClick)
                else Modifier,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = a11y
                if (onClick != null) role = Role.Button
            },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Person,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.secondary,
            )
            Text(
                name,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

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
 *
 * @param isMe           True when the message was sent by the current user.
 * @param onLongPress    Optional long-press callback (used to show reaction picker).
 * @param onTicketClick  Called with the ticket id when an `@ticket NNNN` embed is tapped.
 *                       Null suppresses tappability (embed still renders as non-interactive chip).
 * @param onCustomerClick Called with the customer name when an `@customer Name` embed is tapped.
 */
@Composable
fun TeamMessageBubble(
    message: TeamChatMessage,
    isMe: Boolean,
    onReactionToggle: (emoji: String) -> Unit = {},
    onLongPress: (() -> Unit)? = null,
    onTicketClick: ((ticketId: Long) -> Unit)? = null,
    onCustomerClick: ((name: String) -> Unit)? = null,
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

    val timeDisplay = message.createdAt.take(16).replace("T", " ")
    val a11yLabel = "${if (isMe) "You" else message.authorName} at $timeDisplay: ${message.body}"
    val linkColor = MaterialTheme.colorScheme.primary

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
                // §47.3: render @ticket / @customer embeds as mini-cards; fall
                // through to MarkdownLiteParser for plain text segments.
                TeamMessageBody(
                    body = message.body,
                    linkColor = linkColor,
                    onTicketClick = onTicketClick,
                    onCustomerClick = onCustomerClick,
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
