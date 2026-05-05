package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

// -----------------------------------------------------------------------
// Age tier — red >14d / amber 7–14d / yellow 3–7d / gray <3d
// -----------------------------------------------------------------------

/** Age tier used for both age and due-date badge colouring. */
@Stable
enum class AgeTier { Gray, Yellow, Amber, Red }

/** Compute the [AgeTier] for a ticket age (days since creation). */
fun ageTierForDays(days: Long): AgeTier = when {
    days > 14 -> AgeTier.Red
    days >= 7  -> AgeTier.Amber
    days >= 3  -> AgeTier.Yellow
    else       -> AgeTier.Gray
}

/**
 * Parse an ISO-8601 datetime/date string (yyyy-MM-dd'T'HH:mm:ss, yyyy-MM-dd HH:mm:ss,
 * or yyyy-MM-dd) into a [LocalDate]. Returns null on any parse failure.
 */
fun parseLocalDate(raw: String): LocalDate? = runCatching {
    when {
        raw.contains('T') -> LocalDateTime
            .parse(raw.substring(0, 19), DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss"))
            .toLocalDate()
        raw.contains(' ') -> LocalDateTime
            .parse(raw.substring(0, 19), DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
            .toLocalDate()
        else -> LocalDate.parse(raw, DateTimeFormatter.ISO_LOCAL_DATE)
    }
}.getOrNull()

/**
 * Days between [createdAtStr] and today. Returns null when [createdAtStr] cannot be parsed.
 */
fun ticketAgeDays(createdAtStr: String, today: LocalDate = LocalDate.now()): Long? {
    val created = parseLocalDate(createdAtStr) ?: return null
    return ChronoUnit.DAYS.between(created, today).coerceAtLeast(0)
}

// -----------------------------------------------------------------------
// Due-date tier — red overdue / amber today / yellow ≤2d / gray later
// -----------------------------------------------------------------------

enum class DueTier { Gray, Yellow, Amber, Red }

fun dueTierFor(dueAtStr: String, today: LocalDate = LocalDate.now()): DueTier {
    val due = parseLocalDate(dueAtStr) ?: return DueTier.Gray
    val daysUntil = ChronoUnit.DAYS.between(today, due)
    return when {
        daysUntil < 0    -> DueTier.Red    // overdue
        daysUntil == 0L  -> DueTier.Amber  // today
        daysUntil <= 2L  -> DueTier.Yellow // ≤ 2 days
        else             -> DueTier.Gray   // later
    }
}

// -----------------------------------------------------------------------
// Color helpers
// -----------------------------------------------------------------------

@Composable
private fun ageTierColor(tier: AgeTier): Color = when (tier) {
    AgeTier.Red    -> MaterialTheme.colorScheme.error
    AgeTier.Amber  -> LocalExtendedColors.current.warning
    // TODO: cream-theme — pick token — Yellow tier (3–7d); no warning-light token yet
    AgeTier.Yellow -> Color(0xFFEAB308)
    AgeTier.Gray   -> MaterialTheme.colorScheme.onSurfaceVariant
}

@Composable
private fun dueTierColor(tier: DueTier): Color = when (tier) {
    DueTier.Red    -> MaterialTheme.colorScheme.error
    DueTier.Amber  -> LocalExtendedColors.current.warning
    // TODO: cream-theme — pick token — Yellow tier (≤2d due); no warning-light token yet
    DueTier.Yellow -> Color(0xFFEAB308)
    DueTier.Gray   -> MaterialTheme.colorScheme.onSurfaceVariant
}

// -----------------------------------------------------------------------
// Chip composables
// -----------------------------------------------------------------------

/**
 * Small age chip. Shows number of days since ticket creation.
 * Color: gray <3d / yellow 3–7d / amber 7–14d / red >14d.
 */
@Composable
fun TicketAgeBadge(
    createdAtStr: String,
    today: LocalDate = LocalDate.now(),
    modifier: Modifier = Modifier,
) {
    val days = ticketAgeDays(createdAtStr, today) ?: return
    val tier = ageTierForDays(days)
    val color = ageTierColor(tier)
    val label = "${days}d"
    BadgeChip(
        label = label,
        color = color,
        modifier = modifier.semantics { contentDescription = "Age $label" },
    )
}

/**
 * Small due-date chip. Shows days until (or since) the due date.
 * Color: gray later / yellow ≤2d / amber today / red overdue.
 */
@Composable
fun TicketDueDateBadge(
    dueAtStr: String,
    today: LocalDate = LocalDate.now(),
    modifier: Modifier = Modifier,
) {
    val due = parseLocalDate(dueAtStr) ?: return
    val tier = dueTierFor(dueAtStr, today)
    val color = dueTierColor(tier)
    val daysUntil = ChronoUnit.DAYS.between(today, due)
    val label = when {
        daysUntil < 0L   -> "Due ${-daysUntil}d ago"
        daysUntil == 0L  -> "Due today"
        else             -> "Due ${daysUntil}d"
    }
    BadgeChip(
        label = label,
        color = color,
        modifier = modifier.semantics { contentDescription = label },
    )
}

/** Row of age + (optional) due-date badges. Attach next to status in list row. */
@Composable
fun TicketRowBadges(
    createdAtStr: String,
    dueAtStr: String?,
    today: LocalDate = LocalDate.now(),
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TicketAgeBadge(createdAtStr = createdAtStr, today = today)
        if (!dueAtStr.isNullOrBlank()) {
            TicketDueDateBadge(dueAtStr = dueAtStr, today = today)
        }
    }
}

// -----------------------------------------------------------------------
// Private: shared chip layout
// -----------------------------------------------------------------------

@Composable
private fun BadgeChip(
    label: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = MaterialTheme.shapes.extraSmall,
        color = color.copy(alpha = 0.12f),
        modifier = modifier,
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
        )
    }
}
