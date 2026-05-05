package com.bizarreelectronics.crm.ui.screens.hardware

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.util.ScaleReading
import com.bizarreelectronics.crm.util.ScaleStatus
import com.bizarreelectronics.crm.util.WeightScaleManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// §17.7 — Weight scale pairing + on-demand read screen.
//
// Settings → Hardware → Weight Scale:
//   - Lists bonded Bluetooth devices matching scale heuristics.
//   - Pair / unpair a scale.
//   - "Read weight" button — polls scale over RFCOMM and displays result.
//   - Result is exposed as [WeightScaleUiState.lastReading] so calling screens
//     (ticket detail, shipping label) can consume it via ViewModel injection.

data class WeightScaleUiState(
    val pairedAddress: String? = null,
    val pairedName: String? = null,
    val discoveredScales: List<BluetoothDevice> = emptyList(),
    val scaleStatus: ScaleStatus = ScaleStatus.Idle,
    val lastReading: String? = null,
    val isReading: Boolean = false,
    val showUnpairConfirm: Boolean = false,
    val feedback: String? = null,
)

@HiltViewModel
class WeightScaleViewModel @Inject constructor(
    private val weightScaleManager: WeightScaleManager,
) : ViewModel() {

    private val _state = MutableStateFlow(
        WeightScaleUiState(
            pairedAddress = weightScaleManager.pairedAddress(),
            pairedName = weightScaleManager.pairedName(),
        )
    )
    val state: StateFlow<WeightScaleUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            weightScaleManager.status.collect { status ->
                _state.update { it.copy(scaleStatus = status) }
            }
        }
        discoverScales()
    }

    fun discoverScales() {
        val found = weightScaleManager.discoverScales()
        _state.update { it.copy(discoveredScales = found) }
    }

    fun pairScale(device: BluetoothDevice) {
        @SuppressLint("MissingPermission")
        val name = runCatching { device.name }.getOrNull() ?: device.address
        weightScaleManager.pairScale(device.address, name)
        _state.update {
            it.copy(
                pairedAddress = device.address,
                pairedName = name,
                feedback = "Scale paired: $name",
            )
        }
    }

    fun requestUnpair() {
        _state.update { it.copy(showUnpairConfirm = true) }
    }

    fun confirmUnpair() {
        weightScaleManager.unpairScale()
        _state.update {
            it.copy(
                pairedAddress = null,
                pairedName = null,
                lastReading = null,
                showUnpairConfirm = false,
                feedback = "Scale removed",
            )
        }
    }

    fun dismissUnpairConfirm() {
        _state.update { it.copy(showUnpairConfirm = false) }
    }

    fun readWeight() {
        viewModelScope.launch {
            _state.update { it.copy(isReading = true, lastReading = null) }
            val result = weightScaleManager.requestWeight()
            _state.update {
                it.copy(
                    isReading = false,
                    lastReading = when (result) {
                        is ScaleReading.Weight -> result.displayString
                        is ScaleReading.Error -> null
                    },
                    feedback = when (result) {
                        is ScaleReading.Weight -> "Weight: ${result.displayString}"
                        is ScaleReading.Error -> "Read failed: ${result.reason}"
                    },
                )
            }
        }
    }

    fun clearFeedback() {
        _state.update { it.copy(feedback = null) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeightScaleScreen(
    onBack: () -> Unit,
    viewModel: WeightScaleViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.feedback) {
        val msg = state.feedback ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearFeedback()
    }

    if (state.showUnpairConfirm) {
        ConfirmDialog(
            title = "Remove scale",
            message = "Remove the paired scale? You can re-pair it at any time.",
            confirmLabel = "Remove",
            isDestructive = true,
            onConfirm = { viewModel.confirmUnpair() },
            onDismiss = { viewModel.dismissUnpairConfirm() },
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Weight Scale",
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.discoverScales() },
                        modifier = Modifier.semantics { contentDescription = "Refresh scale list" },
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null)
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Paired scale ──────────────────────────────────────────────────
            item {
                Text(
                    "PAIRED SCALE",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                PairedScaleCard(
                    pairedName = state.pairedName,
                    scaleStatus = state.scaleStatus,
                    lastReading = state.lastReading,
                    isReading = state.isReading,
                    onReadWeight = { viewModel.readWeight() },
                    onUnpair = { viewModel.requestUnpair() },
                )
            }

            // ── Available scales ──────────────────────────────────────────────
            if (state.discoveredScales.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "AVAILABLE SCALES",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(state.discoveredScales, key = { it.address }) { device ->
                    DiscoveredScaleCard(
                        device = device,
                        isPaired = device.address == state.pairedAddress,
                        onPair = { viewModel.pairScale(device) },
                    )
                }
            } else if (state.pairedAddress == null) {
                item {
                    NoScaleCta()
                }
            }
        }
    }
}

@Composable
private fun PairedScaleCard(
    pairedName: String?,
    scaleStatus: ScaleStatus,
    lastReading: String?,
    isReading: Boolean,
    onReadWeight: () -> Unit,
    onUnpair: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Default.Scale,
                        contentDescription = "Weight scale icon",
                    )
                    Column {
                        Text(
                            pairedName ?: "No scale paired",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        if (pairedName != null) {
                            Text(
                                "Bluetooth scale",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                ScaleStatusPill(scaleStatus)
            }

            if (pairedName != null) {
                Spacer(Modifier.height(12.dp))

                if (lastReading != null) {
                    Text(
                        lastReading,
                        style = MaterialTheme.typography.displaySmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .semantics { contentDescription = "Weight reading $lastReading" },
                    )
                    Spacer(Modifier.height(8.dp))
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(
                        onClick = onReadWeight,
                        enabled = !isReading,
                        modifier = Modifier.semantics { contentDescription = "Read weight from scale" },
                    ) {
                        if (isReading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                            )
                            Spacer(Modifier.width(4.dp))
                            Text("Reading…")
                        } else {
                            Icon(
                                Icons.Default.Scale,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                            )
                            Spacer(Modifier.width(4.dp))
                            Text("Read weight")
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = onUnpair,
                        modifier = Modifier.semantics { contentDescription = "Remove paired scale" },
                    ) {
                        Text("Remove", color = MaterialTheme.colorScheme.error)
                    }
                }
            } else {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Pair a Bluetooth scale from the list below.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun DiscoveredScaleCard(
    device: BluetoothDevice,
    isPaired: Boolean,
    onPair: () -> Unit,
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
    ) {
        ListItem(
            headlineContent = { Text(device.name ?: "Unknown device") },
            supportingContent = {
                Text(
                    device.address,
                    style = MaterialTheme.typography.bodySmall,
                )
            },
            leadingContent = {
                Icon(Icons.Default.Bluetooth, contentDescription = "Bluetooth device")
            },
            trailingContent = {
                if (isPaired) {
                    AssistChip(
                        onClick = {},
                        label = { Text("Paired") },
                    )
                } else {
                    FilledTonalButton(
                        onClick = onPair,
                        modifier = Modifier.semantics { contentDescription = "Pair this scale" },
                    ) {
                        Text("Pair")
                    }
                }
            },
        )
    }
}

@Composable
private fun ScaleStatusPill(status: ScaleStatus) {
    val (label, color) = when (status) {
        ScaleStatus.Idle -> "Ready" to MaterialTheme.colorScheme.primary
        ScaleStatus.Reading -> "Reading…" to MaterialTheme.colorScheme.tertiary
        is ScaleStatus.Error -> "Error" to MaterialTheme.colorScheme.error
    }
    Surface(
        shape = MaterialTheme.shapes.small,
        color = color.copy(alpha = 0.12f),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier
                .padding(horizontal = 8.dp, vertical = 4.dp)
                .semantics { contentDescription = "Scale status: $label" },
        )
    }
}

@Composable
private fun NoScaleCta() {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                Icons.Default.Scale,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "No scales found",
                style = MaterialTheme.typography.titleSmall,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Pair a Bluetooth scale in Android Settings, then refresh here.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
