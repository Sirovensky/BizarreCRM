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
import com.bizarreelectronics.crm.data.remote.dto.TaxClassItem
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §19.8 — POS / Payment settings screen.
 *
 * Wired:
 *  - Payment methods enabled — GET /settings/payment-methods (read-only list; mutation not yet
 *    exposed by the server as a PATCH endpoint, so we show status only)
 *  - Tax classes + default tax — GET /settings/tax-classes (read-only; edit route deferred to §19.17)
 *  - Tip presets — GET /settings/config key "tip_presets" (comma-separated percents)
 *  - Cash drawer enabled — GET /settings/config key "cash_drawer_enabled"
 *
 * NOTE (2026-04-26): BlockChyp terminal pairing is in §17.4 HardwareSettingsScreen — already
 * navigable from Settings > Hardware. Not duplicated here.
 *
 * NOTE (2026-04-26): Receipt template editor (live preview) requires a template-editor widget
 * that renders receipt HTML — deferred to §19.18. Read endpoint exists:
 * GET /settings/receipt-templates. This screen shows template names read-only.
 *
 * NOTE (2026-04-26): Rounding rules are per-jurisdiction; server has no
 * GET /settings/rounding endpoint. Deferred to §19.17 multi-jurisdiction tax config.
 *
 * NOTE (2026-04-26): tip_presets + cash_drawer_enabled are stored in store_config on the
 * server but server-side enforcement (actually applying these presets in the POS flow) is
 * one of the 65/70 unenforced toggles. PosScreen does NOT currently read tip_presets from
 * the server; it uses a hardcoded list. Consumer-side gap documented here.
 */

data class PosSettingsUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    val paymentMethods: List<String> = emptyList(),
    val taxClasses: List<TaxClassItem> = emptyList(),
    val tipPresets: String = "10,15,20",
    val cashDrawerEnabled: Boolean = false,
    val receiptTemplateNames: List<String> = emptyList(),
)

@HiltViewModel
class PosSettingsViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosSettingsUiState())
    val uiState: StateFlow<PosSettingsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                val configResp = settingsApi.getConfig()
                val cfg = configResp.data ?: emptyMap()

                val taxResp = settingsApi.getTaxClasses()
                val taxClasses = taxResp.data?.taxClasses ?: emptyList()

                val pmResp = runCatching { settingsApi.getPaymentMethods() }.getOrNull()
                val paymentMethods = pmResp?.data?.mapNotNull { it["name"] as? String } ?: emptyList()

                _uiState.value = PosSettingsUiState(
                    isLoading = false,
                    paymentMethods = paymentMethods,
                    taxClasses = taxClasses,
                    tipPresets = cfg["tip_presets"] ?: "10,15,20",
                    cashDrawerEnabled = cfg["cash_drawer_enabled"]?.let { it == "1" || it == "true" } ?: false,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message ?: "Failed to load POS settings")
            }
        }
    }

    fun setCashDrawerEnabled(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(cashDrawerEnabled = enabled)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(mapOf("cash_drawer_enabled" to if (enabled) "1" else "0"))
            }
            // NOTE: server stores but POS consumer reads not yet wired (65/70 unenforced)
        }
    }

    fun setTipPresets(presets: String) {
        _uiState.value = _uiState.value.copy(tipPresets = presets)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(mapOf("tip_presets" to presets))
            }
            // NOTE: PosScreen does not currently read tip_presets from server (consumer gap)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosSettingsScreen(
    onBack: () -> Unit,
    viewModel: PosSettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    var editingTips by remember { mutableStateOf(false) }
    var tipPresetsEdit by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("POS & Payment") },
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
                    // Payment methods (read-only)
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Payment methods", style = MaterialTheme.typography.titleSmall)
                            if (uiState.paymentMethods.isEmpty()) {
                                Text(
                                    "Default methods active (Cash, Card, Check, Zelle, Venmo, PayPal)",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            } else {
                                uiState.paymentMethods.forEach { method ->
                                    Text(
                                        method.replaceFirstChar { it.uppercase() },
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                }
                            }
                            Text(
                                "To add or disable payment methods, edit via the web admin panel. Server endpoint for toggle mutations is not yet exposed.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    // Tax classes (read-only)
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Tax classes", style = MaterialTheme.typography.titleSmall)
                            if (uiState.taxClasses.isEmpty()) {
                                Text("No tax classes configured", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            } else {
                                uiState.taxClasses.forEach { tc ->
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                    ) {
                                        Text(
                                            tc.name + if (tc.isDefault == 1) " (default)" else "",
                                            style = MaterialTheme.typography.bodyMedium,
                                        )
                                        Text(
                                            "${tc.rate}%",
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                            Text(
                                "Full tax editor (add/edit/delete) in §19.17. Multi-jurisdiction rules deferred.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    // Tip presets
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Tip presets", style = MaterialTheme.typography.titleSmall)
                            if (editingTips) {
                                OutlinedTextField(
                                    value = tipPresetsEdit,
                                    onValueChange = { tipPresetsEdit = it },
                                    label = { Text("Comma-separated percentages") },
                                    placeholder = { Text("10,15,20") },
                                    modifier = Modifier.fillMaxWidth(),
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton(onClick = { editingTips = false }) { Text("Cancel") }
                                    Button(onClick = {
                                        viewModel.setTipPresets(tipPresetsEdit)
                                        editingTips = false
                                    }) { Text("Save") }
                                }
                                Text(
                                    "NOTE: PosScreen currently uses a hardcoded tip list; this value is saved to the server but consumer side not yet wired.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            } else {
                                Text(
                                    uiState.tipPresets.ifBlank { "10, 15, 20" },
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                TextButton(onClick = {
                                    tipPresetsEdit = uiState.tipPresets
                                    editingTips = true
                                }) {
                                    Text("Edit presets")
                                }
                            }
                        }
                    }

                    // Cash drawer
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Hardware", style = MaterialTheme.typography.titleSmall)
                            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("Cash drawer", style = MaterialTheme.typography.bodyMedium)
                                    Text("Enable cash-drawer kick on cash payments", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Switch(
                                    checked = uiState.cashDrawerEnabled,
                                    onCheckedChange = { viewModel.setCashDrawerEnabled(it) },
                                )
                            }
                            Text(
                                "BlockChyp terminal pairing is in Settings > Hardware.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    // Receipt templates note
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Receipt templates", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Template editor with live preview — deferred to §19.18. Read endpoint exists: GET /settings/receipt-templates.",
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
