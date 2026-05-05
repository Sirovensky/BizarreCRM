package com.bizarreelectronics.crm.ui.screens.settings.hardware

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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.PrinterManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// §17.4 L1881-L1887 — Printer Discovery & Pairing screen.
//
// Lists paired/discovered Bluetooth printers with:
//   - Role assignment (Receipt / Label / Invoice)
//   - "Test print" button per printer
//   - "Remove" button to unpair
//   - "Kick drawer" verification button
//   - Status pill ("Ready" / "Not connected")

data class PrinterDiscoveryUiState(
    val discoveredPrinters: List<BluetoothDevice> = emptyList(),
    val pairedRoles: Map<PrinterManager.PrinterRole, String?> = emptyMap(), // role → address
    val statusMap: Map<String, PrinterManager.PrinterStatus> = emptyMap(),
    val testPrintResult: String? = null,
    val kickDrawerResult: String? = null,
    val isScanning: Boolean = false,
)

@HiltViewModel
class PrinterDiscoveryViewModel @Inject constructor(
    private val printerManager: PrinterManager,
) : ViewModel() {

    private val _state = MutableStateFlow(PrinterDiscoveryUiState())
    val state = _state.asStateFlow()

    init {
        viewModelScope.launch {
            printerManager.printerStatus.collect { map ->
                _state.value = _state.value.copy(statusMap = map)
            }
        }
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isScanning = true)
            val devices = printerManager.discoverBluetoothPrinters()
            val roles = PrinterManager.PrinterRole.entries.associateWith {
                printerManager.getPairedAddress(it)
            }
            _state.value = _state.value.copy(
                discoveredPrinters = devices,
                pairedRoles = roles,
                isScanning = false,
            )
            // Probe connections
            printerManager.onActivityResume()
        }
    }

    fun pair(device: BluetoothDevice, role: PrinterManager.PrinterRole) {
        printerManager.pair(device, role)
        refresh()
    }

    fun unpair(role: PrinterManager.PrinterRole) {
        printerManager.unpair(role)
        refresh()
    }

    fun testPrint(role: PrinterManager.PrinterRole) {
        viewModelScope.launch {
            val result = printerManager.testPrint(role)
            _state.value = _state.value.copy(
                testPrintResult = if (result.isSuccess) "Test print sent to ${role.label} printer"
                else "Test print failed: ${result.exceptionOrNull()?.message}",
            )
        }
    }

    fun kickDrawer() {
        viewModelScope.launch {
            val result = printerManager.kickDrawer()
            _state.value = _state.value.copy(
                kickDrawerResult = if (result.isSuccess) "Cash drawer kicked"
                else "Kick failed: ${result.exceptionOrNull()?.message}",
            )
        }
    }

    fun clearTestResult() { _state.value = _state.value.copy(testPrintResult = null) }
    fun clearKickResult() { _state.value = _state.value.copy(kickDrawerResult = null) }
}

@OptIn(ExperimentalMaterial3Api::class)
@SuppressLint("MissingPermission")
@Composable
fun PrinterDiscoveryScreen(
    onBack: () -> Unit,
    viewModel: PrinterDiscoveryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.testPrintResult) {
        val msg = state.testPrintResult
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearTestResult()
        }
    }
    LaunchedEffect(state.kickDrawerResult) {
        val msg = state.kickDrawerResult
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearKickResult()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Printer Setup",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
            // Scanning indicator
            if (state.isScanning) {
                item {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text("Scanning...", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }

            // Paired roles section
            item {
                Text("PAIRED PRINTERS", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            items(PrinterManager.PrinterRole.entries) { role ->
                val pairedAddress = state.pairedRoles[role]
                val pairedName = if (pairedAddress != null) {
                    state.discoveredPrinters
                        .firstOrNull { it.address == pairedAddress }
                        ?.name ?: pairedAddress
                } else null
                val status = pairedAddress?.let { state.statusMap[it] }

                PairedPrinterCard(
                    role = role,
                    deviceName = pairedName,
                    status = status,
                    onTestPrint = { viewModel.testPrint(role) },
                    onRemove = { viewModel.unpair(role) },
                    onKickDrawer = if (role == PrinterManager.PrinterRole.Receipt) {
                        { viewModel.kickDrawer() }
                    } else null,
                )
            }

            // Discovered printers section
            if (state.discoveredPrinters.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(8.dp))
                    Text("AVAILABLE PRINTERS", style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(state.discoveredPrinters, key = { it.address }) { device ->
                    DiscoveredPrinterCard(
                        device = device,
                        currentRoles = state.pairedRoles.entries
                            .filter { it.value == device.address }
                            .map { it.key },
                        onAssignRole = { role -> viewModel.pair(device, role) },
                    )
                }
            } else if (!state.isScanning) {
                item {
                    ConnectPrinterCta()
                }
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun PairedPrinterCard(
    role: PrinterManager.PrinterRole,
    deviceName: String?,
    status: PrinterManager.PrinterStatus?,
    onTestPrint: () -> Unit,
    onRemove: () -> Unit,
    onKickDrawer: (() -> Unit)?,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
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
                    Icon(Icons.Default.Print, contentDescription = null)
                    Column {
                        Text(role.label, style = MaterialTheme.typography.titleSmall)
                        if (deviceName != null) {
                            Text(deviceName, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                StatusPill(status = status ?: PrinterManager.PrinterStatus.NotConnected)
            }

            if (deviceName != null) {
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onTestPrint) {
                        Icon(Icons.Default.Print, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Test print")
                    }
                    if (onKickDrawer != null) {
                        OutlinedButton(onClick = onKickDrawer) {
                            Icon(Icons.Default.LockOpen, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Kick drawer")
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = onRemove) {
                        Text("Remove", color = MaterialTheme.colorScheme.error)
                    }
                }
            } else {
                Spacer(Modifier.height(8.dp))
                Text(
                    "No printer assigned — pair one below",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun DiscoveredPrinterCard(
    device: BluetoothDevice,
    currentRoles: List<PrinterManager.PrinterRole>,
    onAssignRole: (PrinterManager.PrinterRole) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
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
                    Icon(Icons.Default.BluetoothConnected, contentDescription = null)
                    Column {
                        Text(device.name ?: "Unknown device", style = MaterialTheme.typography.bodyMedium)
                        Text(device.address, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (currentRoles.isNotEmpty()) {
                    AssistChip(
                        onClick = {},
                        label = { Text(currentRoles.first().label) },
                    )
                } else {
                    Button(onClick = { expanded = true }) {
                        Text("Assign Role")
                    }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        PrinterManager.PrinterRole.entries.forEach { role ->
                            DropdownMenuItem(
                                text = { Text(role.label) },
                                onClick = {
                                    onAssignRole(role)
                                    expanded = false
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusPill(status: PrinterManager.PrinterStatus) {
    val (label, color) = when (status) {
        PrinterManager.PrinterStatus.Ready -> "Ready" to MaterialTheme.colorScheme.primary
        PrinterManager.PrinterStatus.Connecting -> "Connecting..." to MaterialTheme.colorScheme.tertiary
        PrinterManager.PrinterStatus.NotConnected -> "Not connected" to MaterialTheme.colorScheme.error
    }
    Surface(
        shape = MaterialTheme.shapes.small,
        color = color.copy(alpha = 0.12f),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun ConnectPrinterCta() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest),
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                Icons.Default.PrintDisabled,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "No printers found",
                style = MaterialTheme.typography.titleSmall,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Pair a Bluetooth printer in Android Settings, then refresh here.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
