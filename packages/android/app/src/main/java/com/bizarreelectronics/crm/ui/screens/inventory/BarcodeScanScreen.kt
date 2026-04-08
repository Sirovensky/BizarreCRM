package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// TODO: Integrate CameraX + ML Kit Barcode Scanning
// Dependencies needed in build.gradle:
//   implementation("androidx.camera:camera-camera2:1.3.x")
//   implementation("androidx.camera:camera-lifecycle:1.3.x")
//   implementation("androidx.camera:camera-view:1.3.x")
//   implementation("com.google.mlkit:barcode-scanning:17.x.x")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BarcodeScanScreen(
    onScanned: (String) -> Unit,
    onBack: () -> Unit,
) {
    var manualEntry by remember { mutableStateOf("") }
    var showManualEntry by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Scan Barcode") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showManualEntry = !showManualEntry }) {
                        Icon(Icons.Default.Keyboard, contentDescription = "Manual Entry")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (showManualEntry) {
                // Manual barcode entry
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OutlinedTextField(
                        value = manualEntry,
                        onValueChange = { manualEntry = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Barcode / SKU") },
                        singleLine = true,
                    )
                    Button(
                        onClick = {
                            if (manualEntry.isNotBlank()) {
                                onScanned(manualEntry)
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = manualEntry.isNotBlank(),
                    ) {
                        Text("Look Up")
                    }
                }
            } else {
                // Camera preview placeholder
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.QrCodeScanner,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = Color.White,
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            "Camera preview will appear here\n(CameraX + ML Kit integration pending)",
                            color = Color.White,
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }

                Text(
                    "Point camera at barcode to scan",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
