package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.NewReleases
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * §71.5 — "What's new" modal shown once per new versionCode.
 *
 * Shown on first launch after the app is upgraded to a new version.
 * Dismissed by tapping "Got it" or interacting elsewhere; once dismissed
 * [AppPreferences.lastSeenVersionCode] is updated so the dialog never
 * appears again for that build.
 *
 * ## Visibility rule
 * The hosting screen (MainActivity) compares [BuildConfig.VERSION_CODE]
 * against [AppPreferences.lastSeenVersionCode]. If the current code is
 * strictly greater than the stored value, the user has just upgraded and
 * this dialog is presented.
 *
 * ## Content
 * Release notes are defined in [WHATS_NEW_ENTRIES] — add one [WhatsNewEntry]
 * per versionCode that has notable user-visible changes. Entries are shown in
 * declaration order (newest first). If no entries match the upgrade range the
 * dialog still shows a "You're up to date" fallback so the modal always
 * completes the §71.5 flow without an empty state.
 *
 * @param versionName    Human-readable version string from [BuildConfig.VERSION_NAME].
 * @param versionCode    Numeric version code from [BuildConfig.VERSION_CODE].
 * @param prevVersionCode Version code the user was on before the upgrade, or 0 on
 *                        first launch.
 * @param onDismiss      Called when the user taps "Got it". The caller is
 *                       responsible for persisting [versionCode] to prefs so the
 *                       dialog is not shown again.
 */
@Composable
fun WhatsNewDialog(
    versionName: String,
    versionCode: Int,
    prevVersionCode: Int,
    onDismiss: () -> Unit,
) {
    // Collect release notes whose versionCode is > prevVersionCode (new since last seen)
    val entries = WHATS_NEW_ENTRIES.filter { it.sinceVersionCode > prevVersionCode }

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                imageVector = Icons.Default.NewReleases,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(32.dp),
            )
        },
        title = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "What's New",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "Version $versionName",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (entries.isEmpty()) {
                    WhatsNewItem(
                        icon = Icons.Default.Star,
                        headline = "You're up to date",
                        body = "Bug fixes and performance improvements.",
                        kind = WhatsNewKind.IMPROVEMENT,
                    )
                } else {
                    entries.forEach { entry ->
                        WhatsNewItem(
                            icon = entry.kind.icon,
                            headline = entry.headline,
                            body = entry.body,
                            kind = entry.kind,
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Got it")
            }
        },
    )
}

// ---------------------------------------------------------------------------
// Internal composable
// ---------------------------------------------------------------------------

@Composable
private fun WhatsNewItem(
    icon: ImageVector,
    headline: String,
    body: String,
    kind: WhatsNewKind,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.Start,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = when (kind) {
                WhatsNewKind.FEATURE     -> MaterialTheme.colorScheme.primary
                WhatsNewKind.IMPROVEMENT -> MaterialTheme.colorScheme.secondary
                WhatsNewKind.FIX        -> MaterialTheme.colorScheme.tertiary
                WhatsNewKind.SECURITY   -> MaterialTheme.colorScheme.error
            },
            modifier = Modifier
                .size(20.dp)
                .padding(top = 2.dp),
        )
        Spacer(Modifier.width(10.dp))
        Column {
            Text(
                text = headline,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (body.isNotBlank()) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = body,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/**
 * Category of a release-note entry — drives the icon and accent color in
 * [WhatsNewItem].
 */
enum class WhatsNewKind(val icon: ImageVector) {
    /** Wholly new screen or capability. */
    FEATURE(Icons.Default.Bolt),

    /** Enhancement to an existing feature. */
    IMPROVEMENT(Icons.Default.Star),

    /** Bug fix (visible or stability). */
    FIX(Icons.Default.BugReport),

    /** Security fix or hardening. */
    SECURITY(Icons.Default.Security),
}

/**
 * A single release-note bullet shown in [WhatsNewDialog].
 *
 * @param sinceVersionCode The versionCode this change first appeared in.
 *   Entries with [sinceVersionCode] > [prevVersionCode] (the last version the
 *   user ran) are shown in the dialog. This means you can ship release notes
 *   ahead of time in the binary and they will only surface to users who are
 *   actually upgrading past that code.
 * @param headline Short title (≤ 6 words). Shown in bold.
 * @param body     Optional one-sentence description. Left blank for concise items.
 * @param kind     Controls icon + accent color.
 */
data class WhatsNewEntry(
    val sinceVersionCode: Int,
    val headline: String,
    val body: String = "",
    val kind: WhatsNewKind = WhatsNewKind.FEATURE,
)

/**
 * Canonical release notes shown in [WhatsNewDialog].
 *
 * Add a new [WhatsNewEntry] for each versionCode that has user-visible changes
 * worth highlighting. List is ordered newest-first so the latest changes appear
 * at the top.
 *
 * [WhatsNewEntry.sinceVersionCode] should equal the versionCode of the build in
 * which the change shipped; users who skipped intermediate versions will see all
 * entries since their last installed version in a single catch-up dialog.
 */
internal val WHATS_NEW_ENTRIES: List<WhatsNewEntry> = listOf(
    WhatsNewEntry(
        sinceVersionCode = 1,
        headline = "Column picker for ticket list",
        body = "Show or hide assignee, device, urgency, and more on the ticket list. Persists per user.",
        kind = WhatsNewKind.FEATURE,
    ),
    WhatsNewEntry(
        sinceVersionCode = 1,
        headline = "Ticket photos with pinch-zoom",
        body = "Full-screen gallery supports pinch-to-zoom, before/after tags, and EXIF-stripped uploads.",
        kind = WhatsNewKind.FEATURE,
    ),
    WhatsNewEntry(
        sinceVersionCode = 1,
        headline = "SLA countdown chips",
        body = "Every ticket row shows a colour-coded ring indicating how close the job is to its deadline.",
        kind = WhatsNewKind.IMPROVEMENT,
    ),
    WhatsNewEntry(
        sinceVersionCode = 1,
        headline = "Inventory barcode display",
        body = "Tap any inventory item to see its Code-128 and QR codes ready to scan or share.",
        kind = WhatsNewKind.FEATURE,
    ),
    WhatsNewEntry(
        sinceVersionCode = 1,
        headline = "Offline-first POS",
        body = "Cash sales queue locally when connectivity is lost and sync automatically on reconnect.",
        kind = WhatsNewKind.IMPROVEMENT,
    ),
    WhatsNewEntry(
        sinceVersionCode = 1,
        headline = "Screen-capture prevention",
        body = "FLAG_SECURE now defaults ON in release builds, blocking Recents screenshots of PII.",
        kind = WhatsNewKind.SECURITY,
    ),
)
