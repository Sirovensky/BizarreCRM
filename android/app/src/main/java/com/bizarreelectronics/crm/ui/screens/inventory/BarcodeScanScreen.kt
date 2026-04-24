package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
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

// a11y: When CameraX ships, add:
//   - SemanticsProperties.LiveRegion(LiveRegionMode.Polite) on a scan-result
//     announcement node ("Scanned: VALUE") for HID/camera auto-fills.
//   - LiveRegionMode.Assertive on item-not-found error state.
//   - contentDescription "Looking up item" on a loading indicator node.
//   - contentDescription per row + Role.Button on recent-lookups list items.
//   - FAB contentDescription "Add new item with this barcode" if no match.
//   - mergeDescendants = true on empty-state container.

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BarcodeScanScreen(
    onScanned: (String) -> Unit,
    onBack: () -> Unit,
) {
    // rememberSaveable so an in-progress entry survives rotation.
    var manualEntry by rememberSaveable { mutableStateOf("") }
    // D5-6: IME Search key fires the same Look Up action the button does.
    val focusManager = LocalFocusManager.current
    val submit = {
        val trimmed = manualEntry.trim()
        if (trimmed.isNotBlank()) {
            focusManager.clearFocus()
            onScanned(trimmed)
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Scan Barcode",
                navigationIcon = {
                    // a11y: "Back" matches platform convention; no change needed.
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
                // a11y: Decorative — illustrative icon above the "Enter barcode"
                // heading Text that carries the screen-level announcement.
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            // a11y: Heading text is read as plain text by TalkBack; no explicit
            // heading semantics needed for a single-section screen.
            Text(
                "Enter barcode",
                style = MaterialTheme.typography.titleMedium,
            )

            // a11y: Body copy is informational; no interactive role required.
            Text(
                "Type the barcode, SKU, or IMEI. A bluetooth barcode scanner in HID mode can be used here too — it types into this field just like a keyboard.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // a11y: OutlinedTextField gets an explicit contentDescription so
            // TalkBack announces the full purpose ("Barcode input, numeric or
            // scanner-compatible") rather than just the visible label text.
            // The Modifier.semantics block supplies the description without
            // removing the label or hint that sighted users see.
            OutlinedTextField(
                value = manualEntry,
                onValueChange = { manualEntry = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = "Barcode input, numeric or scanner-compatible"
                        // a11y: When CameraX / HID delivers a scan result into
                        // this field automatically, wrap the update in a node
                        // with liveRegion = LiveRegionMode.Polite so TalkBack
                        // announces the scanned value without interrupting the
                        // user ("Scanned: VALUE").
                    },
                label = { Text("Barcode / SKU / IMEI") },
                // BrandMono for barcode/SKU strings per todo rule
                textStyle = BrandMono,
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Characters,
                    imeAction = ImeAction.Search,
                ),
                // D5-6: hitting the native Search button on the IME triggers
                // the same Look Up flow as the button below.
                keyboardActions = KeyboardActions(onSearch = { submit() }),
                trailingIcon = {
                    if (manualEntry.isNotEmpty()) {
                        // a11y: "Clear barcode input" is more specific than "Clear"
                        // so TalkBack announces the target of the action.
                        IconButton(onClick = { manualEntry = "" }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear barcode input")
                        }
                    }
                },
            )

            // a11y: Explicit contentDescription overrides the default derivation
            // from child Text so TalkBack reads the full action label even when
            // the icon and text are combined inside the Button's slot.
            Button(
                onClick = { submit() },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Look up item by barcode" },
                enabled = manualEntry.isNotBlank(),
            ) {
                // a11y: Decorative — Button's semantics node supplies the name.
                Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Look Up")
            }
        }
    }
}
