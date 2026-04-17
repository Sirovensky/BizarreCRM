package com.bizarreelectronics.crm.ui.screens.estimates

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.repository.EstimateRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.LoadingIndicator
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

data class EstimateDetailUiState(
    val estimate: EstimateEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    val convertedTicketId: Long? = null,
    // AND-20260414-M7: bump after a successful delete so the screen can
    // navigate back via a LaunchedEffect — keeps the click handler free of
    // navigation side effects and mirrors how InvoiceDetail uses a counter
    // to close its payment dialog.
    val deletedCounter: Int = 0,
)

@HiltViewModel
class EstimateDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val estimateRepository: EstimateRepository,
) : ViewModel() {

    private val estimateId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(EstimateDetailUiState())
    val state = _state.asStateFlow()

    private var collectJob: Job? = null

    init {
        loadEstimate()
    }

    fun loadEstimate() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            estimateRepository.getEstimate(estimateId)
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load estimate",
                    )
                }
                .collectLatest { entity ->
                    _state.value = _state.value.copy(
                        estimate = entity,
                        isLoading = false,
                    )
                }
        }
    }

    fun convertToTicket() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val ticketId = estimateRepository.convertEstimate(estimateId)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = if (ticketId != null) "Converted to ticket #$ticketId" else "Estimate converted",
                    convertedTicketId = ticketId,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Failed to convert estimate. You must be online.",
                )
            }
        }
    }

    fun sendViaSms() = send("sms")

    fun sendViaEmail() = send("email")

    private fun send(method: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                estimateRepository.sendEstimate(estimateId, method)
                val label = if (method == "sms") "SMS" else "email"
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Estimate sent via $label",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Failed to send estimate. You must be online.",
                )
            }
        }
    }

    fun delete() {
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                estimateRepository.deleteEstimate(estimateId)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Estimate deleted",
                    deletedCounter = _state.value.deletedCounter + 1,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Failed to delete estimate",
                )
            }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    fun clearConvertedTicket() {
        _state.value = _state.value.copy(convertedTicketId = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EstimateDetailScreen(
    estimateId: Long,
    onBack: () -> Unit,
    onConverted: (ticketId: Long) -> Unit,
    // AND-20260414-M7: invoked after a successful delete. Nav graph uses this
    // to write a refresh signal into the previous back stack entry and pop.
    onDeleted: (() -> Unit)? = null,
    viewModel: EstimateDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val estimate = state.estimate

    val snackbarHostState = remember { SnackbarHostState() }
    var showMenu by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    LaunchedEffect(state.convertedTicketId) {
        val ticketId = state.convertedTicketId
        if (ticketId != null) {
            onConverted(ticketId)
            viewModel.clearConvertedTicket()
        }
    }

    // AND-20260414-M7: navigate back once delete succeeds. Using a LaunchedEffect
    // keyed on the counter (not a boolean) so repeated deletes are correctly
    // observed; not that a second delete is possible from this screen, but the
    // counter pattern is defensive and matches InvoiceDetail.
    LaunchedEffect(state.deletedCounter) {
        if (state.deletedCounter > 0) {
            onDeleted?.invoke() ?: onBack()
        }
    }

    if (showDeleteConfirm) {
        ConfirmDialog(
            title = "Delete Estimate",
            message = "Are you sure you want to delete this estimate? This action cannot be undone.",
            confirmLabel = "Delete",
            onConfirm = {
                showDeleteConfirm = false
                viewModel.delete()
            },
            onDismiss = { showDeleteConfirm = false },
            isDestructive = true,
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = estimate?.orderId?.ifBlank { "EST-$estimateId" } ?: "EST-$estimateId",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Send SMS") },
                                leadingIcon = { Icon(Icons.Default.Sms, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    viewModel.sendViaSms()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Send Email") },
                                leadingIcon = { Icon(Icons.Default.Email, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    viewModel.sendViaEmail()
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        "Delete",
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Delete,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                },
                                onClick = {
                                    showMenu = false
                                    showDeleteConfirm = true
                                },
                            )
                        }
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
                    LoadingIndicator()
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
                        message = state.error ?: "Error",
                        onRetry = { viewModel.loadEstimate() },
                    )
                }
            }
            estimate != null -> {
                EstimateDetailContent(
                    estimate = estimate,
                    isActionInProgress = state.isActionInProgress,
                    padding = padding,
                    onConvert = { viewModel.convertToTicket() },
                    onSendSms = { viewModel.sendViaSms() },
                    onSendEmail = { viewModel.sendViaEmail() },
                )
            }
        }
    }
}

@Composable
private fun EstimateDetailContent(
    estimate: EstimateEntity,
    isActionInProgress: Boolean,
    padding: PaddingValues,
    onConvert: () -> Unit,
    onSendSms: () -> Unit,
    onSendEmail: () -> Unit,
) {
    val alreadyConverted = estimate.convertedTicketId != null ||
        estimate.status.equals("converted", ignoreCase = true)

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Header card: order id + status badge
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            estimate.orderId.ifBlank { "EST-${estimate.id}" },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        BrandStatusBadge(
                            label = estimate.status.replaceFirstChar { it.uppercase() },
                            status = estimate.status,
                        )
                    }
                    Text(
                        "Created: ${estimate.createdAt.take(10)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (estimate.convertedTicketId != null) {
                        Text(
                            "Converted to ticket #${estimate.convertedTicketId}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // Customer card
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Customer",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        estimate.customerName ?: "Unknown",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        // Pricing breakdown
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "Pricing",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Subtotal", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            estimate.subtotal.formatAsMoney(),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    if (estimate.discount > 0) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text("Discount", style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "-${estimate.discount.formatAsMoney()}",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Tax", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            estimate.totalTax.formatAsMoney(),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                        thickness = 1.dp,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            "Total",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            estimate.total.formatAsMoney(),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // Valid until
        if (!estimate.validUntil.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            "Valid Until",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            estimate.validUntil.take(10),
                            style = MaterialTheme.typography.bodyLarge,
                        )
                    }
                }
            }
        }

        // Notes
        if (!estimate.notes.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            "Notes",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            estimate.notes,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
        }

        // Convert to Ticket CTA — purple primary (positive terminal action)
        item {
            Spacer(modifier = Modifier.height(4.dp))
            Button(
                onClick = onConvert,
                modifier = Modifier.fillMaxWidth(),
                enabled = !isActionInProgress && !alreadyConverted,
            ) {
                Icon(
                    Icons.Default.SwapHoriz,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(if (alreadyConverted) "Already Converted" else "Convert to Ticket")
            }
        }

        // Secondary send actions — teal text buttons (secondary importance)
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TextButton(
                    onClick = onSendSms,
                    modifier = Modifier.weight(1f),
                    enabled = !isActionInProgress,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.secondary,
                    ),
                ) {
                    Icon(
                        Icons.Default.Sms,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Send SMS")
                }
                TextButton(
                    onClick = onSendEmail,
                    modifier = Modifier.weight(1f),
                    enabled = !isActionInProgress,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.secondary,
                    ),
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.Send,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Send Email")
                }
            }
        }
    }
}
