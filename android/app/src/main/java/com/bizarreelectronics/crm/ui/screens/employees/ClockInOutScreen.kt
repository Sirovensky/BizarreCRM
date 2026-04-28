package com.bizarreelectronics.crm.ui.screens.employees

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.BizarreCrmApp
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.api.EmployeeApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.service.ClockInTileService
import com.bizarreelectronics.crm.service.LiveUpdateNotifier
import com.bizarreelectronics.crm.util.ClockShortcutPublisher
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.widget.glance.publishClockState
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.screens.employees.components.ClockBreakPicker
import android.location.LocationManager
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlin.math.roundToInt

// region — state

data class ClockInOutUiState(
    val pin: String = "",
    val isClockedIn: Boolean = false,
    val isProcessing: Boolean = false,
    val error: String? = null,
    val successMessage: String? = null,
    val userName: String = "",
    // §14.3 L1626 — break support
    val onBreak: Boolean = false,
    val breakElapsedSeconds: Long = 0L,
    // §14.3 L1630 — offline indicator
    val isOffline: Boolean = false,
    // §14.3 L1627 — geofence warning
    val geofenceWarning: String? = null,
)

// endregion

@HiltViewModel
class ClockInOutViewModel @Inject constructor(
    private val authApi: AuthApi,
    private val settingsApi: SettingsApi,
    private val employeeApi: EmployeeApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
    private val syncQueueDao: SyncQueueDao,
    @ApplicationContext private val appContext: Context,
    private val gson: Gson,
) : ViewModel() {

    private val _state = MutableStateFlow(ClockInOutUiState())
    val state = _state.asStateFlow()

    // §14.3 L1631 — live update notification ID; non-null when clocked in
    private var liveUpdateId: Int? = null

    // §14.3 L1626 — break timer job
    private var breakTimerJob: Job? = null

    // Shop location stub (fixed centre) — replaced by tenant config when available
    private val shopLat = 40.7128
    private val shopLon = -74.0060
    private val geofenceRadiusKm = 0.5

    init {
        val firstName = authPreferences.userFirstName.orEmpty()
        val lastName = authPreferences.userLastName.orEmpty()
        val name = "$firstName $lastName".trim().ifBlank { authPreferences.username.orEmpty() }
        _state.value = _state.value.copy(
            userName = name,
            isOffline = !serverMonitor.isEffectivelyOnline.value,
        )
        // Observe online status
        viewModelScope.launch {
            serverMonitor.isEffectivelyOnline.collect { online ->
                _state.value = _state.value.copy(isOffline = !online)
            }
        }
    }

    // region — PIN pad

    fun appendDigit(digit: String) {
        val current = _state.value
        if (current.pin.length < 4 && !current.isProcessing) {
            _state.value = current.copy(pin = current.pin + digit, error = null, successMessage = null)
        }
    }

    fun clearPin() {
        _state.value = _state.value.copy(pin = "", error = null, successMessage = null)
    }

    // endregion

    // region — clock in/out

    fun submit() {
        val current = _state.value
        if (current.pin.length != 4) {
            _state.value = current.copy(error = "Enter 4-digit PIN")
            return
        }
        if (current.isProcessing) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isProcessing = true, error = null, successMessage = null)
            if (serverMonitor.isEffectivelyOnline.value) {
                submitOnline()
            } else {
                submitOffline()
            }
        }
    }

    private suspend fun submitOnline() {
        try {
            val pin = _state.value.pin
            val pinResponse = authApi.verifyPin(mapOf("pin" to pin))
            val verified = (pinResponse.data as? Map<*, *>)?.get("verified") == true
            if (!verified) {
                _state.value = _state.value.copy(isProcessing = false, error = "Invalid PIN", pin = "")
                return
            }
            val userId = authPreferences.userId
            val wasClockedIn = _state.value.isClockedIn
            if (wasClockedIn) {
                settingsApi.clockOut(userId, mapOf("pin" to pin))
                cancelLiveUpdate()
            } else {
                settingsApi.clockIn(userId, mapOf("pin" to pin))
                postClockedInNotification()
            }
            val nowClockedIn = !wasClockedIn
            _state.value = _state.value.copy(
                isProcessing = false,
                isClockedIn = nowClockedIn,
                onBreak = false,
                pin = "",
                successMessage = if (wasClockedIn) "Clocked out successfully" else "Clocked in successfully",
            )
            if (wasClockedIn) stopBreakTimer()
            // §14.10 — push new state to QS tile + Glance widget
            broadcastClockState(nowClockedIn)
        } catch (e: Exception) {
            _state.value = _state.value.copy(
                isProcessing = false,
                error = e.message ?: "Operation failed",
                pin = "",
            )
        }
    }

    private suspend fun submitOffline() {
        val userId = authPreferences.userId
        val wasClockedIn = _state.value.isClockedIn
        val operation = if (wasClockedIn) "clock_out" else "clock_in"
        val pin = _state.value.pin
        val payload = gson.toJson(mapOf("userId" to userId, "pin" to pin))
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "employee",
                entityId = userId,
                operation = operation,
                payload = payload,
            )
        )
        if (!wasClockedIn) postClockedInNotification()
        else cancelLiveUpdate()

        val nowClockedIn = !wasClockedIn
        _state.value = _state.value.copy(
            isProcessing = false,
            isClockedIn = nowClockedIn,
            onBreak = false,
            pin = "",
            successMessage = if (wasClockedIn) {
                "Clock out queued \u2014 will sync when online"
            } else {
                "Clock in queued \u2014 will sync when online"
            },
        )
        if (wasClockedIn) stopBreakTimer()
        // \u00a714.10 \u2014 push new state to QS tile + Glance widget even when offline
        broadcastClockState(nowClockedIn)
    }

    // endregion

    // region — §14.3 L1626 breaks

    fun startBreak() {
        if (!_state.value.isClockedIn || _state.value.onBreak) return
        viewModelScope.launch {
            runCatching { employeeApi.startBreak(authPreferences.userId) }
            _state.value = _state.value.copy(onBreak = true, breakElapsedSeconds = 0L)
            startBreakTimer()
        }
    }

    fun endBreak() {
        if (!_state.value.onBreak) return
        viewModelScope.launch {
            runCatching { employeeApi.endBreak(authPreferences.userId) }
            _state.value = _state.value.copy(onBreak = false, breakElapsedSeconds = 0L)
            stopBreakTimer()
        }
    }

    private fun startBreakTimer() {
        stopBreakTimer()
        breakTimerJob = viewModelScope.launch {
            while (true) {
                delay(1_000L)
                _state.value = _state.value.copy(
                    breakElapsedSeconds = _state.value.breakElapsedSeconds + 1L,
                )
            }
        }
    }

    private fun stopBreakTimer() {
        breakTimerJob?.cancel()
        breakTimerJob = null
    }

    // endregion

    // region — §14.3 L1631 live update notification

    private fun postClockedInNotification() {
        val clockTime = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
        val id = LiveUpdateNotifier.showLiveUpdate(
            context = appContext,
            title = "Clocked in at $clockTime",
            progressText = "Timer running\u2026",
            deepLink = "clock",
            channelId = BizarreCrmApp.CH_SYNC,
            existingId = liveUpdateId,
        )
        liveUpdateId = id
    }

    private fun cancelLiveUpdate() {
        val id = liveUpdateId ?: return
        LiveUpdateNotifier.cancelLiveUpdate(appContext, id)
        liveUpdateId = null
    }

    override fun onCleared() {
        super.onCleared()
        stopBreakTimer()
        // Don't cancel live update on VM clear — notification stays while clocked in
    }

    // endregion

    // region — §14.10 QS tile + Glance widget state broadcast

    /**
     * §14.10 — Propagates the latest clock state to both surfaces that reflect
     * it outside the app:
     *
     * 1. **Quick Settings tile** (`ClockInTileService`) — writes a lightweight
     *    SharedPreferences key and asks the OS to rebind the tile so its
     *    [Tile.STATE_ACTIVE] / [Tile.STATE_INACTIVE] icon updates immediately.
     *
     * 2. **Glance home-screen widget** (`ClockInGlanceWidget`) — pushes the
     *    new boolean + employee name into the Glance DataStore and triggers a
     *    widget redraw via the Glance update machinery.
     *
     * Both calls are fire-and-forget: failures are logged but never surfaced
     * to the user because the QS tile and widget are non-critical UI.
     *
     * This must be called from a coroutine (suspend context) because
     * [publishClockState] is a suspend function.
     */
    private suspend fun broadcastClockState(isClockedIn: Boolean) {
        // 1. Quick Settings tile (synchronous SharedPrefs + requestListeningState)
        runCatching {
            ClockInTileService.persistClockState(
                context = appContext,
                isClockedIn = isClockedIn,
                isLoggedIn = true,
            )
        }.onFailure { android.util.Log.w("ClockInOutVM", "tile state update failed: ${it.message}") }

        // §14.10 — Launcher App Shortcut: update dynamic shortcut to reflect new state
        // (Clock in ↔ Clock out label + badge icon)
        runCatching {
            ClockShortcutPublisher.updateShortcut(
                context = appContext,
                isClockedIn = isClockedIn,
            )
        }.onFailure { android.util.Log.w("ClockInOutVM", "shortcut update failed: ${it.message}") }

        // 2. Glance widget (suspend; iterates active widget instances)
        val displayName = buildString {
            append(authPreferences.userFirstName.orEmpty())
            val last = authPreferences.userLastName.orEmpty()
            if (last.isNotBlank()) {
                if (isNotEmpty()) append(" ")
                append(last)
            }
        }.ifBlank { authPreferences.username.orEmpty() }

        runCatching {
            publishClockState(
                context = appContext,
                isClockedIn = isClockedIn,
                employeeName = displayName,
            )
        }.onFailure { android.util.Log.w("ClockInOutVM", "widget state update failed: ${it.message}") }
    }

    // endregion

    // region — §14.3 L1627 geofence

    /**
     * Called from the UI after location permission is granted or already held.
     * Uses Android's built-in LocationManager (last known location).
     * Stubs fixed shop centre if location unavailable.
     */
    @SuppressLint("MissingPermission")
    fun checkGeofence(context: Context) {
        viewModelScope.launch {
            try {
                val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    ?: return@launch
                // Try GPS then network provider for last-known location
                val loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    ?: return@launch
                val distKm = haversineKm(loc.latitude, loc.longitude, shopLat, shopLon)
                if (distKm > geofenceRadiusKm) {
                    val km = (distKm * 10).roundToInt() / 10.0
                    _state.value = _state.value.copy(
                        geofenceWarning = "You're $km km from the shop",
                    )
                } else {
                    _state.value = _state.value.copy(geofenceWarning = null)
                }
            } catch (_: Exception) {
                // Location unavailable — silently skip geofence check
            }
        }
    }

    fun dismissGeofenceWarning() {
        _state.value = _state.value.copy(geofenceWarning = null)
    }

    // endregion
}

// region — Haversine

private fun haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    val r = 6371.0
    val dLat = Math.toRadians(lat2 - lat1)
    val dLon = Math.toRadians(lon2 - lon1)
    val a = Math.sin(dLat / 2).let { it * it } +
            Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
            Math.sin(dLon / 2).let { it * it }
    return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// endregion

// region — Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClockInOutScreen(
    onBack: () -> Unit = {},
    viewModel: ClockInOutViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // §14.3 L1627 — location permission launcher
    val locationPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) viewModel.checkGeofence(context)
    }

    // Trigger geofence check when the screen first appears (clocked-out state)
    LaunchedEffect(Unit) {
        if (!state.isClockedIn) {
            val hasPerm = ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (hasPerm) viewModel.checkGeofence(context)
            else locationPermLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    LaunchedEffect(state.successMessage) {
        val msg = state.successMessage
        if (msg != null) snackbarHostState.showSnackbar(msg)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Clock In / Out",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // §14.3 L1630 — offline indicator banner
            if (state.isOffline) {
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.CloudOff,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                        Text(
                            "Offline — clock event will sync when online",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                    }
                }
            }

            // §14.3 L1627 — geofence warning (dismissible)
            state.geofenceWarning?.let { warning ->
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.weight(1f),
                        ) {
                            Icon(
                                Icons.Default.LocationOff,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onErrorContainer,
                            )
                            Text(
                                warning,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                            )
                        }
                        IconButton(
                            onClick = { viewModel.dismissGeofenceWarning() },
                            modifier = Modifier.size(24.dp),
                        ) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Dismiss",
                                modifier = Modifier.size(14.dp),
                                tint = MaterialTheme.colorScheme.onErrorContainer,
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(4.dp))

            // Clock status icon
            Icon(
                if (state.isClockedIn) Icons.Default.Timer else Icons.Default.TimerOff,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = if (state.isClockedIn) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Text(
                if (state.isClockedIn) "Currently clocked in" else "Not clocked in",
                style = MaterialTheme.typography.headlineSmall,
            )

            if (state.userName.isNotBlank()) {
                Text(
                    state.userName,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // §14.3 L1626 — break picker (only when clocked in)
            if (state.isClockedIn) {
                val breakElapsedLabel = run {
                    val secs = state.breakElapsedSeconds
                    val m = TimeUnit.SECONDS.toMinutes(secs)
                    val s = secs - TimeUnit.MINUTES.toSeconds(m)
                    "%02d:%02d".format(m, s)
                }
                ClockBreakPicker(
                    onBreak = state.onBreak,
                    breakElapsedLabel = if (state.onBreak) breakElapsedLabel else "",
                    isProcessing = state.isProcessing,
                    onStartBreak = { viewModel.startBreak() },
                    onEndBreak = { viewModel.endBreak() },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // PIN display
            Text(
                text = state.pin.map { '*' }.joinToString("  ").ifEmpty { "\u2022  \u2022  \u2022  \u2022" },
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.height(48.dp),
                color = if (state.pin.isEmpty())
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                else MaterialTheme.colorScheme.onSurface,
            )

            // PIN pad
            val buttons = listOf(
                listOf("1", "2", "3"),
                listOf("4", "5", "6"),
                listOf("7", "8", "9"),
                listOf("C", "0", "OK"),
            )

            buttons.forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { label ->
                        Button(
                            onClick = {
                                when (label) {
                                    "C" -> viewModel.clearPin()
                                    "OK" -> viewModel.submit()
                                    else -> viewModel.appendDigit(label)
                                }
                            },
                            modifier = Modifier.size(72.dp),
                            enabled = !state.isProcessing,
                            colors = when (label) {
                                "C" -> ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer,
                                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                )
                                "OK" -> ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.primary,
                                    contentColor = MaterialTheme.colorScheme.onPrimary,
                                )
                                else -> ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            },
                        ) {
                            if (label == "OK" && state.isProcessing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp,
                                    color = MaterialTheme.colorScheme.onPrimary,
                                )
                            } else {
                                Text(label, style = MaterialTheme.typography.titleLarge)
                            }
                        }
                    }
                }
            }

            state.error?.let { errorText ->
                Text(
                    errorText,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

// endregion
