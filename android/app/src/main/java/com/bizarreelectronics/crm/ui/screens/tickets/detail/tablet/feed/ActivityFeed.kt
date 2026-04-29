package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.feed

import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.StickyNote2
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.TicketHistory
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Tablet ticket-detail Activity feed (right pane top portion).
 *
 * Renders [history] as a vertical timeline:
 *   - Continuous 1.dp surface3 rail painted via Modifier.drawBehind on
 *     the LazyColumn.
 *   - Day dividers (Today / Yesterday / explicit date) with a 10.dp
 *     pulse marker; "Today" pulses via infiniteTransition.
 *   - Each event row: 32.dp tinted dot + kind label + author + when +
 *     description text.
 *
 * Server returns history DESC by created_at; this composable reverses
 * client-side so oldest sits at top and newest at bottom (closer to
 * the compose bar that lands in T-C9).
 *
 * Kind detection is keyword-inferred from `description` since
 * `TicketHistory` doesn't carry an `action` enum field on the wire.
 *
 * @param history server-supplied history events.
 */
@Composable
internal fun ActivityFeed(
    history: List<TicketHistory>,
    createdAt: String? = null,
    updatedAt: String? = null,
    assignedTo: String? = null,
    slaHint: String? = null,
) {
    val ascending = remember(history) { history.reversed() }
    val grouped = remember(ascending) { groupByDay(ascending) }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxSize(),
    ) {
        // Cream left-border accent ribbon on the feed card (mockup parity).
        Box(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 0.dp),
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    Text(
                        "Activity",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(start = 18.dp, top = 14.dp, bottom = 6.dp),
                    )

                    // Header meta pills row (Created / Updated / Assigned / SLA).
                    val pills = listOfNotNull(
                        createdAt?.takeIf { it.isNotBlank() }?.let { "Created ${formatDayShort(it)}" },
                        updatedAt?.takeIf { it.isNotBlank() }?.let { "Updated ${formatTime(it)}" },
                        assignedTo?.takeIf { it.isNotBlank() }?.let { "Assigned: $it" },
                        slaHint?.takeIf { it.isNotBlank() },
                    )
                    if (pills.isNotEmpty()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 18.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            pills.take(4).forEach { p ->
                                Surface(
                                    color = MaterialTheme.colorScheme.surfaceVariant,
                                    shape = CircleShape,
                                ) {
                                    Text(
                                        p,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                                    )
                                }
                            }
                        }
                    }

                    if (ascending.isEmpty()) {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "No activity yet — events will appear here as they happen.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        val railColor = MaterialTheme.colorScheme.surfaceVariant
                        LazyColumn(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(horizontal = 14.dp)
                                .drawBehind {
                                    val xPx = 28f
                                    drawLine(
                                        color = railColor,
                                        start = androidx.compose.ui.geometry.Offset(xPx, 12f),
                                        end = androidx.compose.ui.geometry.Offset(xPx, size.height - 12f),
                                        strokeWidth = 1f,
                                    )
                                },
                            verticalArrangement = Arrangement.spacedBy(0.dp),
                        ) {
                            grouped.forEachIndexed { groupIdx, group ->
                                item(key = "div_${group.label}") {
                                    DayDivider(label = group.label, isToday = group.isToday)
                                }
                                items(group.events.size, key = { i -> "ev_${groupIdx}_${group.events[i].id}" }) { i ->
                                    val ev = group.events[i]
                                    EventRow(event = ev)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DayDivider(label: String, isToday: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 14.dp, bottom = 6.dp, start = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(modifier = Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            Surface(
                color = if (isToday) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.surfaceVariant,
                shape = CircleShape,
                modifier = Modifier.size(10.dp),
            ) {}
            if (isToday) {
                val transition = rememberInfiniteTransition(label = "today_pulse")
                val scale by transition.animateFloat(
                    initialValue = 0.8f,
                    targetValue = 1.6f,
                    animationSpec = infiniteRepeatable(animation = tween(1800)),
                    label = "today_pulse_scale",
                )
                val alpha by transition.animateFloat(
                    initialValue = 0.7f,
                    targetValue = 0f,
                    animationSpec = infiniteRepeatable(animation = tween(1800)),
                    label = "today_pulse_alpha",
                )
                Surface(
                    color = Color.Transparent,
                    border = androidx.compose.foundation.BorderStroke(
                        1.dp, MaterialTheme.colorScheme.primary.copy(alpha = alpha),
                    ),
                    shape = CircleShape,
                    modifier = Modifier.size((10 * scale).dp),
                ) {}
            }
        }
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun EventRow(event: TicketHistory) {
    val kind = inferKind(event.description)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(modifier = Modifier.size(32.dp), contentAlignment = Alignment.Center) {
            Surface(
                color = MaterialTheme.colorScheme.surface,
                contentColor = kind.tint,
                shape = CircleShape,
                border = androidx.compose.foundation.BorderStroke(1.dp, kind.tint.copy(alpha = 0.4f)),
                modifier = Modifier.size(28.dp),
            ) {
                Box(modifier = Modifier.size(28.dp), contentAlignment = Alignment.Center) {
                    Icon(
                        kind.icon,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    kind.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.Medium,
                )
                event.userName?.takeIf { it.isNotBlank() }?.let { user ->
                    Text(
                        user,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
                event.createdAt?.let { ts ->
                    Text(
                        formatTime(ts),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            event.description?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

private data class EventKind(
    val label: String,
    val tint: Color,
    val icon: ImageVector,
)

@Composable
private fun inferKind(description: String?): EventKind {
    val text = description?.lowercase().orEmpty()
    val good = MaterialTheme.colorScheme.primary
    val cream = MaterialTheme.colorScheme.primary
    val warn = MaterialTheme.colorScheme.error
    val onMuted = MaterialTheme.colorScheme.onSurfaceVariant
    return when {
        "status" in text || "→" in text -> EventKind("Status", good, Icons.Default.Refresh)
        "sms" in text || "text" in text -> EventKind("SMS", onMuted, Icons.Default.Sms)
        "note" in text -> EventKind("Note", warn, Icons.Default.StickyNote2)
        "paid" in text || "payment" in text || "charge" in text -> EventKind("Payment", cream, Icons.Default.AttachMoney)
        "created" in text || "opened" in text -> EventKind("Created", onMuted, Icons.Default.Add)
        "edit" in text || "updated" in text -> EventKind("Update", onMuted, Icons.Default.Edit)
        else -> EventKind("Activity", onMuted, Icons.Default.Refresh)
    }
}

private data class DayGroup(
    val label: String,
    val isToday: Boolean,
    val events: List<TicketHistory>,
)

private fun groupByDay(events: List<TicketHistory>): List<DayGroup> {
    if (events.isEmpty()) return emptyList()
    val today = LocalDate.now()
    val yesterday = today.minusDays(1)
    val byDay = events.groupBy { ev -> parseDateOrNull(ev.createdAt) ?: today }
    val ordered = byDay.toSortedMap()
    return ordered.map { (day, list) ->
        val label = when (day) {
            today -> "Today · ${day.format(DAY_LABEL_FMT)}"
            yesterday -> "Yesterday · ${day.format(DAY_LABEL_FMT)}"
            else -> day.format(DAY_LABEL_FMT_FULL)
        }
        DayGroup(label = label, isToday = day == today, events = list)
    }
}

private fun parseDateOrNull(iso: String?): LocalDate? {
    if (iso.isNullOrBlank()) return null
    return runCatching {
        Instant.parse(iso.replace(" ", "T") + if (!iso.endsWith("Z")) "Z" else "")
            .atZone(ZoneId.systemDefault())
            .toLocalDate()
    }.getOrNull()
        ?: runCatching {
            LocalDate.parse(iso.take(10))
        }.getOrNull()
}

private fun formatTime(iso: String?): String {
    if (iso.isNullOrBlank()) return ""
    return runCatching {
        val zoned = Instant.parse(iso.replace(" ", "T") + if (!iso.endsWith("Z")) "Z" else "")
            .atZone(ZoneId.systemDefault())
        val now = ZoneId.systemDefault().rules.getOffset(Instant.now())
        val mins = ChronoUnit.MINUTES.between(zoned.toInstant(), Instant.now())
        when {
            mins < 1 -> "just now"
            mins < 60 -> "${mins}m ago"
            mins < 24 * 60 -> "${mins / 60}h ago"
            else -> zoned.format(TIME_LABEL_FMT)
        }
    }.getOrDefault(iso)
}

private fun formatDayShort(iso: String?): String {
    if (iso.isNullOrBlank()) return ""
    return runCatching {
        Instant.parse(iso.replace(" ", "T") + if (!iso.endsWith("Z")) "Z" else "")
            .atZone(ZoneId.systemDefault())
            .format(DAY_LABEL_FMT)
    }.getOrDefault(iso.take(10))
}

private val DAY_LABEL_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("MMM d")
private val DAY_LABEL_FMT_FULL: DateTimeFormatter = DateTimeFormatter.ofPattern("EEE · MMM d, yyyy")
private val TIME_LABEL_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
