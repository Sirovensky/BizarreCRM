package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.service.NotificationHistoryStore
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.DeviceTokenManager
import kotlinx.coroutines.launch
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject

/**
 * CROSS38b-notif: Settings > Notifications preferences sub-page.
 *
 * Now includes:
 *  - L1991: per-event × {Push/SMS/Email} matrix
 *  - L1992: per-channel sound picker
 *  - Original delivery-channel and quiet-hours toggles
 */

/** L1991 — Notification event types with their display metadata. */
data class NotifEvent(
    val id: String,
    val title: String,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    /** Per-channel default-on map. Keys: "push", "sms", "email". True = default ON. */
    val defaultsOn: Map<String, Boolean> = mapOf("push" to true, "sms" to false, "email" to false),
    /** If true the user has flipped this cell away from its default value. */
    // (derived at call-site from AppPreferences; stored here as compile-time reference only)
)

// §73.1 — events marked as "high-volume" warn the user before enabling SMS.
val HIGH_VOLUME_SMS_EVENTS = setOf(
    "sms_inbound", "ticket_status_auto", "low_stock",
)

/** L1992 — Notification channel IDs. */
enum class NotifChannel(val id: String, val label: String) {
    Push("push", "Push"),
    Sms("sms", "SMS"),
    Email("email", "Email"),
}

data class NotificationSettingsUiState(
    val emailAlerts: Boolean = true,
    val smsAlerts: Boolean = true,
    val pushNotifications: Boolean = true,
    val lowStockAlerts: Boolean = true,
    val newTicketAlerts: Boolean = true,
    val appointmentReminderAlerts: Boolean = true,
    // §13.2 quiet hours
    val quietHoursEnabled: Boolean = false,
    val quietHoursStartMinutes: Int = 22 * 60,
    val quietHoursEndMinutes: Int = 7 * 60,
    // L1991 — per-event × per-channel matrix: map of "eventId_channelId" → Boolean
    val eventMatrix: Map<String, Boolean> = emptyMap(),
    // L1992 — per-channel ringtone URIs: map of channelId → uri string or null
    val channelSoundUris: Map<String, String?> = emptyMap(),
    // §73.1 — high-volume SMS warning: set when user enables SMS on a high-volume event
    val pendingHighVolumeSmsEvent: String? = null,
    val pendingHighVolumeSmsChannel: String? = null,
    // §73.8 — recent push history (last 100, newest first)
    val recentHistory: List<NotificationHistoryStore.Entry> = emptyList(),
)

@HiltViewModel
class NotificationSettingsViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
    private val notificationHistoryStore: NotificationHistoryStore,
    private val deviceTokenManager: DeviceTokenManager,
) : ViewModel() {

    /** §73 — Full 21-event matrix matching the ActionPlan §73 table. */
    val notifEvents: List<NotifEvent> = listOf(
        // Customer group
        NotifEvent(
            "sms_inbound", "SMS inbound",
            Icons.Default.Sms,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "appointment_reminder", "Appointment reminder",
            Icons.Default.Event,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "mention", "Ticket mention",
            Icons.Default.AlternateEmail,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "team_mention", "Team chat mention",
            Icons.Default.Forum,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        // Operational group
        NotifEvent(
            "ticket_assigned", "Ticket assigned",
            Icons.Default.AssignmentInd,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "ticket_status_auto", "Ticket status change",
            Icons.Default.ConfirmationNumber,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "estimate_approved", "Estimate approved",
            Icons.Default.ThumbUp,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        // Admin / financial group
        NotifEvent(
            "payment_received", "Payment received",
            Icons.Default.Payments,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "payment_declined", "Payment declined",
            Icons.Default.CreditCardOff,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "invoice_overdue", "Invoice overdue",
            Icons.Default.Receipt,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to true),
        ),
        NotifEvent(
            "low_stock", "Low stock",
            Icons.Default.Inventory,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to true),
        ),
        NotifEvent(
            "sla_breach", "SLA breach",
            Icons.Default.Warning,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to true),
        ),
        // Staff group
        NotifEvent(
            "shift_starting", "Shift starting",
            Icons.Default.AccessTime,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "timeoff_request", "Time-off request",
            Icons.Default.BeachAccess,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        // Digest / admin
        NotifEvent(
            "daily_summary", "Daily summary",
            Icons.Default.BarChart,
            defaultsOn = mapOf("push" to false, "sms" to false, "email" to true),
        ),
        NotifEvent(
            "weekly_digest", "Weekly digest",
            Icons.Default.DateRange,
            defaultsOn = mapOf("push" to false, "sms" to false, "email" to true),
        ),
        // Diagnostics
        NotifEvent(
            "setup_wizard_incomplete", "Setup wizard (24 h)",
            Icons.Default.Build,
            defaultsOn = mapOf("push" to false, "sms" to false, "email" to false),
        ),
        NotifEvent(
            "subscription_renewal", "Subscription renewal",
            Icons.Default.Autorenew,
            defaultsOn = mapOf("push" to false, "sms" to false, "email" to false),
        ),
        NotifEvent(
            "integration_disconnected", "Integration disconnected",
            Icons.Default.LinkOff,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "backup_failed", "Backup failed",
            Icons.Default.BackupTable,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
        NotifEvent(
            "security_event", "Security event",
            Icons.Default.Security,
            defaultsOn = mapOf("push" to true,  "sms" to false, "email" to false),
        ),
    )

    /** L1992 — Channels shown as columns. */
    val channels: List<NotifChannel> = NotifChannel.entries

    private fun buildMatrix(): Map<String, Boolean> = buildMap {
        notifEvents.forEach { event ->
            channels.forEach { channel ->
                // §73.1 — Read persisted value; fall back to per-event default
                // (not global true) so initial state matches the §73 table.
                val defaultOn = event.defaultsOn[channel.id] ?: false
                val key = "${event.id}_${channel.id}"
                // Only use persisted value if it's been explicitly set; otherwise
                // the default-on map governs. AppPreferences stores true as default
                // for backwards compat, so we shadow with the event-specific default
                // by checking whether a key has EVER been written. The simplest
                // approach: write all defaults on first load so the matrix is
                // always self-consistent.
                put(key, appPreferences.getNotifMatrixEnabled(event.id, channel.id, defaultOn))
            }
        }
    }

    /**
     * §73.1 — Returns whether [eventId]×[channelId] has been overridden away from
     * its shipped default so the UI can grey out unmodified cells.
     */
    fun isAtDefault(eventId: String, channelId: String): Boolean {
        val event = notifEvents.firstOrNull { it.id == eventId } ?: return true
        val shippedDefault = event.defaultsOn[channelId] ?: false
        return appPreferences.getNotifMatrixEnabled(eventId, channelId, shippedDefault) == shippedDefault
    }

    private fun buildSoundUris(): Map<String, String?> = buildMap {
        channels.forEach { channel ->
            put(channel.id, appPreferences.getNotifSoundUri(channel.id))
        }
    }

    private val _state = MutableStateFlow(
        NotificationSettingsUiState(
            emailAlerts = appPreferences.notifEmailAlertsEnabled,
            smsAlerts = appPreferences.notifSmsAlertsEnabled,
            pushNotifications = appPreferences.notifPushEnabled,
            lowStockAlerts = appPreferences.notifLowStockEnabled,
            newTicketAlerts = appPreferences.notifNewTicketEnabled,
            appointmentReminderAlerts = appPreferences.notifAppointmentReminderEnabled,
            quietHoursEnabled = appPreferences.quietHoursEnabled,
            quietHoursStartMinutes = appPreferences.quietHoursStartMinutes,
            quietHoursEndMinutes = appPreferences.quietHoursEndMinutes,
            eventMatrix = buildMatrix(),
            channelSoundUris = buildSoundUris(),
            recentHistory = notificationHistoryStore.snapshot(),
        ),
    )
    val state: StateFlow<NotificationSettingsUiState> = _state.asStateFlow()

    /** §73.8 — Refresh the history snapshot (called when screen becomes visible). */
    fun refreshHistory() {
        _state.update { it.copy(recentHistory = notificationHistoryStore.snapshot()) }
    }

    /** §73.8 — Clear all history entries and refresh state. */
    fun clearHistory() {
        notificationHistoryStore.clear()
        _state.update { it.copy(recentHistory = emptyList()) }
    }

    /**
     * §73.9 — Manual FCM token re-registration.
     *
     * Resets the "registered" flag so [DeviceTokenManager.registerIfNeeded] fetches
     * and posts a fresh token even if the 24-hour staleness window has not elapsed.
     * Surfaced in Settings as a "Re-register push" row for support / diagnostics.
     */
    fun reRegisterPushToken() {
        appPreferences.fcmTokenRegistered = false
        viewModelScope.launch {
            deviceTokenManager.registerIfNeeded()
        }
    }

    fun setEmailAlerts(enabled: Boolean) {
        appPreferences.notifEmailAlertsEnabled = enabled
        _state.value = _state.value.copy(emailAlerts = enabled)
    }

    fun setSmsAlerts(enabled: Boolean) {
        appPreferences.notifSmsAlertsEnabled = enabled
        _state.value = _state.value.copy(smsAlerts = enabled)
    }

    fun setPushNotifications(enabled: Boolean) {
        appPreferences.notifPushEnabled = enabled
        _state.value = _state.value.copy(pushNotifications = enabled)
    }

    fun setLowStockAlerts(enabled: Boolean) {
        appPreferences.notifLowStockEnabled = enabled
        _state.value = _state.value.copy(lowStockAlerts = enabled)
    }

    fun setNewTicketAlerts(enabled: Boolean) {
        appPreferences.notifNewTicketEnabled = enabled
        _state.value = _state.value.copy(newTicketAlerts = enabled)
    }

    fun setAppointmentReminderAlerts(enabled: Boolean) {
        appPreferences.notifAppointmentReminderEnabled = enabled
        _state.value = _state.value.copy(appointmentReminderAlerts = enabled)
    }

    // §13.2 quiet hours
    fun setQuietHoursEnabled(enabled: Boolean) {
        appPreferences.quietHoursEnabled = enabled
        _state.value = _state.value.copy(quietHoursEnabled = enabled)
    }

    fun setQuietHoursStart(minutes: Int) {
        appPreferences.quietHoursStartMinutes = minutes
        _state.value = _state.value.copy(quietHoursStartMinutes = minutes)
    }

    fun setQuietHoursEnd(minutes: Int) {
        appPreferences.quietHoursEndMinutes = minutes
        _state.value = _state.value.copy(quietHoursEndMinutes = minutes)
    }

    // L1991 — per-event matrix toggle.
    // §73.1 — If enabling SMS on a high-volume event, raise a confirmation dialog
    // instead of writing immediately; the UI calls [confirmHighVolumeSms] on OK.
    fun setMatrixEnabled(eventId: String, channelId: String, enabled: Boolean) {
        if (shouldWarnHighVolumeSms(eventId, channelId, enabled)) {
            _state.update { it.copy(
                pendingHighVolumeSmsEvent = eventId,
                pendingHighVolumeSmsChannel = channelId,
            ) }
            return
        }
        appPreferences.setNotifMatrixEnabled(eventId, channelId, enabled)
        val key = "${eventId}_$channelId"
        _state.update { it.copy(eventMatrix = it.eventMatrix + (key to enabled)) }
    }

    /** §73.1 — User confirmed enabling SMS on a high-volume event. */
    fun confirmHighVolumeSms() {
        val eventId = _state.value.pendingHighVolumeSmsEvent ?: return
        val channelId = _state.value.pendingHighVolumeSmsChannel ?: return
        appPreferences.setNotifMatrixEnabled(eventId, channelId, true)
        val key = "${eventId}_$channelId"
        _state.update { it.copy(
            eventMatrix = it.eventMatrix + (key to true),
            pendingHighVolumeSmsEvent = null,
            pendingHighVolumeSmsChannel = null,
        ) }
    }

    /** §73.1 — User cancelled enabling SMS on a high-volume event. */
    fun cancelHighVolumeSms() {
        _state.update { it.copy(
            pendingHighVolumeSmsEvent = null,
            pendingHighVolumeSmsChannel = null,
        ) }
    }

    // §73.1 — Reset all per-event matrix cells to shipped defaults.
    fun resetAllToDefaults() {
        val newMatrix = buildMap<String, Boolean> {
            notifEvents.forEach { event ->
                channels.forEach { channel ->
                    val defaultOn = event.defaultsOn[channel.id] ?: false
                    appPreferences.setNotifMatrixEnabled(event.id, channel.id, defaultOn)
                    put("${event.id}_${channel.id}", defaultOn)
                }
            }
        }
        _state.update { it.copy(eventMatrix = newMatrix) }
    }

    // §73.1 — whether to show the high-volume SMS warning for this event + channel combo.
    fun shouldWarnHighVolumeSms(eventId: String, channelId: String, enabling: Boolean): Boolean =
        enabling && channelId == "sms" && eventId in HIGH_VOLUME_SMS_EVENTS

    // L1992 — per-channel ringtone
    fun setChannelSoundUri(channelId: String, uri: String?) {
        appPreferences.setNotifSoundUri(channelId, uri)
        _state.update { it.copy(channelSoundUris = it.channelSoundUris + (channelId to uri)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationSettingsScreen(
    onBack: () -> Unit,
    // §19.3 — navigate to the in-app channel preview (importance / sound / badge per channel).
    onChannelPreview: (() -> Unit)? = null,
    viewModel: NotificationSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // §73.8 — refresh the history snapshot whenever the screen is (re)composed.
    LaunchedEffect(Unit) { viewModel.refreshHistory() }

    // L1992 — Ringtone picker launcher (per-channel).
    // We carry the channelId via a remembered mutable so the result callback
    // knows which channel to update.
    val pendingChannel = remember { mutableStateOf<String?>(null) }
    val ringtoneLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val channel = pendingChannel.value ?: return@rememberLauncherForActivityResult
        val uri = result.data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        viewModel.setChannelSoundUri(channel, uri?.toString())
        pendingChannel.value = null
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Notifications",
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Delivery channels
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // a11y: section heading — TalkBack "heading" navigation gesture lands here
                    Text(
                        "Delivery channels",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.semantics { heading() },
                    )
                    NotificationToggleRow(
                        icon = Icons.Default.Email,
                        title = "Email alerts",
                        subtitle = "Receive notifications via email",
                        checked = state.emailAlerts,
                        onCheckedChange = viewModel::setEmailAlerts,
                    )
                    NotificationToggleDivider()
                    NotificationToggleRow(
                        icon = Icons.Default.Sms,
                        title = "SMS alerts",
                        subtitle = "Receive notifications via SMS",
                        checked = state.smsAlerts,
                        onCheckedChange = viewModel::setSmsAlerts,
                    )
                    NotificationToggleDivider()
                    NotificationToggleRow(
                        icon = Icons.Default.Notifications,
                        title = "Push notifications",
                        subtitle = "Receive push alerts on this device",
                        checked = state.pushNotifications,
                        onCheckedChange = viewModel::setPushNotifications,
                    )
                    NotificationToggleDivider()
                    // §73.9 — Manual re-register row for diagnostics / support.
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { viewModel.reRegisterPushToken() }
                            .padding(vertical = 10.dp)
                            .semantics(mergeDescendants = true) {
                                contentDescription =
                                    "Re-register push token. Tap to force a fresh registration with the server."
                                role = Role.Button
                            },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Re-register push token", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "Force a fresh push token registration with the server.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    // §19.3 — Channel preview row: tap to open per-channel importance/sound/badge inspector.
                    if (onChannelPreview != null) {
                        NotificationToggleDivider()
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onChannelPreview() }
                                .padding(vertical = 10.dp)
                                .semantics(mergeDescendants = true) {
                                    contentDescription =
                                        "View notification channels. Tap to inspect and configure each push channel."
                                    role = Role.Button
                                },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Notifications,
                                contentDescription = null,
                                modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    "View notification channels",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Text(
                                    "Inspect importance, sound, badge and vibration per channel.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowForward,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // §13.2 Quiet hours — silences non-critical channels (sla_breach
            // and security_event always pass through). Two clickable rows
            // open a Material 3 TimePicker dialog for start / end.
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // a11y: section heading
                    Text(
                        "Quiet hours",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.semantics { heading() },
                    )
                    NotificationToggleRow(
                        icon = Icons.Default.Bedtime,
                        title = "Enable quiet hours",
                        subtitle = "Silences non-urgent push during the window. SLA + security alerts still come through.",
                        checked = state.quietHoursEnabled,
                        onCheckedChange = viewModel::setQuietHoursEnabled,
                    )
                    NotificationToggleDivider()
                    QuietHourRow(
                        label = "Start",
                        minutes = state.quietHoursStartMinutes,
                        enabled = state.quietHoursEnabled,
                        onPicked = viewModel::setQuietHoursStart,
                    )
                    NotificationToggleDivider()
                    QuietHourRow(
                        label = "End",
                        minutes = state.quietHoursEndMinutes,
                        enabled = state.quietHoursEnabled,
                        onPicked = viewModel::setQuietHoursEnd,
                    )
                }
            }

            // Category triggers
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // a11y: section heading
                    Text(
                        "Categories",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.semantics { heading() },
                    )
                    NotificationToggleRow(
                        icon = Icons.Default.Inventory,
                        title = "Low-stock alerts",
                        subtitle = "When an inventory item drops below its threshold",
                        checked = state.lowStockAlerts,
                        onCheckedChange = viewModel::setLowStockAlerts,
                    )
                    NotificationToggleDivider()
                    NotificationToggleRow(
                        icon = Icons.Default.ConfirmationNumber,
                        title = "New-ticket alerts",
                        subtitle = "When a ticket is created or assigned to you",
                        checked = state.newTicketAlerts,
                        onCheckedChange = viewModel::setNewTicketAlerts,
                    )
                    NotificationToggleDivider()
                    NotificationToggleRow(
                        icon = Icons.Default.Event,
                        title = "Appointment-reminder alerts",
                        subtitle = "Reminders for upcoming appointments",
                        checked = state.appointmentReminderAlerts,
                        onCheckedChange = viewModel::setAppointmentReminderAlerts,
                    )
                }
            }

            // L1991 — Per-event × per-channel matrix
            NotifEventMatrixCard(
                events = viewModel.notifEvents,
                channels = viewModel.channels,
                matrix = state.eventMatrix,
                onToggle = { eventId, channelId, enabled ->
                    viewModel.setMatrixEnabled(eventId, channelId, enabled)
                },
                onResetAll = viewModel::resetAllToDefaults,
                isAtDefault = { eventId, channelId -> viewModel.isAtDefault(eventId, channelId) },
            )

            // §73.1 — High-volume SMS warning dialog
            if (state.pendingHighVolumeSmsEvent != null) {
                AlertDialog(
                    onDismissRequest = viewModel::cancelHighVolumeSms,
                    title = { Text("Enable SMS for this event?") },
                    text = {
                        Text(
                            "This event can generate 50 or more texts per day. " +
                                "Your SMS provider may charge per message. Continue?",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    },
                    confirmButton = {
                        TextButton(
                            onClick = viewModel::confirmHighVolumeSms,
                            modifier = androidx.compose.ui.Modifier.semantics {
                                contentDescription = "Confirm enable SMS for high-volume event"
                                role = Role.Button
                            },
                        ) { Text("Enable anyway") }
                    },
                    dismissButton = {
                        TextButton(
                            onClick = viewModel::cancelHighVolumeSms,
                            modifier = androidx.compose.ui.Modifier.semantics {
                                contentDescription = "Cancel enabling SMS for high-volume event"
                                role = Role.Button
                            },
                        ) { Text("Cancel") }
                    },
                )
            }

            // L1992 — Sound picker per channel
            NotifSoundPickerCard(
                channels = viewModel.channels,
                soundUris = state.channelSoundUris,
                onPickSound = { channelId ->
                    pendingChannel.value = channelId
                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_NOTIFICATION)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
                        val existingUri = state.channelSoundUris[channelId]
                        if (existingUri != null) {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(existingUri))
                        }
                    }
                    ringtoneLauncher.launch(intent)
                },
            )

            // §73.8 — Recent push history card
            NotifHistoryCard(
                entries = state.recentHistory,
                onClear = viewModel::clearHistory,
            )
        }
    }
}

/**
 * CROSS38b-notif: single toggle row — icon + title + subtitle + Switch.
 * Mirrors the `PreferenceRow` pattern already used on the parent Settings
 * screen's Device Preferences card for visual consistency.
 */
@Composable
private fun NotificationToggleRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val onOffLabel = if (checked) "on" else "off"
    // a11y: mergeDescendants collapses icon + text + Switch into one node;
    // contentDescription gives TalkBack "<title>, notifications <on/off>. <subtitle>."
    // Role.Switch mirrors the underlying M3 Switch role so swipe-to-toggle works.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "$title, notifications $onOffLabel. $subtitle."
                role = Role.Switch
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // decorative — merged Row contentDescription supplies the announcement
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
        )
    }
}

@Composable
private fun NotificationToggleDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
        thickness = 1.dp,
    )
}

/**
 * §13.2 quiet-hour row — clickable label + formatted time. Opens a Material
 * 3 TimePicker dialog. Disabled (greyed out, ignores clicks) when the parent
 * quiet-hours toggle is off.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuietHourRow(
    label: String,
    minutes: Int,
    enabled: Boolean,
    onPicked: (Int) -> Unit,
) {
    var showPicker by remember { mutableStateOf(false) }
    val color = if (enabled) MaterialTheme.colorScheme.onSurface
        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    val formattedTime = formatHHmm(minutes)

    // a11y: Row is the interactive target; describe its current value and affordance.
    // When disabled, note that quiet hours must be enabled first.
    val rowContentDescription = if (enabled) {
        "$label time: $formattedTime. Tap to change."
    } else {
        "$label time: $formattedTime. Enable quiet hours to change."
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { showPicker = true }
            .padding(vertical = 8.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = rowContentDescription
                role = Role.Button
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // decorative — merged Row contentDescription supplies the announcement
        Icon(
            Icons.Default.Schedule,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant
                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
        )
        Spacer(Modifier.width(12.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium, color = color, modifier = Modifier.weight(1f))
        Text(
            text = formattedTime,
            style = MaterialTheme.typography.bodyLarge,
            color = color,
        )
    }

    if (showPicker) {
        val pickerState = rememberTimePickerState(
            initialHour = minutes / 60,
            initialMinute = minutes % 60,
            is24Hour = false,
        )
        AlertDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                // a11y: confirm sets the chosen time
                TextButton(
                    onClick = {
                        onPicked(pickerState.hour * 60 + pickerState.minute)
                        showPicker = false
                    },
                    modifier = Modifier.semantics {
                        contentDescription = "Set $label time"
                        role = Role.Button
                    },
                ) { Text("Set") }
            },
            dismissButton = {
                // a11y: dismiss cancels without saving
                TextButton(
                    onClick = { showPicker = false },
                    modifier = Modifier.semantics {
                        contentDescription = "Cancel $label time change"
                        role = Role.Button
                    },
                ) { Text("Cancel") }
            },
            title = { Text(label) },
            text = { TimePicker(state = pickerState) },
        )
    }
}

private fun formatHHmm(minutes: Int): String {
    val total = ((minutes % 1440) + 1440) % 1440
    val h = total / 60
    val m = total % 60
    val ampm = if (h < 12) "AM" else "PM"
    val h12 = when {
        h == 0 -> 12
        h > 12 -> h - 12
        else -> h
    }
    return "%d:%02d %s".format(h12, m, ampm)
}

// ---------------------------------------------------------------------------
// L1991 — Per-event × per-channel matrix card
// ---------------------------------------------------------------------------

@Composable
private fun NotifEventMatrixCard(
    events: List<NotifEvent>,
    channels: List<NotifChannel>,
    matrix: Map<String, Boolean>,
    onToggle: (eventId: String, channelId: String, enabled: Boolean) -> Unit,
    onResetAll: () -> Unit,
    isAtDefault: (eventId: String, channelId: String) -> Boolean,
) {
    var showResetConfirm by remember { mutableStateOf(false) }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Per-event channels",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() },
                )
                // §73.1 — "Reset all to default" button
                TextButton(
                    onClick = { showResetConfirm = true },
                    modifier = Modifier.semantics {
                        contentDescription = "Reset all notification overrides to default"
                        role = Role.Button
                    },
                ) {
                    Text(
                        "Reset defaults",
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
            Text(
                "Fine-tune which channels fire for each event type. " +
                    "Greyed checkboxes are at their shipped default.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Header row
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                channels.forEach { channel ->
                    Text(
                        channel.label,
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.width(52.dp),
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))

            events.forEachIndexed { index, event ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        event.icon,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        event.title,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                    )
                    channels.forEach { channel ->
                        val key = "${event.id}_${channel.id}"
                        val defaultOn = event.defaultsOn[channel.id] ?: false
                        val checked = matrix[key] ?: defaultOn
                        val atDefault = isAtDefault(event.id, channel.id)
                        // §73.1 — Greyed (onSurfaceVariant alpha 0.5) when at default.
                        // The "(default)" label is conveyed via contentDescription for a11y.
                        val checkboxColors = if (atDefault) {
                            CheckboxDefaults.colors(
                                checkedColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                uncheckedColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f),
                                checkmarkColor = MaterialTheme.colorScheme.surface,
                            )
                        } else {
                            CheckboxDefaults.colors()
                        }
                        val defaultLabel = if (atDefault) " (default)" else ""
                        Checkbox(
                            checked = checked,
                            onCheckedChange = { onToggle(event.id, channel.id, it) },
                            colors = checkboxColors,
                            modifier = Modifier
                                .size(52.dp)
                                .semantics {
                                    contentDescription =
                                        "${event.title} via ${channel.label}: " +
                                            "${if (checked) "on" else "off"}$defaultLabel"
                                },
                        )
                    }
                }
                if (index < events.lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                }
            }
        }
    }

    // §73.1 — Confirm before resetting all to defaults.
    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text("Reset all to defaults?") },
            text = {
                Text(
                    "This will restore every per-event channel setting to its shipped default.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onResetAll()
                        showResetConfirm = false
                    },
                    modifier = Modifier.semantics {
                        contentDescription = "Confirm reset all notification settings to default"
                        role = Role.Button
                    },
                ) { Text("Reset") }
            },
            dismissButton = {
                TextButton(
                    onClick = { showResetConfirm = false },
                    modifier = Modifier.semantics {
                        contentDescription = "Cancel reset notification settings"
                        role = Role.Button
                    },
                ) { Text("Cancel") }
            },
        )
    }
}

// ---------------------------------------------------------------------------
// §73.8 — Recent push history card
// ---------------------------------------------------------------------------

@Composable
private fun NotifHistoryCard(
    entries: List<NotificationHistoryStore.Entry>,
    onClear: () -> Unit,
) {
    val dateFormat = remember { SimpleDateFormat("HH:mm MMM d", Locale.getDefault()) }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Recent (last ${NotificationHistoryStore.CAPACITY})",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { heading() },
                )
                if (entries.isNotEmpty()) {
                    TextButton(
                        onClick = onClear,
                        modifier = Modifier.semantics {
                            contentDescription = "Clear notification history"
                            role = Role.Button
                        },
                    ) {
                        Text("Clear", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            if (entries.isEmpty()) {
                Text(
                    "No push notifications received yet this session.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            } else {
                entries.take(NotificationHistoryStore.CAPACITY).forEachIndexed { index, entry ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp)
                            .semantics(mergeDescendants = true) {
                                contentDescription =
                                    "${entry.title}: ${entry.body}. " +
                                        "Type ${entry.type}. " +
                                        "Received ${dateFormat.format(Date(entry.receivedAtMs))}." +
                                        if (entry.silenced) " Silenced." else ""
                            },
                        verticalAlignment = Alignment.Top,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                entry.title,
                                style = MaterialTheme.typography.bodySmall,
                                color = if (entry.silenced)
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                else
                                    MaterialTheme.colorScheme.onSurface,
                            )
                            if (entry.body.isNotBlank()) {
                                Text(
                                    entry.body,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 2,
                                )
                            }
                            Text(
                                "${entry.type} · ${dateFormat.format(Date(entry.receivedAtMs))}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                            )
                        }
                        if (entry.silenced) {
                            Icon(
                                Icons.Default.VolumeOff,
                                contentDescription = null, // merged
                                modifier = Modifier
                                    .size(14.dp)
                                    .padding(start = 4.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            )
                        }
                    }
                    if (index < entries.lastIndex) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f))
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// L1992 — Sound picker per channel
// ---------------------------------------------------------------------------

@Composable
private fun NotifSoundPickerCard(
    channels: List<NotifChannel>,
    soundUris: Map<String, String?>,
    onPickSound: (channelId: String) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                "Notification sounds",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.semantics { heading() },
            )
            channels.forEach { channel ->
                val uri = soundUris[channel.id]
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onPickSound(channel.id) }
                        .semantics(mergeDescendants = true) {
                            contentDescription = "${channel.label} sound: ${if (uri != null) "custom" else "default"}. Tap to change."
                            role = Role.Button
                        }
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(channel.label, style = MaterialTheme.typography.bodyMedium)
                        Text(
                            if (uri != null) "Custom ringtone" else "Default",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Icon(
                        Icons.Default.MusicNote,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp),
                    )
                }
                if (channel != channels.last()) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                }
            }
        }
    }
}
