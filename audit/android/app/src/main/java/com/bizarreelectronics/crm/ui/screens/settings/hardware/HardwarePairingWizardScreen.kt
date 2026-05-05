package com.bizarreelectronics.crm.ui.screens.settings.hardware

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
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
import com.bizarreelectronics.crm.service.WeightScaleService
import com.bizarreelectronics.crm.service.WeightUnit
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.PrinterManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §17.11 — Settings → Hardware → "Add device" pairing wizard.
 *
 * Five-step walkthrough:
 *   Step 1: Device type selection (Printer | Scale | Terminal | Scanner)
 *   Step 2: Enable Bluetooth prompt + discovery
 *   Step 3: Discover & select device from bonded list
 *   Step 4: Role assignment + test (print / weigh / scan)
 *   Step 5: Save + confirmation
 *
 * Per-location config: the wizard stores the pairing in SharedPreferences
 * keyed by device type + role so the same device works across POS and
 * Ticket Detail screens.
 *
 * mock-mode wiring: discovery returns bonded devices from BluetoothAdapter;
 * test operations delegate to [PrinterManager] / [WeightScaleService].
 * Needs physical hardware for end-to-end test.
 */

// ── Wizard state ──────────────────────────────────────────────────────────────

enum class HardwareDeviceType(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Printer("Printer", Icons.Default.Print),
    Scale("Weight Scale", Icons.Default.Scale),
    Terminal("Payment Terminal", Icons.Default.CreditCard),
    Scanner("Barcode Scanner", Icons.Default.QrCodeScanner),
}

enum class WizardStep { SelectType, EnableBluetooth, Discover, RoleAssign, Confirm }

data class PairingWizardUiState(
    val step: WizardStep = WizardStep.SelectType,
    val selectedType: HardwareDeviceType? = null,
    val discoveredDevices: List<BluetoothDevice> = emptyList(),
    val selectedDevice: BluetoothDevice? = null,
    val selectedPrinterRole: PrinterManager.PrinterRole = PrinterManager.PrinterRole.Receipt,
    val selectedScaleUnit: WeightUnit = WeightUnit.LB,
    val isDiscovering: Boolean = false,
    val testResult: String? = null,
    val isTesting: Boolean = false,
    val isSaved: Boolean = false,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class PairingWizardViewModel @Inject constructor(
    private val printerManager: PrinterManager,
    private val weightScaleService: WeightScaleService,
) : ViewModel() {

    private val _state = MutableStateFlow(PairingWizardUiState())
    val state = _state.asStateFlow()

    fun selectType(type: HardwareDeviceType) {
        _state.update { it.copy(selectedType = type, step = WizardStep.EnableBluetooth) }
    }

    fun onBluetoothConfirmed() {
        _state.update { it.copy(step = WizardStep.Discover, isDiscovering = true) }
        viewModelScope.launch {
            val devices = printerManager.discoverBluetoothPrinters()
            _state.update { it.copy(discoveredDevices = devices, isDiscovering = false) }
        }
    }

    fun selectDevice(device: BluetoothDevice) {
        _state.update { it.copy(selectedDevice = device, step = WizardStep.RoleAssign) }
    }

    fun setPrinterRole(role: PrinterManager.PrinterRole) {
        _state.update { it.copy(selectedPrinterRole = role) }
    }

    fun setScaleUnit(unit: WeightUnit) {
        _state.update { it.copy(selectedScaleUnit = unit) }
    }

    @SuppressLint("MissingPermission")
    fun testDevice() {
        val device = _state.value.selectedDevice ?: return
        _state.update { it.copy(isTesting = true, testResult = null) }
        viewModelScope.launch {
            when (_state.value.selectedType) {
                HardwareDeviceType.Printer -> {
                    val role = _state.value.selectedPrinterRole
                    printerManager.pair(device, role)
                    val result = printerManager.testPrint(role)
                    _state.update {
                        it.copy(
                            isTesting = false,
                            testResult = if (result.isSuccess) "Test print sent to ${device.name ?: device.address}"
                            else "Print failed: ${result.exceptionOrNull()?.message}",
                        )
                    }
                }
                HardwareDeviceType.Scale -> {
                    val name = runCatching { device.name }.getOrNull() ?: device.address
                    weightScaleService.savePairing(device.address, name, _state.value.selectedScaleUnit)
                    val result = weightScaleService.readWeight()
                    _state.update {
                        it.copy(
                            isTesting = false,
                            testResult = result.fold(
                                onSuccess = { reading -> "Scale read: ${reading.label()}" },
                                onFailure = { err -> "Scale error: ${err.message}" },
                            ),
                        )
                    }
                }
                HardwareDeviceType.Terminal, HardwareDeviceType.Scanner -> {
                    // Terminal pairing done via HardwareSettingsScreen (IP-based)
                    // Scanner is HID — no pairing needed
                    _state.update {
                        it.copy(
                            isTesting = false,
                            testResult = "For ${_state.value.selectedType?.label}, pair via the dedicated settings card.",
                        )
                    }
                }
                null -> _state.update { it.copy(isTesting = false) }
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun save() {
        val device = _state.value.selectedDevice ?: return
        when (_state.value.selectedType) {
            HardwareDeviceType.Printer -> printerManager.pair(device, _state.value.selectedPrinterRole)
            HardwareDeviceType.Scale -> {
                val name = runCatching { device.name }.getOrNull() ?: device.address
                weightScaleService.savePairing(device.address, name, _state.value.selectedScaleUnit)
            }
            else -> { /* no-op — handled by dedicated screens */ }
        }
        _state.update { it.copy(step = WizardStep.Confirm, isSaved = true) }
    }

    fun back() {
        _state.update {
            it.copy(
                step = when (it.step) {
                    WizardStep.EnableBluetooth -> WizardStep.SelectType
                    WizardStep.Discover -> WizardStep.EnableBluetooth
                    WizardStep.RoleAssign -> WizardStep.Discover
                    WizardStep.Confirm -> WizardStep.RoleAssign
                    else -> WizardStep.SelectType
                },
                testResult = null,
            )
        }
    }

    fun reset() {
        _state.value = PairingWizardUiState()
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@SuppressLint("MissingPermission")
@Composable
fun HardwarePairingWizardScreen(
    onFinish: () -> Unit,
    viewModel: PairingWizardViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Add Device",
                navigationIcon = {
                    IconButton(
                        onClick = {
                            if (state.step == WizardStep.SelectType || state.isSaved) onFinish()
                            else viewModel.back()
                        },
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
    ) { padding ->
        AnimatedContent(
            targetState = state.step,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "wizard_step",
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
        ) { step ->
            when (step) {
                WizardStep.SelectType -> StepSelectType(onSelect = viewModel::selectType)
                WizardStep.EnableBluetooth -> StepEnableBluetooth(onConfirm = viewModel::onBluetoothConfirmed)
                WizardStep.Discover -> StepDiscover(
                    state = state,
                    onSelect = viewModel::selectDevice,
                )
                WizardStep.RoleAssign -> StepRoleAssign(
                    state = state,
                    onSetRole = viewModel::setPrinterRole,
                    onSetUnit = viewModel::setScaleUnit,
                    onTest = viewModel::testDevice,
                    onSave = viewModel::save,
                )
                WizardStep.Confirm -> StepConfirm(
                    state = state,
                    onAddAnother = { viewModel.reset() },
                    onDone = onFinish,
                )
            }
        }
    }
}

// ── Step composables ──────────────────────────────────────────────────────────

@Composable
private fun StepSelectType(onSelect: (HardwareDeviceType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("What type of device are you adding?", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        HardwareDeviceType.entries.forEach { type ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Add ${type.label}" },
                onClick = { onSelect(type) },
            ) {
                ListItem(
                    headlineContent = { Text(type.label) },
                    leadingContent = { Icon(type.icon, contentDescription = null) },
                    trailingContent = {
                        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null)
                    },
                )
            }
        }
    }
}

@Composable
private fun StepEnableBluetooth(onConfirm: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Default.Bluetooth,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Text("Enable Bluetooth", style = MaterialTheme.typography.titleMedium)
        Text(
            "Make sure Bluetooth is enabled on this device and the hardware device is powered on and in pairing mode.",
            style = MaterialTheme.typography.bodyMedium,
        )
        Button(
            onClick = onConfirm,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Bluetooth is on — start discovery" },
        ) {
            Text("Bluetooth is on — Discover devices")
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun StepDiscover(
    state: PairingWizardUiState,
    onSelect: (BluetoothDevice) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (state.isDiscovering) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                Text("Scanning for bonded devices…")
            }
        } else if (state.discoveredDevices.isEmpty()) {
            Text(
                "No Bluetooth devices found. Pair the device in Android Settings first, then return here.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Text("Select your device:", style = MaterialTheme.typography.titleSmall)
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(state.discoveredDevices, key = { it.address }) { device ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { contentDescription = "Select ${device.name ?: device.address}" },
                        onClick = { onSelect(device) },
                    ) {
                        ListItem(
                            headlineContent = { Text(device.name ?: "Unknown device") },
                            supportingContent = { Text(device.address) },
                            leadingContent = {
                                Icon(Icons.Default.BluetoothConnected, contentDescription = null)
                            },
                        )
                    }
                }
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun StepRoleAssign(
    state: PairingWizardUiState,
    onSetRole: (PrinterManager.PrinterRole) -> Unit,
    onSetUnit: (WeightUnit) -> Unit,
    onTest: () -> Unit,
    onSave: () -> Unit,
) {
    val device = state.selectedDevice ?: return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            device.name ?: device.address,
            style = MaterialTheme.typography.titleMedium,
        )

        when (state.selectedType) {
            HardwareDeviceType.Printer -> {
                Text("Assign a role to this printer:", style = MaterialTheme.typography.labelMedium)
                PrinterManager.PrinterRole.entries.forEach { role ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { contentDescription = "Assign ${role.label} role" },
                    ) {
                        RadioButton(
                            selected = state.selectedPrinterRole == role,
                            onClick = { onSetRole(role) },
                        )
                        Text(role.label)
                    }
                }
            }
            HardwareDeviceType.Scale -> {
                Text("Preferred weight unit:", style = MaterialTheme.typography.labelMedium)
                WeightUnit.entries.forEach { unit ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { contentDescription = "Use ${unit.name} unit" },
                    ) {
                        RadioButton(
                            selected = state.selectedScaleUnit == unit,
                            onClick = { onSetUnit(unit) },
                        )
                        Text(unit.name)
                    }
                }
            }
            else -> {
                Text(
                    "No additional configuration needed for ${state.selectedType?.label}.",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }

        // Test button
        if (state.isTesting) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
        state.testResult?.let { msg ->
            Text(msg, style = MaterialTheme.typography.bodySmall,
                color = if (msg.contains("error", ignoreCase = true) || msg.contains("fail", ignoreCase = true))
                    MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.primary)
        }
        OutlinedButton(
            onClick = onTest,
            enabled = !state.isTesting,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Test device" },
        ) {
            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(4.dp))
            Text("Test device")
        }

        Button(
            onClick = onSave,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Save pairing" },
        ) {
            Icon(Icons.Default.Save, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(4.dp))
            Text("Save")
        }
    }
}

@Composable
private fun StepConfirm(
    state: PairingWizardUiState,
    onAddAnother: () -> Unit,
    onDone: () -> Unit,
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Default.CheckCircle,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            "${state.selectedType?.label} paired successfully",
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            "This device is now available across POS and Ticket screens for this location.",
            style = MaterialTheme.typography.bodyMedium,
        )
        Button(
            onClick = onDone,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Done — close wizard" },
        ) { Text("Done") }
        OutlinedButton(
            onClick = onAddAnother,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Add another device" },
        ) { Text("Add another device") }
    }
}
