package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.ArrowForwardIos
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
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

data class BusinessInfoState(
    val storeName: String = "",
    val address: String = "",
    val phone: String = "",
    val email: String = "",
    val taxId: String = "",
    val socialFacebook: String = "",
    val socialInstagram: String = "",
    val socialWebsite: String = "",
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
)

@HiltViewModel
class BusinessInfoViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(BusinessInfoState(isLoading = true))
    val uiState: StateFlow<BusinessInfoState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            runCatching { settingsApi.getStoreConfig() }
                .onSuccess { response ->
                    val cfg = response.data ?: emptyMap()
                    _uiState.value = BusinessInfoState(
                        storeName = cfg["store_name"] ?: "",
                        address = cfg["address"] ?: "",
                        phone = cfg["phone"] ?: "",
                        email = cfg["email"] ?: "",
                        taxId = cfg["tax_id"] ?: "",
                        socialFacebook = cfg["social_facebook"] ?: "",
                        socialInstagram = cfg["social_instagram"] ?: "",
                        socialWebsite = cfg["website"] ?: "",
                        isLoading = false,
                    )
                }
                .onFailure {
                    _uiState.value = BusinessInfoState(
                        isLoading = false,
                        errorMessage = "Failed to load business info: ${it.message}",
                    )
                }
        }
    }

    fun update(block: BusinessInfoState.() -> BusinessInfoState) {
        _uiState.value = _uiState.value.block()
    }

    fun save() {
        val s = _uiState.value
        _uiState.value = s.copy(isSaving = true, errorMessage = null)
        viewModelScope.launch {
            runCatching {
                settingsApi.putStoreConfig(
                    mapOf(
                        "store_name" to s.storeName,
                        "address" to s.address,
                        "phone" to s.phone,
                        "email" to s.email,
                        "tax_id" to s.taxId,
                        "social_facebook" to s.socialFacebook,
                        "social_instagram" to s.socialInstagram,
                        "website" to s.socialWebsite,
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
fun BusinessInfoScreen(
    onBack: () -> Unit,
    onBusinessHours: (() -> Unit)? = null,
    viewModel: BusinessInfoViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.savedOk) {
        if (state.savedOk) {
            snackbarHostState.showSnackbar("Business info saved")
            viewModel.clearSavedOk()
        }
    }
    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Business Info") },
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
                horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
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
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Store details", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.storeName,
                        onValueChange = { viewModel.update { copy(storeName = it) } },
                        label = { Text("Shop name") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.address,
                        onValueChange = { viewModel.update { copy(address = it) } },
                        label = { Text("Address") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        minLines = 2,
                        maxLines = 3,
                    )
                    OutlinedTextField(
                        value = state.phone,
                        onValueChange = { viewModel.update { copy(phone = it) } },
                        label = { Text("Phone") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Phone,
                            imeAction = ImeAction.Next,
                        ),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.email,
                        onValueChange = { viewModel.update { copy(email = it) } },
                        label = { Text("Email") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Email,
                            imeAction = ImeAction.Next,
                        ),
                        singleLine = true,
                    )
                }
            }

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Tax & legal", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.taxId,
                        onValueChange = { viewModel.update { copy(taxId = it) } },
                        label = { Text("Tax ID / EIN") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        singleLine = true,
                    )
                }
            }

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Social & web", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = state.socialWebsite,
                        onValueChange = { viewModel.update { copy(socialWebsite = it) } },
                        label = { Text("Website URL") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Uri,
                            imeAction = ImeAction.Next,
                        ),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.socialFacebook,
                        onValueChange = { viewModel.update { copy(socialFacebook = it) } },
                        label = { Text("Facebook page URL") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Uri,
                            imeAction = ImeAction.Next,
                        ),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = state.socialInstagram,
                        onValueChange = { viewModel.update { copy(socialInstagram = it) } },
                        label = { Text("Instagram handle") },
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        singleLine = true,
                    )
                }
            }

            // §19.19 — Business hours (dedicated editor screen)
            if (onBusinessHours != null) {
                OutlinedCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(
                            role = Role.Button,
                            onClickLabel = "Edit business hours",
                            onClick = onBusinessHours,
                        ),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column {
                            Text("Business hours", style = MaterialTheme.typography.bodyLarge)
                            Text(
                                "Opening and closing times per day",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowForwardIos,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
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
