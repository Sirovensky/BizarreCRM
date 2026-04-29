package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SmsSettingsState(
    /** Name of the configured SMS provider (e.g. "twilio", "telnyx"). */
    val providerType: String = "",
    /** Sender phone number / TFN / short code in E.164 or alphanumeric. */
    val senderNumber: String = "",
    /** Off-hours auto-reply message template. */
    val offHoursReply: String = "",
    /** TCPA/CTIA compliance footer text. */
    val complianceFooter: String = "Reply STOP to opt out.",
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
)

@HiltViewModel
class SmsSettingsViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SmsSettingsState(isLoading = true))
    val uiState: StateFlow<SmsSettingsState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val configResult = runCatching { settingsApi.getStoreConfig() }
            val providersResult = runCatching { settingsApi.getSmsProviders() }

            val cfg = configResult.getOrNull()?.data ?: emptyMap()

            // Determine active provider type from store-config key "sms_provider_type".
            // Fall back to the name of the first provider entry from getSmsProviders() if absent.
            val providerFromProviders = providersResult.getOrNull()?.data
                ?.firstOrNull()
                ?.get("provider_type") as? String ?: ""

            _uiState.value = SmsSettingsState(
                providerType = cfg["sms_provider_type"] ?: providerFromProviders,
                senderNumber = cfg["sms_sender_number"] ?: cfg["sms_from_number"] ?: "",
                offHoursReply = cfg["sms_off_hours_reply"] ?: "",
                complianceFooter = cfg["sms_compliance_footer"] ?: "Reply STOP to opt out.",
                isLoading = false,
                errorMessage = configResult.exceptionOrNull()?.message,
            )
        }
    }

    fun update(block: SmsSettingsState.() -> SmsSettingsState) {
        _uiState.value = _uiState.value.block()
    }

    fun save() {
        val s = _uiState.value
        _uiState.value = s.copy(isSaving = true, errorMessage = null)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(
                    mapOf(
                        "sms_sender_number" to s.senderNumber,
                        "sms_off_hours_reply" to s.offHoursReply,
                        "sms_compliance_footer" to s.complianceFooter,
                    )
                )
            }
                .onSuccess {
                    _uiState.value = _uiState.value.copy(isSaving = false, savedOk = true)
                }
                .onFailure {
                    _uiState.value = _uiState.value.copy(
                        isSaving = false,
                        errorMessage = "Save failed: ${it.message}",
                    )
                }
        }
    }

    fun clearSavedOk() {
        _uiState.value = _uiState.value.copy(savedOk = false)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsSettingsScreen(
    onBack: () -> Unit,
    viewModel: SmsSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.savedOk) {
        if (state.savedOk) {
            snackbarHostState.showSnackbar("SMS settings saved")
            viewModel.clearSavedOk()
        }
    }
    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("SMS Settings") },
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
            ) {
                CircularProgressIndicator()
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Provider status (read-only; configured via web admin)
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Provider", style = MaterialTheme.typography.titleSmall)
                    Text(
                        if (state.providerType.isNotBlank())
                            "Connected: ${state.providerType.replaceFirstChar { it.uppercase() }}"
                        else
                            "No SMS provider configured",
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (state.providerType.isNotBlank())
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.error,
                    )
                    Text(
                        "Android version settings coming soon. Configuration synchronizes with the web admin panel when available.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Sender number
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Sender", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.senderNumber,
                        onValueChange = { viewModel.update { copy(senderNumber = it) } },
                        label = { Text("From number / TFN / Sender ID") },
                        supportingText = { Text("E.164 format (+12125551234) or alphanumeric sender") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Phone,
                            imeAction = ImeAction.Next,
                        ),
                        singleLine = true,
                    )
                }
            }

            // Compliance footer
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Compliance", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.complianceFooter,
                        onValueChange = { viewModel.update { copy(complianceFooter = it) } },
                        label = { Text("Opt-out footer") },
                        supportingText = { Text("Appended once per recipient per TCPA/CTIA rules") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        singleLine = true,
                    )
                }
            }

            // Off-hours auto-reply
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Off-hours auto-reply", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.offHoursReply,
                        onValueChange = { viewModel.update { copy(offHoursReply = it) } },
                        label = { Text("Auto-reply template") },
                        supportingText = { Text("Sent automatically during off-hours. Leave blank to disable.") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        minLines = 3,
                        maxLines = 5,
                    )
                }
            }

            Spacer(Modifier.height(8.dp))

            FilledTonalButton(
                onClick = { viewModel.save() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isSaving,
            ) {
                if (state.isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp).height(18.dp),
                        strokeWidth = 2.dp,
                    )
                }
                Text("Save changes")
            }
        }
    }
}
