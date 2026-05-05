package com.bizarreelectronics.crm.ui.screens.hardware

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.provider.Settings
import androidx.compose.animation.AnimatedContent
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.PrinterManager
import com.bizarreelectronics.crm.util.WeightScaleManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// §17.11 — Hardware Pairing Wizard.
//
// Settings → Hardware → Add Device — five-step walkthrough:
//   Step 1: Enable Bluetooth (checks + deep link to system BT settings)
//   Step 2: Discover bonded BT devices
//   Step 3: Select device from list
//   Step 4: Role-assign (Receipt printer / Label printer / Weight scale)
//   Step 5: Test (test print / read weight) + Save
//
// Per-location note: pairing is persisted per device role in shared prefs, so
// the same physical device is reachable from both POS and Ticket screens.

enum class WizardStep(val label: String, val stepNumber: Int) {
    Bluetooth("Enable Bluetooth", 1),
    Discover("Discover devices", 2),
    Select("Select device", 3),
    Role("Assign role", 4),
    Test("Test & save", 5),
}

enum class HardwareRole(val label: String, val description: String) {
    ReceiptPrinter("Receipt printer", "Prints customer receipts and tickets"),
    LabelPrinter("Label printer", "Prints ZPL / CPCL device labels"),
    InvoicePrinter("Invoice printer", "Full-page invoice + waiver printing"),
    WeightScale("Weight scale", "Reads item / package weight on demand"),
}

data class WizardUiState(
    val step: WizardStep = WizardStep.Bluetooth,
    val bluetoothEnabled: Boolean = false,
    val discoveredDevices: List<BluetoothDevice> = emptyList(),
    val selectedDevice: BluetoothDevice? = null,
    val selectedRole: HardwareRole? = null,
    val testResult: String? = null,
    val isTesting: Boolean = false,
    val isSaved: Boolean = false,
    val feedback: String? = null,
)

@HiltViewModel
class HardwarePairingWizardViewModel @Inject constructor(
    private val printerManager: PrinterManager,
    private val weightScaleManager: WeightScaleManager,
) : ViewModel() {

    private val _state = MutableStateFlow(WizardUiState())
    val state: StateFlow<WizardUiState> = _state.asStateFlow()

    fun checkBluetooth(adapter: BluetoothAdapter?) {
        val enabled = adapter?.isEnabled == true
        _state.update { it.copy(bluetoothEnabled = enabled) }
    }

    fun onBluetoothReady() {
        _state.update { it.copy(step = WizardStep.Discover, bluetoothEnabled = true) }
    }

    @SuppressLint("MissingPermission")
    fun discoverDevices(adapter: BluetoothAdapter?) {
        if (adapter == null || !adapter.isEnabled) {
            _state.update { it.copy(feedback = "Bluetooth not available") }
            return
        }
        val bonded = adapter.bondedDevices.toList()
        _state.update { it.copy(discoveredDevices = bonded) }
        if (bonded.isEmpty()) {
            _state.update { it.copy(feedback = "No bonded devices found — pair in Android Settings first") }
        }
    }

    fun selectDevice(device: BluetoothDevice) {
        _state.update { it.copy(selectedDevice = device, step = WizardStep.Role) }
    }

    fun advanceToSelect() {
        _state.update { it.copy(step = WizardStep.Select) }
    }

    fun selectRole(role: HardwareRole) {
        _state.update { it.copy(selectedRole = role, step = WizardStep.Test) }
    }

    fun testDevice() {
        val device = _state.value.selectedDevice ?: return
        val role = _state.value.selectedRole ?: return
        viewModelScope.launch {
            _state.update { it.copy(isTesting = true, testResult = null) }
            val result = when (role) {
                HardwareRole.ReceiptPrinter ->
                    printerManager.testPrint(PrinterManager.PrinterRole.Receipt)
                HardwareRole.LabelPrinter ->
                    printerManager.testPrint(PrinterManager.PrinterRole.Label)
                HardwareRole.InvoicePrinter ->
                    printerManager.testPrint(PrinterManager.PrinterRole.Invoice)
                HardwareRole.WeightScale ->
                    weightScaleManager.requestWeight().let { reading ->
                        if (reading is com.bizarreelectronics.crm.util.ScaleReading.Weight)
                            Result.success(Unit)
                        else
                            Result.failure(Exception((reading as com.bizarreelectronics.crm.util.ScaleReading.Error).reason))
                    }
            }
            _state.update {
                it.copy(
                    isTesting = false,
                    testResult = if (result.isSuccess) "Test passed" else "Test failed: ${result.exceptionOrNull()?.message}",
                )
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun saveAndFinish() {
        val device = _state.value.selectedDevice ?: return
        val role = _state.value.selectedRole ?: return
        val name = runCatching { device.name }.getOrNull() ?: device.address
        when (role) {
            HardwareRole.ReceiptPrinter ->
                printerManager.pair(device, PrinterManager.PrinterRole.Receipt)
            HardwareRole.LabelPrinter ->
                printerManager.pair(device, PrinterManager.PrinterRole.Label)
            HardwareRole.InvoicePrinter ->
                printerManager.pair(device, PrinterManager.PrinterRole.Invoice)
            HardwareRole.WeightScale ->
                weightScaleManager.pairScale(device.address, name)
        }
        _state.update {
            it.copy(
                isSaved = true,
                feedback = "$name saved as ${role.label}",
            )
        }
    }

    fun back() {
        val prev = when (_state.value.step) {
            WizardStep.Bluetooth -> null
            WizardStep.Discover -> WizardStep.Bluetooth
            WizardStep.Select -> WizardStep.Discover
            WizardStep.Role -> WizardStep.Select
            WizardStep.Test -> WizardStep.Role
        }
        if (prev != null) _state.update { it.copy(step = prev) }
    }

    fun clearFeedback() {
        _state.update { it.copy(feedback = null) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HardwarePairingWizardScreen(
    onBack: () -> Unit,
    onFinished: () -> Unit,
    viewModel: HardwarePairingWizardViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    val btManager = remember {
        context.getSystemService(BluetoothManager::class.java)
    }
    val btAdapter = remember { btManager?.adapter }

    LaunchedEffect(Unit) {
        viewModel.checkBluetooth(btAdapter)
    }

    LaunchedEffect(state.isSaved) {
        if (state.isSaved) onFinished()
    }

    LaunchedEffect(state.feedback) {
        val msg = state.feedback ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearFeedback()
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Add Device",
                navigationIcon = {
                    IconButton(
                        onClick = {
                            if (state.step == WizardStep.Bluetooth) onBack()
                            else viewModel.back()
                        },
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Step indicator
            WizardStepIndicator(currentStep = state.step)

            AnimatedContent(
                targetState = state.step,
                label = "wizard_step",
            ) { step ->
                when (step) {
                    WizardStep.Bluetooth -> BluetoothStep(
                        enabled = state.bluetoothEnabled,
                        onOpenSettings = {
                            context.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        },
                        onContinue = {
                            viewModel.checkBluetooth(btAdapter)
                            if (btAdapter?.isEnabled == true) viewModel.onBluetoothReady()
                        },
                    )
                    WizardStep.Discover -> DiscoverStep(
                        onScan = {
                            viewModel.discoverDevices(btAdapter)
                            viewModel.advanceToSelect()
                        },
                    )
                    WizardStep.Select -> SelectStep(
                        devices = state.discoveredDevices,
                        onSelect = viewModel::selectDevice,
                    )
                    WizardStep.Role -> RoleStep(
                        onSelect = viewModel::selectRole,
                    )
                    WizardStep.Test -> TestStep(
                        selectedDevice = state.selectedDevice,
                        selectedRole = state.selectedRole,
                        testResult = state.testResult,
                        isTesting = state.isTesting,
                        onTest = { viewModel.testDevice() },
                        onSave = { viewModel.saveAndFinish() },
                    )
                }
            }
        }
    }
}

@Composable
private fun WizardStepIndicator(currentStep: WizardStep) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        WizardStep.entries.forEachIndexed { index, step ->
            val active = step == currentStep
            val done = step.stepNumber < currentStep.stepNumber
            val color = when {
                done -> MaterialTheme.colorScheme.primary
                active -> MaterialTheme.colorScheme.primary
                else -> MaterialTheme.colorScheme.outlineVariant
            }
            Surface(
                shape = MaterialTheme.shapes.small,
                color = if (active || done) color.copy(alpha = 0.15f) else color.copy(alpha = 0.06f),
                modifier = Modifier
                    .weight(1f)
                    .height(4.dp),
            ) {}
            if (index < WizardStep.entries.size - 1) {
                Spacer(Modifier.width(4.dp))
            }
        }
    }
    Text(
        "Step ${currentStep.stepNumber} of ${WizardStep.entries.size}: ${currentStep.label}",
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun BluetoothStep(
    enabled: Boolean,
    onOpenSettings: () -> Unit,
    onContinue: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(
            if (enabled) Icons.Default.Bluetooth else Icons.Default.BluetoothDisabled,
            contentDescription = if (enabled) "Bluetooth enabled" else "Bluetooth disabled",
            modifier = Modifier
                .size(56.dp)
                .align(Alignment.CenterHorizontally),
            tint = if (enabled) MaterialTheme.colorScheme.primary
                   else MaterialTheme.colorScheme.error,
        )
        Text(
            if (enabled) "Bluetooth is on" else "Bluetooth is off",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
        Text(
            "Hardware peripherals (printers, scales, card readers) connect via Bluetooth.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (!enabled) {
            FilledTonalButton(
                onClick = onOpenSettings,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Open Bluetooth settings" },
            ) {
                Icon(Icons.Default.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Open Bluetooth Settings")
            }
        }
        Button(
            onClick = onContinue,
            enabled = enabled,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Continue to device discovery" },
        ) {
            Text("Continue")
        }
    }
}

@Composable
private fun DiscoverStep(onScan: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Default.Search,
            contentDescription = "Scanning for devices",
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            "Scan for devices",
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            "Make sure your device is powered on and discoverable. " +
                "If not listed, pair it in Android Settings → Bluetooth first.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = onScan,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Scan for Bluetooth devices" },
        ) {
            Icon(Icons.Default.BluetoothSearching, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Scan for Devices")
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun SelectStep(
    devices: List<BluetoothDevice>,
    onSelect: (BluetoothDevice) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Select your device", style = MaterialTheme.typography.titleMedium)
        if (devices.isEmpty()) {
            Text(
                "No devices found. Go back and scan again, or pair the device in Android Settings.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(devices, key = { it.address }) { device ->
                    OutlinedCard(
                        modifier = Modifier.fillMaxWidth(),
                        onClick = { onSelect(device) },
                    ) {
                        ListItem(
                            headlineContent = { Text(device.name ?: "Unknown device") },
                            supportingContent = { Text(device.address) },
                            leadingContent = {
                                Icon(Icons.Default.BluetoothConnected, contentDescription = "Bluetooth device")
                            },
                            trailingContent = {
                                Icon(Icons.Default.ChevronRight, contentDescription = null)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RoleStep(onSelect: (HardwareRole) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("What is this device?", style = MaterialTheme.typography.titleMedium)
        Text(
            "Select the role for this device. The same device can be used across POS and Ticket screens.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        HardwareRole.entries.forEach { role ->
            OutlinedCard(
                modifier = Modifier.fillMaxWidth(),
                onClick = { onSelect(role) },
            ) {
                ListItem(
                    headlineContent = { Text(role.label) },
                    supportingContent = { Text(role.description) },
                    leadingContent = {
                        Icon(
                            when (role) {
                                HardwareRole.ReceiptPrinter, HardwareRole.InvoicePrinter -> Icons.Default.Print
                                HardwareRole.LabelPrinter -> Icons.Default.Label
                                HardwareRole.WeightScale -> Icons.Default.Scale
                            },
                            contentDescription = "${role.label} icon",
                        )
                    },
                    trailingContent = {
                        Icon(Icons.Default.ChevronRight, contentDescription = null)
                    },
                )
            }
        }
    }
}

@SuppressLint("MissingPermission")
@Composable
private fun TestStep(
    selectedDevice: BluetoothDevice?,
    selectedRole: HardwareRole?,
    testResult: String?,
    isTesting: Boolean,
    onTest: () -> Unit,
    onSave: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Test & save", style = MaterialTheme.typography.titleMedium)

        if (selectedDevice != null && selectedRole != null) {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = {
                        Text(runCatching { selectedDevice.name }.getOrNull() ?: selectedDevice.address)
                    },
                    supportingContent = { Text("Role: ${selectedRole.label}") },
                    leadingContent = {
                        Icon(Icons.Default.CheckCircle, contentDescription = "Selected device")
                    },
                )
            }
        }

        if (testResult != null) {
            val isPass = testResult.startsWith("Test passed")
            OutlinedCard(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.outlinedCardColors(
                    containerColor = if (isPass)
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                    else
                        MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f),
                ),
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (isPass) Icons.Default.CheckCircle else Icons.Default.Error,
                        contentDescription = if (isPass) "Test passed" else "Test failed",
                        tint = if (isPass) MaterialTheme.colorScheme.primary
                               else MaterialTheme.colorScheme.error,
                    )
                    Text(
                        testResult,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }

        if (isTesting) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = onTest,
                enabled = !isTesting,
                modifier = Modifier
                    .weight(1f)
                    .semantics { contentDescription = "Send test command to device" },
            ) {
                Text("Test device")
            }
            Button(
                onClick = onSave,
                modifier = Modifier
                    .weight(1f)
                    .semantics { contentDescription = "Save device pairing" },
            ) {
                Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("Save")
            }
        }
    }
}
