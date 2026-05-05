package com.bizarreelectronics.crm.ui.screens.settings

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.BizarreCrmApp
import com.bizarreelectronics.crm.service.NotificationChannelBootstrap
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar

/**
 * §19.3 — In-app Notification Channel Preview screen.
 *
 * Shows every registered notification channel grouped by their [NotificationChannelGroup],
 * surfacing the OS-level importance, sound, badge, and vibration settings so users can
 * see at a glance which channels are active without navigating into the system settings
 * tree. Each channel row has a "Configure" button that deep-links directly into
 * [Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS] for that channel.
 *
 * On pre-O devices (API < 26) channels do not exist; the screen shows an informational
 * banner directing users to the system notification settings instead.
 *
 * No ViewModel needed — all data is read directly from [NotificationManager] which is
 * already the source of truth for channel state (user overrides included).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationChannelPreviewScreen(
    onBack: () -> Unit,
) {
    val context = LocalContext.current

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Notification channels",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Pre-O: channels don't exist; surface a simple shortcut to global notif settings.
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(
                    Icons.Default.Notifications,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.height(16.dp))
                Text(
                    "Notification channels require Android 8 or later.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Spacer(Modifier.height(12.dp))
                Button(onClick = {
                    context.startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        },
                    )
                }) {
                    Text("Open notification settings")
                }
            }
            return@Scaffold
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        val groups = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            buildChannelGroups(manager, context)
        } else {
            emptyList()
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            // Info banner
            Surface(
                color = MaterialTheme.colorScheme.secondaryContainer,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.Info,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "Tap \"Configure\" on any channel to adjust sound, vibration, and importance in system settings.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }

            Spacer(Modifier.height(8.dp))

            groups.forEach { group ->
                ChannelGroupSection(
                    groupLabel = group.label,
                    channels = group.channels,
                    context = context,
                )
                Spacer(Modifier.height(4.dp))
            }

            Spacer(Modifier.height(16.dp))

            // Footer: shortcut to all-app notification settings
            TextButton(
                onClick = {
                    context.startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        },
                    )
                },
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .semantics {
                        contentDescription = "Open all app notification settings"
                        role = Role.Button
                    },
            ) {
                Icon(
                    Icons.Default.Settings,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text("Open all app notification settings")
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

private data class ChannelGroupUi(
    val label: String,
    val channels: List<ChannelRowUi>,
)

private data class ChannelRowUi(
    val id: String,
    val name: String,
    val description: String,
    /** OS importance label after any user override. */
    val importanceLabel: String,
    val importanceColor: @Composable () -> androidx.compose.ui.graphics.Color,
    val badgeEnabled: Boolean,
    val vibrationEnabled: Boolean,
    val soundEnabled: Boolean,
    /** true when the channel is blocked by the user entirely. */
    val blocked: Boolean,
)

// ---------------------------------------------------------------------------
// Data builder (API 26+)
// ---------------------------------------------------------------------------

@RequiresApi(Build.VERSION_CODES.O)
private fun buildChannelGroups(
    manager: NotificationManager,
    context: Context,
): List<ChannelGroupUi> {
    // Map group id → display name (populated from NotificationChannelBootstrap constants)
    val groupNames: Map<String, String> = mapOf(
        NotificationChannelBootstrap.GROUP_OPERATIONAL to "Operational",
        NotificationChannelBootstrap.GROUP_CUSTOMER    to "Customer",
        NotificationChannelBootstrap.GROUP_ADMIN       to "Admin",
        NotificationChannelBootstrap.GROUP_SYSTEM      to "System",
        NotificationChannelBootstrap.GROUP_STAFF       to "Staff",
        NotificationChannelBootstrap.GROUP_DIAGNOSTICS to "Diagnostics",
        ""                                             to "Ungrouped",
    )

    // All channel IDs registered by the app, in display order.
    val allIds: List<String> = listOf(
        // Customer — high
        BizarreCrmApp.CH_SMS_INBOUND,
        BizarreCrmApp.CH_APPOINTMENT_REMINDER,
        BizarreCrmApp.CH_MENTION,
        BizarreCrmApp.CH_TEAM_MENTION,
        BizarreCrmApp.CH_SMS_SILENT,
        // Operational
        BizarreCrmApp.CH_TICKET_ASSIGNED,
        BizarreCrmApp.CH_TICKET_STATUS,
        BizarreCrmApp.CH_ESTIMATE_APPROVED,
        // Admin
        BizarreCrmApp.CH_PAYMENT_RECEIVED,
        BizarreCrmApp.CH_PAYMENT_DECLINED,
        BizarreCrmApp.CH_INVOICE_OVERDUE,
        BizarreCrmApp.CH_SLA_BREACH,
        BizarreCrmApp.CH_LOW_STOCK,
        BizarreCrmApp.CH_DAILY_SUMMARY,
        BizarreCrmApp.CH_WEEKLY_DIGEST,
        BizarreCrmApp.CH_EXPORT_READY,
        // Staff
        BizarreCrmApp.CH_SHIFT_STARTING,
        BizarreCrmApp.CH_MANAGER_TIMEOFF,
        // System
        BizarreCrmApp.CH_SECURITY_EVENT,
        BizarreCrmApp.CH_BACKUP_REPORT,
        BizarreCrmApp.CH_SYNC,
        // Diagnostics
        BizarreCrmApp.CH_SETUP_WIZARD,
        BizarreCrmApp.CH_SUBSCRIPTION_RENEWAL,
        BizarreCrmApp.CH_INTEGRATION_DISCONNECTED,
    )

    // Fetch channels from OS, keyed by ID.
    val osChannelMap = manager.notificationChannels
        .associateBy { it.id }

    // Build rows and group them.
    val byGroup = LinkedHashMap<String, MutableList<ChannelRowUi>>()
    allIds.forEach { id ->
        val ch = osChannelMap[id] ?: return@forEach
        val groupId = ch.group ?: ""
        val blocked = ch.importance == NotificationManager.IMPORTANCE_NONE
        val row = ChannelRowUi(
            id = ch.id,
            name = ch.name?.toString() ?: id,
            description = ch.description?.toString() ?: "",
            importanceLabel = importanceLabel(ch.importance),
            importanceColor = importanceColorProvider(ch.importance),
            badgeEnabled = ch.canShowBadge(),
            vibrationEnabled = ch.shouldVibrate(),
            soundEnabled = ch.sound != null,
            blocked = blocked,
        )
        byGroup.getOrPut(groupId) { mutableListOf() }.add(row)
    }

    return byGroup.entries
        .map { (gid, rows) ->
            ChannelGroupUi(label = groupNames[gid] ?: gid, channels = rows)
        }
        .filter { it.channels.isNotEmpty() }
}

@RequiresApi(Build.VERSION_CODES.O)
private fun importanceLabel(importance: Int): String = when (importance) {
    NotificationManager.IMPORTANCE_HIGH    -> "High (heads-up)"
    NotificationManager.IMPORTANCE_DEFAULT -> "Default (sound)"
    NotificationManager.IMPORTANCE_LOW     -> "Low (no sound)"
    NotificationManager.IMPORTANCE_MIN     -> "Min (no status bar)"
    NotificationManager.IMPORTANCE_NONE    -> "Off (blocked)"
    else                                   -> "Unknown"
}

@RequiresApi(Build.VERSION_CODES.O)
private fun importanceColorProvider(importance: Int): @Composable () -> androidx.compose.ui.graphics.Color = {
    when (importance) {
        NotificationManager.IMPORTANCE_HIGH    -> MaterialTheme.colorScheme.error
        NotificationManager.IMPORTANCE_DEFAULT -> MaterialTheme.colorScheme.tertiary
        NotificationManager.IMPORTANCE_NONE    -> MaterialTheme.colorScheme.outline
        else                                   -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}

// ---------------------------------------------------------------------------
// UI composables
// ---------------------------------------------------------------------------

@RequiresApi(Build.VERSION_CODES.O)
@Composable
private fun ChannelGroupSection(
    groupLabel: String,
    channels: List<ChannelRowUi>,
    context: Context,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        // Group header
        Text(
            groupLabel,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .semantics { heading() },
        )
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
        ) {
            channels.forEachIndexed { index, ch ->
                ChannelRow(ch = ch, context = context)
                if (index < channels.lastIndex) {
                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f),
                    )
                }
            }
        }
    }
}

@RequiresApi(Build.VERSION_CODES.O)
@Composable
private fun ChannelRow(
    ch: ChannelRowUi,
    context: Context,
) {
    val importanceColor = ch.importanceColor()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = buildString {
                    append("${ch.name}. ${ch.importanceLabel}.")
                    if (ch.blocked) append(" Blocked.")
                    if (ch.badgeEnabled) append(" Badge on.") else append(" Badge off.")
                    if (ch.vibrationEnabled) append(" Vibration on.") else append(" Vibration off.")
                    if (!ch.blocked) append(" Tap Configure to change in system settings.")
                }
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    ch.name,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (ch.blocked) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f)
                    else MaterialTheme.colorScheme.onSurface,
                )
                if (ch.blocked) {
                    Spacer(Modifier.width(6.dp))
                    Surface(
                        color = MaterialTheme.colorScheme.errorContainer,
                        shape = MaterialTheme.shapes.small,
                    ) {
                        Text(
                            "Off",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                }
            }
            if (ch.description.isNotBlank()) {
                Text(
                    ch.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                )
            }
            Spacer(Modifier.height(4.dp))
            // Importance + capability chips row
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    ch.importanceLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = importanceColor,
                )
                CapabilityDot(enabled = ch.badgeEnabled, label = "badge")
                CapabilityDot(enabled = ch.vibrationEnabled, label = "vibrate")
                CapabilityDot(enabled = ch.soundEnabled, label = "sound")
            }
        }

        // Configure button — deep-links into system channel settings
        TextButton(
            onClick = {
                context.startActivity(
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        putExtra(Settings.EXTRA_CHANNEL_ID, ch.id)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
            },
            modifier = Modifier.semantics {
                contentDescription = "Configure ${ch.name} notification channel in system settings"
                role = Role.Button
            },
        ) {
            Text("Configure", style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun CapabilityDot(enabled: Boolean, label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Surface(
            shape = MaterialTheme.shapes.extraSmall,
            color = if (enabled) MaterialTheme.colorScheme.primaryContainer
            else MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.size(8.dp),
        ) {}
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = if (enabled) MaterialTheme.colorScheme.onSurface
            else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
        )
    }
}
