package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.theme.BrandMono

// U4 fix: There used to be TWO barcode scanner screens — this one in
// ui/screens/inventory and an orphan ui/screens/scanner/ScannerScreen that was
// never wired into the nav graph. The duplicate has been deleted. Only this
// screen is routed via AppNavGraph -> Screen.BarcodeScan.
//
// Full ML Kit / CameraX barcode scanning requires three dependencies in
// app/build.gradle.kts that this editing scope cannot add:
//   implementation("androidx.camera:camera-camera2:1.3.4")
//   implementation("androidx.camera:camera-lifecycle:1.3.4")
//   implementation("androidx.camera:camera-view:1.3.4")
//   implementation("com.google.mlkit:barcode-scanning:17.3.0")
//
// Until those land, the screen ships a minimum-viable manual entry flow
// (instead of a lying fake camera preview): barcode/SKU/IMEI typed in by hand
// or pasted from a hardware scanner in HID mode. A hardware Bluetooth scanner
// behaves exactly like a keyboard so this path works today.

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BarcodeScanScreen(
    onScanned: (String) -> Unit,
    onBack: () -> Unit,
) {
    // rememberSaveable so an in-progress entry survives rotation.
    var manualEntry by rememberSaveable { mutableStateOf("") }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Scan barcode",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp)
                .imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(
                Icons.Default.Keyboard,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            Text(
                "Enter barcode",
                style = MaterialTheme.typography.titleMedium,
            )

            Text(
                "Type the barcode, SKU, or IMEI. A bluetooth barcode scanner in HID mode can be used here too — it types into this field just like a keyboard.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            OutlinedTextField(
                value = manualEntry,
                onValueChange = { manualEntry = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Barcode / SKU / IMEI") },
                // BrandMono for barcode/SKU strings per todo rule
                textStyle = BrandMono,
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Characters,
                    imeAction = ImeAction.Search,
                ),
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
                    val trimmed = manualEntry.trim()
                    if (trimmed.isNotBlank()) {
                        onScanned(trimmed)
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
    }
}
