package com.bizarreelectronics.crm.ui.screens.scanner

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
//   implementation("androidx.camera:camera-camera2:1.4.x")
//   implementation("androidx.camera:camera-lifecycle:1.4.x")
//   implementation("androidx.camera:camera-view:1.4.x")
//   implementation("com.google.mlkit:barcode-scanning:17.x.x")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScannerScreen(
    onScanned: (String) -> Unit,
) {
    var manualEntry by remember { mutableStateOf("") }
    var showManualEntry by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Scan Barcode") },
                actions = {
                    IconButton(onClick = { showManualEntry = !showManualEntry }) {
                        Icon(
                            if (showManualEntry) Icons.Default.CameraAlt else Icons.Default.Keyboard,
                            contentDescription = if (showManualEntry) "Camera" else "Manual Entry",
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (showManualEntry) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OutlinedTextField(
                        value = manualEntry,
                        onValueChange = { manualEntry = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Barcode / SKU / IMEI") },
                        singleLine = true,
                        trailingIcon = {
                            if (manualEntry.isNotEmpty()) {
                                IconButton(onClick = { manualEntry = "" }) {
                                    Icon(Icons.Default.Clear, contentDescription = "Clear")
                                }
                            }
                        },
                    )
                    Button(
                        onClick = {
                            if (manualEntry.isNotBlank()) {
                                onScanned(manualEntry.trim())
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = manualEntry.isNotBlank(),
                    ) {
                        Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Look Up")
                    }
                }
            } else {
                // CameraX preview placeholder
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    // Viewfinder frame
                    Box(
                        modifier = Modifier
                            .size(250.dp)
                            .border(
                                width = 2.dp,
                                color = Color.White.copy(alpha = 0.7f),
                                shape = RoundedCornerShape(12.dp),
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.QrCodeScanner,
                                contentDescription = null,
                                modifier = Modifier.size(64.dp),
                                tint = Color.White.copy(alpha = 0.7f),
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Text(
                                "CameraX preview\n(integration pending)",
                                color = Color.White.copy(alpha = 0.5f),
                                textAlign = TextAlign.Center,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }

                Text(
                    "Point camera at barcode",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
