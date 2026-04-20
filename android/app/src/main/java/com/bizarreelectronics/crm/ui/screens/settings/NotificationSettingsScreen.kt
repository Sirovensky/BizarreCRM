package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * CROSS38b-notif: Settings > Notifications preferences sub-page.
 *
 * Six device-local toggles — Email alerts, SMS alerts, Push notifications,
 * Low-stock alerts, New-ticket alerts, Appointment-reminder alerts — each
 * backed by a boolean on [AppPreferences]. All default ON so a fresh install
 * gets the expected alerts; the user opts OUT rather than opting IN.
 *
 * Separate from the Notifications INBOX (`NotificationListScreen`) per
 * CROSS54 — that screen lists past notification events; this one configures
 * which future events should fire at all.
 *
 * Server-side enforcement of the same categories is tracked separately; this
 * screen wires the UI + persistent storage so a later pass can flip the
 * server respect switch without another Android release.
 */
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
)

@HiltViewModel
class NotificationSettingsViewModel @Inject constructor(
    private val appPreferences: AppPreferences,
) : ViewModel() {

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
        ),
    )
    val state: StateFlow<NotificationSettingsUiState> = _state.asStateFlow()

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
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationSettingsScreen(
    onBack: () -> Unit,
    viewModel: NotificationSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

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
                    Text(
                        "Delivery channels",
                        style = MaterialTheme.typography.titleSmall,
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
                    Text("Quiet hours", style = MaterialTheme.typography.titleSmall)
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
                    Text(
                        "Categories",
                        style = MaterialTheme.typography.titleSmall,
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
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = title,
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

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled) { showPicker = true }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
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
            text = formatHHmm(minutes),
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
                TextButton(onClick = {
                    onPicked(pickerState.hour * 60 + pickerState.minute)
                    showPicker = false
                }) { Text("Set") }
            },
            dismissButton = {
                TextButton(onClick = { showPicker = false }) { Text("Cancel") }
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
