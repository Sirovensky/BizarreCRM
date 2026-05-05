package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ── Data model ───────────────────────────────────────────────────────────────

/**
 * Represents open/close hours for a single day.
 * [openHour]/[closeHour] are 0-23; null pair means day is closed.
 */
data class DayHours(
    val isOpen: Boolean = true,
    val openHour: Int = 9,
    val openMinute: Int = 0,
    val closeHour: Int = 18,
    val closeMinute: Int = 0,
)

/** Ordered Mon-Sun representation matching the server JSON keys. */
data class BusinessHoursState(
    val days: Map<String, DayHours> = defaultHours(),
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
) {
    companion object {
        val DAY_KEYS = listOf("mon", "tue", "wed", "thu", "fri", "sat", "sun")
        val DAY_LABELS = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
        fun defaultHours() = DAY_KEYS.associateWith { day ->
            when (day) {
                "sat" -> DayHours(isOpen = true, openHour = 10, closeHour = 16)
                "sun" -> DayHours(isOpen = false)
                else  -> DayHours(isOpen = true, openHour = 9, closeHour = 18)
            }
        }
    }
}

// ── JSON helpers ─────────────────────────────────────────────────────────────

private val gson = Gson()

/**
 * Parse server JSON `{"mon":[9,18],"tue":[9,18],...,"sun":null}` into domain model.
 * Each entry is either `null` (closed) or a 2-element int array `[openHour, closeHour]`.
 * Minutes are not stored server-side; we default to :00.
 */
private fun parseBusinessHoursJson(json: String): Map<String, DayHours> {
    return try {
        val type = object : TypeToken<Map<String, Any?>>() {}.type
        val raw: Map<String, Any?> = gson.fromJson(json, type)
        BusinessHoursState.DAY_KEYS.associateWith { key ->
            when (val v = raw[key]) {
                null -> DayHours(isOpen = false)
                is List<*> -> {
                    val open  = (v.getOrNull(0) as? Number)?.toInt() ?: 9
                    val close = (v.getOrNull(1) as? Number)?.toInt() ?: 18
                    DayHours(isOpen = true, openHour = open, closeHour = close)
                }
                else -> DayHours(isOpen = false)
            }
        }
    } catch (_: Exception) {
        BusinessHoursState.defaultHours()
    }
}

/**
 * Serialise back to `{"mon":[9,18],...,"sun":null}`.
 * Minutes are intentionally dropped — server stores hour-only pairs.
 */
private fun toBusinessHoursJson(days: Map<String, DayHours>): String {
    val map = BusinessHoursState.DAY_KEYS.associate { key ->
        val d = days[key] ?: DayHours(isOpen = false)
        key to if (d.isOpen) listOf(d.openHour, d.closeHour) else null
    }
    return gson.toJson(map)
}

private fun formatHour(hour: Int, minute: Int = 0): String {
    val ampm = if (hour < 12) "AM" else "PM"
    val h    = if (hour % 12 == 0) 12 else hour % 12
    val m    = minute.toString().padStart(2, '0')
    return "$h:$m $ampm"
}

// ── ViewModel ────────────────────────────────────────────────────────────────

@HiltViewModel
class BusinessHoursEditorViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(BusinessHoursState(isLoading = true))
    val uiState: StateFlow<BusinessHoursState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            runCatching { settingsApi.getConfig() }
                .onSuccess { resp ->
                    val json = resp.data?.get("business_hours") ?: ""
                    val days = if (json.isBlank()) BusinessHoursState.defaultHours()
                               else parseBusinessHoursJson(json)
                    _uiState.value = BusinessHoursState(days = days, isLoading = false)
                }
                .onFailure {
                    _uiState.value = BusinessHoursState(
                        isLoading = false,
                        errorMessage = "Could not load hours: ${it.message}",
                    )
                }
        }
    }

    fun toggleDay(key: String, isOpen: Boolean) {
        val days = _uiState.value.days.toMutableMap()
        days[key] = (days[key] ?: DayHours()).copy(isOpen = isOpen)
        _uiState.value = _uiState.value.copy(days = days)
    }

    fun setOpenTime(key: String, hour: Int, minute: Int) {
        val days = _uiState.value.days.toMutableMap()
        days[key] = (days[key] ?: DayHours()).copy(openHour = hour, openMinute = minute)
        _uiState.value = _uiState.value.copy(days = days)
    }

    fun setCloseTime(key: String, hour: Int, minute: Int) {
        val days = _uiState.value.days.toMutableMap()
        days[key] = (days[key] ?: DayHours()).copy(closeHour = hour, closeMinute = minute)
        _uiState.value = _uiState.value.copy(days = days)
    }

    fun save() {
        val s = _uiState.value
        _uiState.value = s.copy(isSaving = true, errorMessage = null)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStore(mapOf("business_hours" to toBusinessHoursJson(s.days)))
            }
                .onSuccess { _uiState.value = _uiState.value.copy(isSaving = false, savedOk = true) }
                .onFailure {
                    _uiState.value = _uiState.value.copy(
                        isSaving = false,
                        errorMessage = "Save failed: ${it.message}",
                    )
                }
        }
    }

    fun clearSavedOk() { _uiState.value = _uiState.value.copy(savedOk = false) }
    fun clearError()    { _uiState.value = _uiState.value.copy(errorMessage = null) }
}

// ── Composables ──────────────────────────────────────────────────────────────

/**
 * §19.19 Business hours editor.
 * Presents one row per day of week; each row has an open/closed toggle and,
 * when open, tappable open and close time chips that surface a [TimePicker]
 * dialog. Persists to `PUT /settings/store` as JSON under the `business_hours` key.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BusinessHoursEditorScreen(
    onBack: () -> Unit,
    viewModel: BusinessHoursEditorViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.savedOk) {
        if (state.savedOk) {
            snackbarHostState.showSnackbar("Business hours saved")
            viewModel.clearSavedOk()
        }
    }
    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Business hours") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        if (state.isLoading) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) { CircularProgressIndicator() }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Set your shop's opening and closing hours for each day of the week.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    BusinessHoursState.DAY_KEYS.zip(BusinessHoursState.DAY_LABELS).forEach { (key, label) ->
                        val day = state.days[key] ?: DayHours(isOpen = false)
                        DayHoursRow(
                            dayKey   = key,
                            dayLabel = label,
                            day      = day,
                            onToggle = { viewModel.toggleDay(key, it) },
                            onSetOpen  = { h, m -> viewModel.setOpenTime(key, h, m) },
                            onSetClose = { h, m -> viewModel.setCloseTime(key, h, m) },
                        )
                    }
                }
            }

            FilledTonalButton(
                onClick = { viewModel.save() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isSaving,
            ) {
                if (state.isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp),
                        strokeWidth = 2.dp,
                    )
                }
                Text("Save hours")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DayHoursRow(
    dayKey: String,
    dayLabel: String,
    day: DayHours,
    onToggle: (Boolean) -> Unit,
    onSetOpen: (Int, Int) -> Unit,
    onSetClose: (Int, Int) -> Unit,
) {
    var showOpenPicker  by remember { mutableStateOf(false) }
    var showClosePicker by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(dayLabel, style = MaterialTheme.typography.bodyLarge)
            Switch(
                checked = day.isOpen,
                onCheckedChange = onToggle,
                modifier = Modifier.semantics {
                    contentDescription = "$dayLabel: ${if (day.isOpen) "open" else "closed"}"
                },
            )
        }

        if (day.isOpen) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Opens",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(end = 2.dp),
                )
                TextButton(
                    onClick = { showOpenPicker = true },
                    modifier = Modifier.semantics {
                        contentDescription = "$dayLabel opens at ${formatHour(day.openHour, day.openMinute)}, tap to change"
                    },
                ) {
                    Text(
                        formatHour(day.openHour, day.openMinute),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                Text(
                    text = "–",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = "Closes",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(
                    onClick = { showClosePicker = true },
                    modifier = Modifier.semantics {
                        contentDescription = "$dayLabel closes at ${formatHour(day.closeHour, day.closeMinute)}, tap to change"
                    },
                ) {
                    Text(
                        formatHour(day.closeHour, day.closeMinute),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        } else {
            Text(
                text = "Closed",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }

    if (showOpenPicker) {
        TimePickerDialog(
            title = "Opening time — $dayLabel",
            initialHour = day.openHour,
            initialMinute = day.openMinute,
            onConfirm = { h, m -> onSetOpen(h, m); showOpenPicker = false },
            onDismiss = { showOpenPicker = false },
        )
    }
    if (showClosePicker) {
        TimePickerDialog(
            title = "Closing time — $dayLabel",
            initialHour = day.closeHour,
            initialMinute = day.closeMinute,
            onConfirm = { h, m -> onSetClose(h, m); showClosePicker = false },
            onDismiss = { showClosePicker = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickerDialog(
    title: String,
    initialHour: Int,
    initialMinute: Int,
    onConfirm: (Int, Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val pickerState: TimePickerState = rememberTimePickerState(
        initialHour = initialHour,
        initialMinute = initialMinute,
        is24Hour = false,
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, style = MaterialTheme.typography.titleMedium) },
        text  = { TimePicker(state = pickerState) },
        confirmButton = {
            TextButton(onClick = { onConfirm(pickerState.hour, pickerState.minute) }) {
                Text("OK")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
