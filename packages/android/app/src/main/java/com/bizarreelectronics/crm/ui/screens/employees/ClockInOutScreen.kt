package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ClockInOutUiState(
    val pin: String = "",
    val isClockedIn: Boolean = false,
    val isProcessing: Boolean = false,
    val error: String? = null,
    val successMessage: String? = null,
    val userName: String = "",
)

@HiltViewModel
class ClockInOutViewModel @Inject constructor(
    private val authApi: AuthApi,
    private val settingsApi: SettingsApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
    private val syncQueueDao: SyncQueueDao,
    private val gson: Gson,
) : ViewModel() {

    private val _state = MutableStateFlow(ClockInOutUiState())
    val state = _state.asStateFlow()

    init {
        val firstName = authPreferences.userFirstName.orEmpty()
        val lastName = authPreferences.userLastName.orEmpty()
        _state.value = _state.value.copy(
            userName = "$firstName $lastName".trim().ifBlank { authPreferences.username.orEmpty() },
        )
    }

    fun appendDigit(digit: String) {
        val current = _state.value
        if (current.pin.length < 4 && !current.isProcessing) {
            _state.value = current.copy(pin = current.pin + digit, error = null, successMessage = null)
        }
    }

    fun clearPin() {
        _state.value = _state.value.copy(pin = "", error = null, successMessage = null)
    }

    fun submit() {
        val current = _state.value
        if (current.pin.length != 4) {
            _state.value = current.copy(error = "Enter 4-digit PIN")
            return
        }
        if (current.isProcessing) return

        viewModelScope.launch {
            _state.value = _state.value.copy(isProcessing = true, error = null, successMessage = null)

            val isOnline = serverMonitor.isEffectivelyOnline.value

            if (isOnline) {
                submitOnline()
            } else {
                submitOffline()
            }
        }
    }

    private suspend fun submitOnline() {
        try {
            // Step 1: verify the PIN
            val pinResponse = authApi.verifyPin(mapOf("pin" to _state.value.pin))
            val verified = (pinResponse.data as? Map<*, *>)?.get("verified") == true
            if (!verified) {
                _state.value = _state.value.copy(
                    isProcessing = false,
                    error = "Invalid PIN",
                    pin = "",
                )
                return
            }

            // Step 2: clock in or out
            val userId = authPreferences.userId
            val wasClockedIn = _state.value.isClockedIn

            if (wasClockedIn) {
                settingsApi.clockOut(userId)
            } else {
                settingsApi.clockIn(userId)
            }

            _state.value = _state.value.copy(
                isProcessing = false,
                isClockedIn = !wasClockedIn,
                pin = "",
                successMessage = if (wasClockedIn) "Clocked out successfully" else "Clocked in successfully",
            )
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

        val payload = gson.toJson(mapOf("userId" to userId))
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "employee",
                entityId = userId,
                operation = operation,
                payload = payload,
            )
        )

        // Optimistically toggle local UI state
        _state.value = _state.value.copy(
            isProcessing = false,
            isClockedIn = !wasClockedIn,
            pin = "",
            successMessage = if (wasClockedIn) {
                "Clock out queued \u2014 will sync when online"
            } else {
                "Clock in queued \u2014 will sync when online"
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClockInOutScreen(
    onBack: () -> Unit = {},
    viewModel: ClockInOutViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.successMessage) {
        val msg = state.successMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Clock In / Out",
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
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // Hero icon: primary tint when clocked in (per §3 spec — correct after theme)
            Icon(
                if (state.isClockedIn) Icons.Default.Timer else Icons.Default.TimerOff,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = if (state.isClockedIn) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Status headline — drop manual FontWeight.Bold; theme handles weight
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

            // PIN display — headlineMedium = Barlow Condensed SemiBold (display-condensed slot)
            // Wide letter-spacing for a code-entry feel without needing BrandMono slot yet
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
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
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
                                // §1 spec: "C" clear = BrandDestructiveButton = error container
                                "C" -> ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer,
                                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                )
                                // "OK" = primary purple (correct)
                                "OK" -> ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.primary,
                                    contentColor = MaterialTheme.colorScheme.onPrimary,
                                )
                                // Digit buttons = surfaceVariant; reads well after dark-ramp
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
