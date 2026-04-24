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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import timber.log.Timber

// §17.5 L1890-L1898 — Hardware Settings screen.
//
// Settings → Hardware contains:
//   1. Printer sub-screen entry (routes to PrinterDiscoveryScreen)
//   2. BlockChyp terminal pairing:
//      - LAN IP manual entry
//      - mDNS discovery stub (NsdManager)
//      - Actions: charge / refund / void / capture / adjust (stubbed — SDK dep absent)
//      - Firmware update banner when firmware info is available

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HardwareSettingsScreen(
    onBack: () -> Unit,
    onNavigateToPrinters: () -> Unit,
) {
    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Hardware",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                Text("PRINTERS", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
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

            // BlockChyp terminal section
            item {
                Spacer(Modifier.height(8.dp))
                Text("PAYMENT TERMINAL (BLOCKCHYP)", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item {
                BlockChypTerminalCard()
            }
        }
    }
}

/**
 * §17.5 L1895-L1898 — BlockChyp terminal pairing card.
 *
 * Supports:
 * - Manual LAN IP entry for local pairing
 * - mDNS discovery stub via [NsdManager] (service type "_blockchyp._tcp")
 * - Action buttons: Charge / Refund / Void / Capture / Adjust (all stubbed —
 *   BlockChyp SDK dep is not yet available; calls are no-ops with a toast).
 * - Firmware update banner surfaced when a newer firmware version is detected.
 */
@Composable
private fun BlockChypTerminalCard() {
    val context = LocalContext.current
    var lanIp by rememberSaveable { mutableStateOf("") }
    var isPaired by rememberSaveable { mutableStateOf(false) }
    var isDiscovering by rememberSaveable { mutableStateOf(false) }
    var discoveredTerminals by remember { mutableStateOf<List<String>>(emptyList()) }
    var firmwareUpdateAvailable by remember { mutableStateOf(false) } // stub
    var actionFeedback by remember { mutableStateOf<String?>(null) }

    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(actionFeedback) {
        val msg = actionFeedback
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            actionFeedback = null
        }
    }

    // mDNS discovery stub
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

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Default.CreditCard, contentDescription = null)
                Text("BlockChyp Terminal", style = MaterialTheme.typography.titleSmall)
                Spacer(Modifier.weight(1f))
                if (isPaired) {
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

            // Firmware update banner (stub — shown when firmwareUpdateAvailable = true)
            if (firmwareUpdateAvailable) {
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
                            Text("Firmware update available", style = MaterialTheme.typography.labelMedium)
                            Text("Update from terminal settings", style = MaterialTheme.typography.bodySmall)
                        }
                        TextButton(onClick = { firmwareUpdateAvailable = false }) { Text("Dismiss") }
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
                        IconButton(onClick = { lanIp = "" }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear")
                        }
                    }
                },
            )

            Spacer(Modifier.height(8.dp))

            // mDNS discover button
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = { startMdnsDiscovery() },
                    enabled = !isDiscovering,
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
                    onClick = {
                        if (lanIp.isNotBlank()) {
                            isPaired = true
                            actionFeedback = "Terminal paired at $lanIp"
                        }
                    },
                    enabled = lanIp.isNotBlank(),
                ) {
                    Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Pair")
                }
            }

            // Discovered terminals
            if (discoveredTerminals.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text("Discovered:", style = MaterialTheme.typography.labelSmall)
                discoveredTerminals.forEach { name ->
                    TextButton(onClick = { lanIp = name }) {
                        Icon(Icons.Default.Terminal, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(name)
                    }
                }
            }

            // Terminal actions (stub — BlockChyp SDK not yet available)
            if (isPaired) {
                Spacer(Modifier.height(12.dp))
                HorizontalDivider()
                Spacer(Modifier.height(12.dp))
                Text("TERMINAL ACTIONS", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))

                // Stub action notice
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        "BlockChyp SDK integration is stubbed — charge, refund, void, capture, " +
                            "and adjust actions are pending SDK dependency.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(12.dp),
                    )
                }

                Spacer(Modifier.height(8.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    listOf("Charge", "Refund", "Void").forEach { action ->
                        OutlinedButton(
                            onClick = { actionFeedback = "$action: BlockChyp SDK stub — not yet implemented" },
                            modifier = Modifier.weight(1f),
                        ) {
                            Text(action, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    listOf("Capture", "Adjust").forEach { action ->
                        OutlinedButton(
                            onClick = { actionFeedback = "$action: BlockChyp SDK stub — not yet implemented" },
                            modifier = Modifier.weight(1f),
                        ) {
                            Text(action, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                    // Firmware update check stub
                    OutlinedButton(
                        onClick = { firmwareUpdateAvailable = true },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("Check FW", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}
