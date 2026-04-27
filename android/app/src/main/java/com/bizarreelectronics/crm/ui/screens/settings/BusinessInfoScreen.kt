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
 * §19.19 — Business Info settings screen.
 *
 * Wired to GET /settings/store and PUT /settings/store.
 * Allowed keys per server allowlist:
 *   store_name, address, phone, email, timezone, currency, tax_rate,
 *   receipt_header, receipt_footer, logo_url, sms_provider
 *
 * NOTE (2026-04-26): Tax ID / EIN — server store_config has no dedicated tax_id/ein key
 * in the PUT allowlist. Deferred.
 *
 * NOTE (2026-04-26): Social links — no social_* keys in PUT allowlist. Deferred.
 *
 * NOTE (2026-04-26): "Display on public tracking page / receipts / invoices" — server-side
 * rendering for public tracking (§55) and invoices already uses store_name / address / logo_url.
 * No per-field toggle exists on the server. Consumer IS wired (server reads store_config in
 * invoice/receipt templates). Saving store_name+address here therefore affects all those surfaces.
 */

data class BusinessInfoUiState(
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val saveSuccess: Boolean = false,
    // Editable fields
    val storeName: String = "",
    val address: String = "",
    val phone: String = "",
    val email: String = "",
    val logoUrl: String = "",
    val receiptHeader: String = "",
    val receiptFooter: String = "",
)

@HiltViewModel
class BusinessInfoViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(BusinessInfoUiState())
    val uiState: StateFlow<BusinessInfoUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null, saveSuccess = false)
            try {
                val resp = settingsApi.getStoreConfig()
                val cfg = resp.data ?: emptyMap()
                _uiState.value = BusinessInfoUiState(
                    isLoading = false,
                    storeName = cfg["store_name"] ?: "",
                    address = cfg["address"] ?: "",
                    phone = cfg["phone"] ?: "",
                    email = cfg["email"] ?: "",
                    logoUrl = cfg["logo_url"] ?: "",
                    receiptHeader = cfg["receipt_header"] ?: "",
                    receiptFooter = cfg["receipt_footer"] ?: "",
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message ?: "Failed to load business info")
            }
        }
    }

    fun updateField(field: String, value: String) {
        _uiState.value = when (field) {
            "store_name"     -> _uiState.value.copy(storeName = value)
            "address"        -> _uiState.value.copy(address = value)
            "phone"          -> _uiState.value.copy(phone = value)
            "email"          -> _uiState.value.copy(email = value)
            "logo_url"       -> _uiState.value.copy(logoUrl = value)
            "receipt_header" -> _uiState.value.copy(receiptHeader = value)
            "receipt_footer" -> _uiState.value.copy(receiptFooter = value)
            else             -> _uiState.value
        }
    }

    fun save() {
        val s = _uiState.value
        _uiState.value = s.copy(isSaving = true, error = null, saveSuccess = false)
        viewModelScope.launch {
            try {
                settingsApi.putStoreConfig(
                    mapOf(
                        "store_name"     to s.storeName,
                        "address"        to s.address,
                        "phone"          to s.phone,
                        "email"          to s.email,
                        "logo_url"       to s.logoUrl,
                        "receipt_header" to s.receiptHeader,
                        "receipt_footer" to s.receiptFooter,
                    )
                )
                _uiState.value = _uiState.value.copy(isSaving = false, saveSuccess = true)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isSaving = false, error = e.message ?: "Save failed")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BusinessInfoScreen(
    onBack: () -> Unit,
    viewModel: BusinessInfoViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.saveSuccess) {
        if (uiState.saveSuccess) snackbarHostState.showSnackbar("Business info saved")
    }
    LaunchedEffect(uiState.error) {
        val err = uiState.error
        if (err != null && !uiState.isLoading) snackbarHostState.showSnackbar(err)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Business Info") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (!uiState.isLoading) {
                        if (uiState.isSaving) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp).padding(end = 16.dp), strokeWidth = 2.dp)
                        } else {
                            TextButton(onClick = { viewModel.save() }) { Text("Save") }
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            uiState.isLoading -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            uiState.error != null && !uiState.isSaving -> {
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
                    // Basic info
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Shop details", style = MaterialTheme.typography.titleSmall)
                            BizInfoField(
                                label = "Shop name",
                                value = uiState.storeName,
                                onValueChange = { viewModel.updateField("store_name", it) },
                                icon = Icons.Default.Store,
                            )
                            BizInfoField(
                                label = "Address",
                                value = uiState.address,
                                onValueChange = { viewModel.updateField("address", it) },
                                icon = Icons.Default.LocationOn,
                                singleLine = false,
                                minLines = 2,
                            )
                            BizInfoField(
                                label = "Phone",
                                value = uiState.phone,
                                onValueChange = { viewModel.updateField("phone", it) },
                                icon = Icons.Default.Phone,
                            )
                            BizInfoField(
                                label = "Email",
                                value = uiState.email,
                                onValueChange = { viewModel.updateField("email", it) },
                                icon = Icons.Default.Email,
                            )
                        }
                    }

                    // Logo
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Logo", style = MaterialTheme.typography.titleSmall)
                            BizInfoField(
                                label = "Logo URL",
                                value = uiState.logoUrl,
                                onValueChange = { viewModel.updateField("logo_url", it) },
                                icon = Icons.Default.Image,
                            )
                            Text(
                                "Appears on receipts, invoices, and the public tracking page. Upload via the web admin panel for managed hosting.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    // Receipt header/footer
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Receipt text", style = MaterialTheme.typography.titleSmall)
                            BizInfoField(
                                label = "Receipt header",
                                value = uiState.receiptHeader,
                                onValueChange = { viewModel.updateField("receipt_header", it) },
                                icon = Icons.Default.Receipt,
                                singleLine = false,
                                minLines = 2,
                            )
                            BizInfoField(
                                label = "Receipt footer",
                                value = uiState.receiptFooter,
                                onValueChange = { viewModel.updateField("receipt_footer", it) },
                                icon = Icons.Default.Receipt,
                                singleLine = false,
                                minLines = 2,
                            )
                        }
                    }

                    // Deferred items
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Not available on mobile", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Tax ID / EIN — not in PUT /settings/store allowlist. Deferred.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                "Social links — no social_* keys in server allowlist. Deferred.",
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

@Composable
private fun BizInfoField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    singleLine: Boolean = true,
    minLines: Int = 1,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        leadingIcon = { Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp)) },
        modifier = Modifier.fillMaxWidth(),
        singleLine = singleLine,
        minLines = minLines,
    )
}
