package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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

data class TicketSettingsState(
    /** Default due date offset in business days (+N). Empty = no default. */
    val defaultDueDays: String = "",
    /** Require IMEI/serial on device before ticket can be saved. */
    val imeiRequired: Boolean = false,
    /** Require at least one photo before closing the ticket. */
    val photoRequiredOnClose: Boolean = false,
    /** All employees can see all tickets (server: ticket_all_employees_view_all). */
    val allEmployeesViewAll: Boolean = false,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
)

@HiltViewModel
class TicketSettingsViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(TicketSettingsState(isLoading = true))
    val uiState: StateFlow<TicketSettingsState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            runCatching { settingsApi.getStoreConfig() }
                .onSuccess { response ->
                    val cfg = response.data ?: emptyMap()
                    _uiState.value = TicketSettingsState(
                        defaultDueDays = cfg["default_due_days"] ?: "",
                        imeiRequired = cfg["imei_required"] == "1" || cfg["imei_required"] == "true",
                        photoRequiredOnClose = cfg["photo_required_on_close"] == "1" || cfg["photo_required_on_close"] == "true",
                        allEmployeesViewAll = cfg["ticket_all_employees_view_all"] == "1" || cfg["ticket_all_employees_view_all"] == "true",
                        isLoading = false,
                    )
                }
                .onFailure {
                    _uiState.value = TicketSettingsState(
                        isLoading = false,
                        errorMessage = "Failed to load ticket settings: ${it.message}",
                    )
                }
        }
    }

    fun update(block: TicketSettingsState.() -> TicketSettingsState) {
        _uiState.value = _uiState.value.block()
    }

    fun save() {
        val s = _uiState.value
        _uiState.value = s.copy(isSaving = true, errorMessage = null)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(
                    mapOf(
                        "default_due_days" to s.defaultDueDays,
                        "imei_required" to if (s.imeiRequired) "1" else "0",
                        "photo_required_on_close" to if (s.photoRequiredOnClose) "1" else "0",
                        "ticket_all_employees_view_all" to if (s.allEmployeesViewAll) "1" else "0",
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
fun TicketSettingsScreen(
    onBack: () -> Unit,
    viewModel: TicketSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.savedOk) {
        if (state.savedOk) {
            snackbarHostState.showSnackbar("Ticket settings saved")
            viewModel.clearSavedOk()
        }
    }
    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Ticket Settings") },
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
            // Due date defaults
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Due date", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.defaultDueDays,
                        onValueChange = { viewModel.update { copy(defaultDueDays = it) } },
                        label = { Text("Default due in (business days)") },
                        supportingText = { Text("Leave blank to require manual entry") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done,
                        ),
                        singleLine = true,
                    )
                }
            }

            // Visibility
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = { Text("All employees view all tickets") },
                    supportingContent = { Text("When off, employees only see tickets assigned to them") },
                    trailingContent = {
                        Switch(
                            checked = state.allEmployeesViewAll,
                            onCheckedChange = { viewModel.update { copy(allEmployeesViewAll = it) } },
                        )
                    },
                )
            }

            // Requirements
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column {
                    Text(
                        "Requirements",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
                    )
                    ListItem(
                        headlineContent = { Text("Require IMEI / serial number") },
                        supportingContent = { Text("Ticket cannot be saved without device IMEI or serial") },
                        trailingContent = {
                            Switch(
                                checked = state.imeiRequired,
                                onCheckedChange = { viewModel.update { copy(imeiRequired = it) } },
                            )
                        },
                    )
                    ListItem(
                        headlineContent = { Text("Require photo on close") },
                        supportingContent = { Text("At least one repair photo required before closing ticket") },
                        trailingContent = {
                            Switch(
                                checked = state.photoRequiredOnClose,
                                onCheckedChange = { viewModel.update { copy(photoRequiredOnClose = it) } },
                            )
                        },
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
