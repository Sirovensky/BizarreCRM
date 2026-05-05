package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * §3.7 L538 — Sticky announcement banner at the top of the Dashboard.
 *
 * Shown when [announcement] is non-null. Uses [MaterialTheme.colorScheme.tertiaryContainer]
 * as the banner surface (readable on both light + dark ramps).
 *
 * **Dismiss persistence**: [onDismiss] is called with the announcement id when the
 * "×" button is tapped. The ViewModel writes the id to
 * [AppPreferences.dismissedAnnouncementId] so the same announcement does not
 * reappear across sessions.
 *
 * **Tap → learn more**: [onLearnMore] is called when the user taps the body or the
 * chevron. The full announcement detail screen is deferred; the ViewModel logs an
 * analytics event in the meantime.
 *
 * @param announcement The current announcement. Null = banner is hidden (don't render).
 * @param onDismiss    Called with [AnnouncementDto.id] when user taps "×".
 * @param onLearnMore  Called with [AnnouncementDto.id] when user taps the banner body.
 * @param modifier     Outer modifier.
 */
@Composable
fun AnnouncementBanner(
    announcement: AnnouncementDto,
    onDismiss: (id: String) -> Unit,
    onLearnMore: (id: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .semantics {
                contentDescription = "Announcement: ${announcement.title}. Tap to learn more."
            },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(
                    onClick = { onLearnMore(announcement.id) },
                )
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Megaphone icon
            Icon(
                imageVector = Icons.Default.Campaign,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
                tint = MaterialTheme.colorScheme.onTertiaryContainer,
            )

            // Title + body
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = announcement.title,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (announcement.body.isNotBlank()) {
                    Text(
                        text = announcement.body,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.82f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            // Chevron "Learn more" affordance
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = "Learn more",
                modifier = Modifier
                    .size(20.dp)
                    .semantics { role = Role.Button },
                tint = MaterialTheme.colorScheme.onTertiaryContainer,
            )

            Spacer(modifier = Modifier.width(0.dp))

            // Dismiss button
            IconButton(
                onClick = { onDismiss(announcement.id) },
                modifier = Modifier.size(32.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss announcement",
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onTertiaryContainer,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/**
 * §3.7 — Server-provided announcement DTO from `GET /announcements/current`.
 *
 * The server stub returns 404 when no announcement is active; the ViewModel
 * catches that and emits `null` so the banner stays hidden.
 */
data class AnnouncementDto(
    /** Stable server-assigned ID used for dismiss-persistence. */
    val id: String,
    val title: String,
    val body: String = "",
    /** Optional deep-link URL or route — deferred; not acted upon in this wave. */
    val learnMoreUrl: String? = null,
)
