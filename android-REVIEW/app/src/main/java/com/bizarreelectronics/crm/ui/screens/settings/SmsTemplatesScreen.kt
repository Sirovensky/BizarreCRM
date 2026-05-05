package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.dto.SmsTemplateDto
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import androidx.compose.material.icons.filled.Sms
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SmsTemplate(
    val id: Long,
    val name: String,
    val body: String,
    val category: String?,
)

data class SmsTemplatesUiState(
    val templates: List<SmsTemplate> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val offline: Boolean = false,
)

@HiltViewModel
class SmsTemplatesViewModel @Inject constructor(
    private val smsApi: SmsApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(SmsTemplatesUiState())
    val state = _state.asStateFlow()

    init {
        loadTemplates()
    }

    fun loadTemplates() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(
                isLoading = false,
                offline = true,
                templates = emptyList(),
                error = null,
            )
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = smsApi.getTemplates()
                val parsed = (response.data?.templates ?: emptyList()).map { dto ->
                    dto.toSmsTemplate()
                }
                _state.value = _state.value.copy(
                    isLoading = false,
                    templates = parsed,
                    error = null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load templates",
                )
            }
        }
    }
}

private fun SmsTemplateDto.toSmsTemplate() = SmsTemplate(
    id = id,
    name = name,
    body = body,
    category = category,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsTemplatesScreen(
    onBack: () -> Unit,
    onTemplateSelected: (String) -> Unit,
    viewModel: SmsTemplatesViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "SMS templates",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.offline -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Sms,
                        title = "Offline",
                        subtitle = "Templates require a server connection.",
                    )
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load templates",
                        onRetry = { viewModel.loadTemplates() },
                    )
                }
            }
            state.templates.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Sms,
                        title = "No templates",
                        subtitle = "No SMS templates available yet.",
                    )
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(
                        items = state.templates,
                        key = { it.id },
                    ) { template ->
                        SmsTemplateCard(
                            template = template,
                            onClick = { onTemplateSelected(template.body) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SmsTemplateCard(
    template: SmsTemplate,
    onClick: () -> Unit,
) {
    // D5-3: use Card(onClick = ...) overload so ripple renders natively on tap.
    // The previous Card(...)+.clickable pattern suppressed the M3 ripple since
    // the card's surface drew over the indication layer.
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = template.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                if (!template.category.isNullOrBlank()) {
                    AssistChip(
                        onClick = onClick,
                        label = { Text(template.category) },
                    )
                }
            }
            Text(
                text = template.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
            )
        }
    }
}
