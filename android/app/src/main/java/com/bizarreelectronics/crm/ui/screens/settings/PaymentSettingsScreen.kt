package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
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

data class PaymentMethod(
    val id: Long,
    val name: String,
    val isActive: Boolean,
)

data class PaymentSettingsState(
    val paymentMethods: List<PaymentMethod> = emptyList(),
    /** BlockChyp terminal name (device display name). */
    val blockChypTerminalName: String = "",
    /** Tip presets as comma-separated percentages (e.g. "15,18,20"). */
    val tipPresets: String = "",
    /** Whether to prompt for tip on BlockChyp terminal. */
    val promptForTip: Boolean = false,
    /** Whether cash drawer is enabled. */
    val cashDrawerEnabled: Boolean = false,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
)

@HiltViewModel
class PaymentSettingsViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PaymentSettingsState(isLoading = true))
    val uiState: StateFlow<PaymentSettingsState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val methodsResult = runCatching { settingsApi.getPaymentMethods() }
            val configResult = runCatching { settingsApi.getStoreConfig() }

            val methods = methodsResult.getOrNull()?.data?.mapNotNull { m ->
                val id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null
                val name = m["name"] as? String ?: return@mapNotNull null
                val active = (m["is_active"] as? Number)?.toInt() != 0
                PaymentMethod(id, name, active)
            } ?: emptyList()

            val cfg = configResult.getOrNull()?.data ?: emptyMap()

            _uiState.value = PaymentSettingsState(
                paymentMethods = methods,
                blockChypTerminalName = cfg["blockchyp_terminal_name"] ?: "",
                tipPresets = cfg["tip_presets"] ?: "15,18,20",
                promptForTip = cfg["blockchyp_prompt_for_tip"] == "1" || cfg["blockchyp_prompt_for_tip"] == "true",
                cashDrawerEnabled = cfg["cash_drawer_enabled"] == "1" || cfg["cash_drawer_enabled"] == "true",
                isLoading = false,
                errorMessage = methodsResult.exceptionOrNull()?.message,
            )
        }
    }

    fun update(block: PaymentSettingsState.() -> PaymentSettingsState) {
        _uiState.value = _uiState.value.block()
    }

    fun save() {
        val s = _uiState.value
        _uiState.value = s.copy(isSaving = true, errorMessage = null)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(
                    mapOf(
                        "blockchyp_terminal_name" to s.blockChypTerminalName,
                        "tip_presets" to s.tipPresets,
                        "blockchyp_prompt_for_tip" to if (s.promptForTip) "1" else "0",
                        "cash_drawer_enabled" to if (s.cashDrawerEnabled) "1" else "0",
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
fun PaymentSettingsScreen(
    onBack: () -> Unit,
    viewModel: PaymentSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.savedOk) {
        if (state.savedOk) {
            snackbarHostState.showSnackbar("Payment settings saved")
            viewModel.clearSavedOk()
        }
    }
    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("POS & Payment") },
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
            // Payment methods enabled
            if (state.paymentMethods.isNotEmpty()) {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(top = 16.dp, start = 16.dp, end = 16.dp)) {
                        Text("Payment methods", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Managed on the web admin. Showing active methods.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                    state.paymentMethods.forEachIndexed { index, method ->
                        if (index > 0) HorizontalDivider()
                        ListItem(
                            headlineContent = { Text(method.name) },
                            supportingContent = { Text(if (method.isActive) "Active" else "Inactive") },
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }

            // BlockChyp terminal config
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("BlockChyp terminal", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.blockChypTerminalName,
                        onValueChange = { viewModel.update { copy(blockChypTerminalName = it) } },
                        label = { Text("Terminal name") },
                        supportingText = { Text("Display name shown on the payment terminal") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    ListItem(
                        headlineContent = { Text("Prompt for tip") },
                        supportingContent = { Text("Show tip selection screen on terminal") },
                        trailingContent = {
                            Switch(
                                checked = state.promptForTip,
                                onCheckedChange = { viewModel.update { copy(promptForTip = it) } },
                            )
                        },
                    )
                }
            }

            // Tip presets
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Tip presets", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.tipPresets,
                        onValueChange = { viewModel.update { copy(tipPresets = it) } },
                        label = { Text("Preset percentages") },
                        supportingText = { Text("Comma-separated values, e.g. 15,18,20") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                }
            }

            // Cash drawer
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = { Text("Cash drawer") },
                    supportingContent = { Text("Enable automatic cash drawer open on cash sale") },
                    trailingContent = {
                        Switch(
                            checked = state.cashDrawerEnabled,
                            onCheckedChange = { viewModel.update { copy(cashDrawerEnabled = it) } },
                        )
                    },
                )
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
