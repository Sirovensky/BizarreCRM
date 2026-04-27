package com.bizarreelectronics.crm.ui.screens.settings

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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §19.9 — SMS Settings screen.
 *
 * Wired:
 *  - Provider connection status — GET /settings/sms/providers (provider name + configured flag)
 *  - Sender number / TFN — GET /settings/store key "sms_from" (read-only; edit via web admin)
 *  - Compliance footer template — editable field saved to /settings/store "sms_compliance_footer"
 *  - Off-hours auto-reply template — read from /settings/store "sms_off_hours_reply"
 *  - Rate-limit display — GET /settings/config key "sms_daily_limit" + AppPreferences SMS opt-in
 *    count as a proxy for usage
 *
 * NOTE (2026-04-26): SMS rate-limit counter is not directly exposed by a server endpoint;
 * /settings/config may carry sms_daily_limit but actual usage counter requires
 * GET /settings/audit-logs or a dedicated quota endpoint that does not exist. Showing
 * the configured limit only.
 *
 * NOTE (2026-04-26): Compliance footer and off-hours auto-reply are stored via
 * PUT /settings/store. The server does NOT enforce the footer on outbound SMS —
 * that enforcement happens in SmsSendHandler which reads from store_config. Consumer
 * IS wired on the server side (L1528 compliance footer logic in sms.routes.ts).
 */

data class SmsSettingsUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    val providerName: String = "Not configured",
    val providerConfigured: Boolean = false,
    val senderNumber: String = "",
    val complianceFooter: String = "",
    val offHoursReply: String = "",
    val dailyLimit: Int = 0,
)

@HiltViewModel
class SmsSettingsViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SmsSettingsUiState())
    val uiState: StateFlow<SmsSettingsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                val storeResp = settingsApi.getStoreConfig()
                val store = storeResp.data ?: emptyMap()

                val providersResp = runCatching { settingsApi.getSmsProviders() }.getOrNull()
                val providers = providersResp?.data ?: emptyList()
                val configured = providers.any { it["configured"] == true || it["enabled"] == true }
                val providerName = providers.firstOrNull()?.get("name")?.toString() ?: "Not configured"

                val configResp = runCatching { settingsApi.getConfig() }.getOrNull()
                val cfg = configResp?.data ?: emptyMap()

                _uiState.value = SmsSettingsUiState(
                    isLoading = false,
                    providerName = store["sms_provider"]?.takeIf { it.isNotBlank() } ?: providerName,
                    providerConfigured = configured || store["sms_provider"]?.isNotBlank() == true,
                    senderNumber = store["sms_from"] ?: "",
                    complianceFooter = store["sms_compliance_footer"] ?: "",
                    offHoursReply = store["sms_off_hours_reply"] ?: "",
                    dailyLimit = cfg["sms_daily_limit"]?.toIntOrNull() ?: 0,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message ?: "Failed to load SMS settings")
            }
        }
    }

    fun saveComplianceFooter(footer: String) {
        _uiState.value = _uiState.value.copy(complianceFooter = footer)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(mapOf("sms_compliance_footer" to footer))
            }
        }
    }

    fun saveOffHoursReply(reply: String) {
        _uiState.value = _uiState.value.copy(offHoursReply = reply)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(mapOf("sms_off_hours_reply" to reply))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsSettingsScreen(
    onBack: () -> Unit,
    viewModel: SmsSettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    var editingFooter by remember { mutableStateOf(false) }
    var footerEdit by remember { mutableStateOf("") }
    var editingReply by remember { mutableStateOf(false) }
    var replyEdit by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SMS Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            uiState.isLoading -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            uiState.error != null -> {
                Box(Modifier.fillMaxSize().padding(padding)) {
                    ErrorState(message = uiState.error!!, onRetry = { viewModel.load() })
                }
            }
            else -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    // Provider status
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Provider", style = MaterialTheme.typography.titleSmall)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(
                                    if (uiState.providerConfigured) Icons.Default.CheckCircle else Icons.Default.Warning,
                                    contentDescription = null,
                                    tint = if (uiState.providerConfigured) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(18.dp),
                                )
                                Text(
                                    uiState.providerName,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                            if (uiState.senderNumber.isNotBlank()) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(uiState.senderNumber, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            Text(
                                "Provider credentials and sender number are configured via the web admin panel (Settings > SMS). Read-only here.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    // Compliance footer
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Compliance footer", style = MaterialTheme.typography.titleSmall)
                            if (editingFooter) {
                                OutlinedTextField(
                                    value = footerEdit,
                                    onValueChange = { footerEdit = it },
                                    label = { Text("Footer text") },
                                    placeholder = { Text("Reply STOP to opt out.") },
                                    modifier = Modifier.fillMaxWidth(),
                                    minLines = 2,
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton(onClick = { editingFooter = false }) { Text("Cancel") }
                                    Button(onClick = {
                                        viewModel.saveComplianceFooter(footerEdit)
                                        editingFooter = false
                                    }) { Text("Save") }
                                }
                            } else {
                                Text(
                                    uiState.complianceFooter.ifBlank { "(Not set — default: \"Reply STOP to opt out.\")" },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (uiState.complianceFooter.isBlank())
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    else
                                        MaterialTheme.colorScheme.onSurface,
                                )
                                TextButton(onClick = {
                                    footerEdit = uiState.complianceFooter
                                    editingFooter = true
                                }) { Text("Edit") }
                            }
                        }
                    }

                    // Off-hours auto-reply
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Off-hours auto-reply", style = MaterialTheme.typography.titleSmall)
                            if (editingReply) {
                                OutlinedTextField(
                                    value = replyEdit,
                                    onValueChange = { replyEdit = it },
                                    label = { Text("Auto-reply message") },
                                    placeholder = { Text("We're closed right now, we'll reply soon.") },
                                    modifier = Modifier.fillMaxWidth(),
                                    minLines = 3,
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton(onClick = { editingReply = false }) { Text("Cancel") }
                                    Button(onClick = {
                                        viewModel.saveOffHoursReply(replyEdit)
                                        editingReply = false
                                    }) { Text("Save") }
                                }
                            } else {
                                Text(
                                    uiState.offHoursReply.ifBlank { "(Not set)" },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (uiState.offHoursReply.isBlank())
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    else
                                        MaterialTheme.colorScheme.onSurface,
                                )
                                TextButton(onClick = {
                                    replyEdit = uiState.offHoursReply
                                    editingReply = true
                                }) { Text("Edit") }
                            }
                        }
                    }

                    // Rate limit / quota
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Rate limits & quota", style = MaterialTheme.typography.titleSmall)
                            if (uiState.dailyLimit > 0) {
                                Text(
                                    "Daily limit: ${uiState.dailyLimit} messages",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                            Text(
                                "Real-time usage counters require a dedicated quota endpoint not yet available. Daily limit shown from config when set.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}
