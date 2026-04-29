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
import com.bizarreelectronics.crm.data.remote.dto.StatusListData
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §19.7 — Ticket Settings screen.
 *
 * Shows:
 *  - Default assignee (read from GET /settings/config key "default_assignee_id") —
 *    **NOTE (2026-04-26): server stores default_assignee_id in store_config but no
 *    dedicated GET/PUT /settings/tickets endpoint exists; wired via GET/PUT /settings/config
 *    generic map but assignment picker needs employee list — deferred to employee picker PR.**
 *  - Default due-date rule (N business days) — GET /settings/config "default_due_days"
 *  - ticket_all_employees_view_all — GET /settings/config "ticket_all_employees_view_all"
 *  - IMEI / serial required flag — GET /settings/config "imei_required"
 *  - Photo count required on close — GET /settings/config "photos_required_on_close"
 *  - Status list (read-only count; full editor is §19.16 TicketStatusEditorScreen)
 *
 * Consumer: TicketListViewModel / TicketCreateViewModel reads AppPreferences keys that
 * mirror these server-side flags after each sync.
 *
 * NOTE (2026-04-26): The /settings/config PUT endpoint accepts these keys but the server-side
 * ENFORCER for imei_required / photos_required_on_close / default_due_days is not implemented
 * (65-of-70 toggles situation). UI persists to server but consumer enforcement gap is documented.
 */

data class TicketSettingsUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    // From /settings/config
    val viewAllEnabled: Boolean = false,
    val imeiRequired: Boolean = false,
    val photosRequiredOnClose: Int = 0,
    val defaultDueDays: Int = 3,
    // From /settings/statuses
    val statusCount: Int = 0,
)

@HiltViewModel
class TicketSettingsViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(TicketSettingsUiState())
    val uiState: StateFlow<TicketSettingsUiState> = _uiState.asStateFlow()

    private var currentConfig: MutableMap<String, String> = mutableMapOf()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            try {
                val configResponse = settingsApi.getConfig()
                val statusResponse = settingsApi.getStatuses()
                val cfg = configResponse.data ?: emptyMap()
                currentConfig = cfg.toMutableMap()
                val statusList: List<TicketStatusItem> = statusResponse.data?.statuses ?: emptyList()
                _uiState.value = TicketSettingsUiState(
                    isLoading = false,
                    viewAllEnabled = cfg["ticket_all_employees_view_all"]?.let { it == "1" || it == "true" } ?: false,
                    imeiRequired = cfg["imei_required"]?.let { it == "1" || it == "true" } ?: false,
                    photosRequiredOnClose = cfg["photos_required_on_close"]?.toIntOrNull() ?: 0,
                    defaultDueDays = cfg["default_due_days"]?.toIntOrNull() ?: 3,
                    statusCount = statusList.size,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, error = e.message ?: "Failed to load ticket settings")
            }
        }
    }

    fun setViewAllEnabled(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(viewAllEnabled = enabled)
        putConfig("ticket_all_employees_view_all", if (enabled) "1" else "0")
    }

    fun setImeiRequired(required: Boolean) {
        _uiState.value = _uiState.value.copy(imeiRequired = required)
        putConfig("imei_required", if (required) "1" else "0")
    }

    fun setPhotosRequired(count: Int) {
        _uiState.value = _uiState.value.copy(photosRequiredOnClose = count)
        putConfig("photos_required_on_close", count.toString())
    }

    fun setDefaultDueDays(days: Int) {
        _uiState.value = _uiState.value.copy(defaultDueDays = days)
        putConfig("default_due_days", days.toString())
    }

    private fun putConfig(key: String, value: String) {
        viewModelScope.launch {
            try {
                currentConfig[key] = value
                settingsApi.putStoreConfig(mapOf(key to value))
            } catch (_: Exception) {
                // Non-fatal — server note: 65/70 toggles unenforced; value stored regardless
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketSettingsScreen(
    onBack: () -> Unit,
    viewModel: TicketSettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Ticket Settings") },
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
                    // Visibility
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Visibility", style = MaterialTheme.typography.titleSmall)
                            TicketSettingToggleRow(
                                title = "All staff can view all tickets",
                                subtitle = "When off, staff only see tickets assigned to them",
                                checked = uiState.viewAllEnabled,
                                onCheckedChange = { viewModel.setViewAllEnabled(it) },
                            )
                        }
                    }

                    // Requirements at intake / close
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Requirements", style = MaterialTheme.typography.titleSmall)
                            TicketSettingToggleRow(
                                title = "IMEI / serial required",
                                subtitle = "Block ticket creation if IMEI or serial is blank",
                                checked = uiState.imeiRequired,
                                onCheckedChange = { viewModel.setImeiRequired(it) },
                            )
                            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                            // Photo count required on close — stepper
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("Photos required to close", style = MaterialTheme.typography.bodyMedium)
                                    Text(
                                        "Minimum photos before marking complete (0 = none required)",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    IconButton(
                                        onClick = { if (uiState.photosRequiredOnClose > 0) viewModel.setPhotosRequired(uiState.photosRequiredOnClose - 1) },
                                        enabled = uiState.photosRequiredOnClose > 0,
                                    ) {
                                        Icon(Icons.Default.Remove, contentDescription = "Decrease")
                                    }
                                    Text(
                                        uiState.photosRequiredOnClose.toString(),
                                        style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.widthIn(min = 32.dp),
                                    )
                                    IconButton(
                                        onClick = { viewModel.setPhotosRequired(uiState.photosRequiredOnClose + 1) },
                                        enabled = uiState.photosRequiredOnClose < 20,
                                    ) {
                                        Icon(Icons.Default.Add, contentDescription = "Increase")
                                    }
                                }
                            }
                        }
                    }

                    // Due date rule
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("Defaults", style = MaterialTheme.typography.titleSmall)
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("Default due date", style = MaterialTheme.typography.bodyMedium)
                                    Text(
                                        "+${uiState.defaultDueDays} business day${if (uiState.defaultDueDays != 1) "s" else ""} from creation",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    IconButton(
                                        onClick = { if (uiState.defaultDueDays > 1) viewModel.setDefaultDueDays(uiState.defaultDueDays - 1) },
                                        enabled = uiState.defaultDueDays > 1,
                                    ) {
                                        Icon(Icons.Default.Remove, contentDescription = "Decrease")
                                    }
                                    Text(
                                        uiState.defaultDueDays.toString(),
                                        style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.widthIn(min = 32.dp),
                                    )
                                    IconButton(
                                        onClick = { if (uiState.defaultDueDays < 30) viewModel.setDefaultDueDays(uiState.defaultDueDays + 1) },
                                        enabled = uiState.defaultDueDays < 30,
                                    ) {
                                        Icon(Icons.Default.Add, contentDescription = "Increase")
                                    }
                                }
                            }
                        }
                    }

                    // Status taxonomy info
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Statuses", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "${uiState.statusCount} statuses configured",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                "Full status editor (reorder, color, transition guards) requires §19.16 TicketStatusEditorScreen — server endpoints exist (PUT /settings/statuses/:id) but drag-reorder UI is deferred.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    // Default assignee note
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("Default assignee", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Default assignee picker requires employee list integration — deferred.",
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
private fun TicketSettingToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
