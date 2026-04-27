package com.bizarreelectronics.crm.ui.screens.settings.hardware

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import timber.log.Timber

// §17.5 L1890-L1898 — Hardware Settings screen.
//
// Settings → Hardware contains:
//   1. Printer sub-screen entry (routes to PrinterDiscoveryScreen)
//   2. BlockChyp terminal pairing:
//      - LAN IP manual entry
//      - mDNS discovery stub (NsdManager) — untouched (lines 199-264 equivalent)
//      - Actions: charge / void / capture / adjust — wired to BlockChypClient via ViewModel
//      - Firmware update banner when firmware is below minimum version

private const val MINIMUM_FIRMWARE_VERSION = "1.0.0"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HardwareSettingsScreen(
    onBack: () -> Unit,
    onNavigateToPrinters: () -> Unit,
    onNavigateToPairingWizard: () -> Unit = {},
    viewModel: HardwareSettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Hardware",
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Printers section
            item {
                Text(
                    "PRINTERS",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = onNavigateToPrinters,
                ) {
                    ListItem(
                        headlineContent = { Text("Printer Setup") },
                        supportingContent = { Text("Pair receipt, label, and invoice printers") },
                        leadingContent = {
                            Icon(Icons.Default.Print, contentDescription = null)
                        },
                        trailingContent = {
                            Icon(Icons.Default.ChevronRight, contentDescription = null)
                        },
                    )
                }
            }

            // ── §17.11 Pairing wizard entry point ────────────────────────────
            item {
                Spacer(Modifier.height(8.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = onNavigateToPairingWizard,
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                    ),
                ) {
                    ListItem(
                        headlineContent = { Text("Add Device") },
                        supportingContent = { Text("Printer, scale, scanner, or terminal") },
                        leadingContent = {
                            Icon(Icons.Default.AddCircle, contentDescription = null)
                        },
                        trailingContent = {
                            Icon(Icons.Default.ChevronRight, contentDescription = null)
                        },
                    )
                }
            }

            // BlockChyp terminal section
            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    "PAYMENT TERMINAL (BLOCKCHYP)",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                BlockChypTerminalCard(
                    uiState = uiState,
                    onPair = viewModel::savePairing,
                    onClearPairing = viewModel::clearPairing,
                    onTestConnection = viewModel::testConnection,
                    onCharge = viewModel::testCharge,
                    onVoid = viewModel::voidLast,
                    onCapture = viewModel::captureSignature,
                    onAdjustTip = viewModel::adjustTip,
                    onCheckFirmware = viewModel::checkFirmware,
                    onDismissFirmwareBanner = viewModel::dismissFirmwareBanner,
                    onClearFeedback = viewModel::clearFeedback,
                )
            }

            // ── §17.6 Tap-to-Pay evaluation notice ────────────────────────────
            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    "TAP TO PAY (EVALUATION)",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                    ),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(Icons.Default.Nfc, contentDescription = null)
                            Text("Tap to Pay on Android", style = MaterialTheme.typography.titleSmall)
                            Spacer(Modifier.weight(1f))
                            Surface(
                                shape = MaterialTheme.shapes.small,
                                color = MaterialTheme.colorScheme.secondaryContainer,
                            ) {
                                Text(
                                    "Evaluating",
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                )
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Android phones with NFC HCE can accept contactless payments without an " +
                                "external terminal via BlockChyp's Tap to Pay on Android program. " +
                                "Evaluation pending BlockChyp SDK support. For now, use the BlockChyp " +
                                "terminal above.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// ─── Card composable ──────────────────────────────────────────────────────────

@Composable
private fun BlockChypTerminalCard(
    uiState: HardwareSettingsUiState,
    onPair: (String) -> Unit,
    onClearPairing: () -> Unit,
    onTestConnection: () -> Unit,
    onCharge: () -> Unit,
    onVoid: () -> Unit,
    onCapture: () -> Unit,
    onAdjustTip: () -> Unit,
    onCheckFirmware: () -> Unit,
    onDismissFirmwareBanner: () -> Unit,
    onClearFeedback: () -> Unit,
) {
    val context = LocalContext.current
    var lanIp by rememberSaveable { mutableStateOf(uiState.pairedIp ?: "") }
    var isDiscovering by rememberSaveable { mutableStateOf(false) }
    var discoveredTerminals by remember { mutableStateOf<List<String>>(emptyList()) }

    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.feedback) {
        val msg = uiState.feedback
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            onClearFeedback()
        }
    }

    // ── mDNS discovery (lines 199-264 equivalent — untouched logic) ─────────
    fun startMdnsDiscovery() {
        isDiscovering = true
        discoveredTerminals = emptyList()
        val nsdManager = context.getSystemService(NsdManager::class.java)
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {
                Timber.d("HardwareSettings: mDNS discovery started for $type")
            }
            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                discoveredTerminals = discoveredTerminals + serviceInfo.serviceName
            }
            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
            override fun onDiscoveryStopped(type: String) { isDiscovering = false }
            override fun onStartDiscoveryFailed(type: String, err: Int) { isDiscovering = false }
            override fun onStopDiscoveryFailed(type: String, err: Int) {}
        }
        runCatching {
            nsdManager?.discoverServices("_blockchyp._tcp", NsdManager.PROTOCOL_DNS_SD, listener)
        }.onFailure { e ->
            Timber.w(e, "HardwareSettings: mDNS discovery failed")
            isDiscovering = false
        }
    }
    // ── end mDNS block ───────────────────────────────────────────────────────

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Default.CreditCard, contentDescription = null)
                Text("BlockChyp Terminal", style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.weight(1f))
                if (uiState.isPaired) {
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                    ) {
                        Text(
                            "Paired",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        )
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            // Firmware update banner — shown when firmware is below minimum
            if (uiState.firmwareUpdateAvailable) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.SystemUpdate, contentDescription = null)
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Update terminal firmware",
                                style = MaterialTheme.typography.labelMedium,
                            )
                            val current = uiState.firmwareVersion ?: "unknown"
                            Text(
                                "Current: $current — minimum required: $MINIMUM_FIRMWARE_VERSION",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        TextButton(
                            onClick = onDismissFirmwareBanner,
                            modifier = Modifier.semantics { contentDescription = "Dismiss firmware update warning" },
                        ) { Text("Dismiss") }
                    }
                }
                Spacer(Modifier.height(12.dp))
            }

            // LAN IP entry
            OutlinedTextField(
                value = lanIp,
                onValueChange = { lanIp = it },
                label = { Text("Terminal LAN IP") },
                placeholder = { Text("192.168.1.100") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Done,
                ),
                modifier = Modifier.fillMaxWidth(),
                leadingIcon = { Icon(Icons.Default.Wifi, contentDescription = null) },
                trailingIcon = {
                    if (lanIp.isNotBlank()) {
                        IconButton(
                            onClick = { lanIp = "" },
                            modifier = Modifier.semantics { contentDescription = "Clear IP address" },
                        ) {
                            Icon(Icons.Default.Clear, contentDescription = null)
                        }
                    }
                },
            )

            Spacer(Modifier.height(8.dp))

            // mDNS discover + Pair buttons
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { startMdnsDiscovery() },
                    enabled = !isDiscovering,
                    modifier = Modifier.semantics { contentDescription = "Discover terminals on network" },
                ) {
                    if (isDiscovering) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(16.dp))
                    }
                    Spacer(Modifier.width(4.dp))
                    Text("Discover")
                }

                Button(
                    onClick = { if (lanIp.isNotBlank()) onPair(lanIp) },
                    enabled = lanIp.isNotBlank(),
                    modifier = Modifier.semantics { contentDescription = "Pair terminal at entered IP" },
                ) {
                    Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Pair")
                }

                if (uiState.isPaired) {
                    OutlinedButton(
                        onClick = onClearPairing,
                        modifier = Modifier.semantics { contentDescription = "Unpair terminal" },
                    ) {
                        Text("Unpair")
                    }
                }
            }

            // Discovered terminals from mDNS
            if (discoveredTerminals.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text("Discovered:", style = MaterialTheme.typography.labelSmall)
                discoveredTerminals.forEach { name ->
                    TextButton(
                        onClick = { lanIp = name },
                        modifier = Modifier.semantics { contentDescription = "Select terminal $name" },
                    ) {
                        Icon(Icons.Default.Terminal, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(name)
                    }
                }
            }

            // Terminal actions — wired to BlockChypClient (lines 266-324 replacement)
            if (uiState.isPaired) {
                Spacer(Modifier.height(12.dp))
                HorizontalDivider()
                Spacer(Modifier.height(12.dp))
                Text(
                    "TERMINAL ACTIONS",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(8.dp))

                if (uiState.isLoading) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    OutlinedButton(
                        onClick = onTestConnection,
                        enabled = !uiState.isLoading,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Test connection to terminal" },
                    ) {
                        Text("Test", style = MaterialTheme.typography.labelSmall)
                    }
                    OutlinedButton(
                        onClick = onCharge,
                        enabled = !uiState.isLoading,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Process a test charge on the terminal" },
                    ) {
                        Text("Charge", style = MaterialTheme.typography.labelSmall)
                    }
                    OutlinedButton(
                        onClick = onVoid,
                        enabled = !uiState.isLoading && uiState.lastTransactionId != null,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Void the last transaction" },
                    ) {
                        Text("Void", style = MaterialTheme.typography.labelSmall)
                    }
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    OutlinedButton(
                        onClick = onCapture,
                        enabled = !uiState.isLoading,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Capture signature on terminal" },
                    ) {
                        Text("Capture", style = MaterialTheme.typography.labelSmall)
                    }
                    OutlinedButton(
                        onClick = onAdjustTip,
                        enabled = !uiState.isLoading && uiState.lastTransactionId != null,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Adjust tip on last transaction" },
                    ) {
                        Text("Adjust", style = MaterialTheme.typography.labelSmall)
                    }
                    OutlinedButton(
                        onClick = onCheckFirmware,
                        enabled = !uiState.isLoading,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Check terminal firmware version" },
                    ) {
                        Text("Check FW", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}
