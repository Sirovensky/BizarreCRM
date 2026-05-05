package com.bizarreelectronics.crm.ui.screens.inventory

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.KeyEvent
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
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
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.BarcodeAnalyzer
import java.util.concurrent.Executors

// §17.2 L1870-L1874 — Barcode scanning screen (extended from the manual-entry baseline).
//
// When CAMERA permission is granted, shows a live CameraX viewfinder with ML Kit
// BarcodeAnalyzer. Green reticle overlay drawn via Canvas. Haptic on match.
// Multi-scan (stocktake) mode: keeps scanning after each result with a beep highlight.
// Torch toggle. Falls back to manual-entry keyboard input when permission denied.
//
// §6.5: HID-scanner support — hidden focused Modifier.onKeyEvent sink. A Bluetooth
// scanner in HID mode types characters just like a keyboard. We detect rapid keystrokes
// (intra-key gap <50 ms) to distinguish scanner input from regular keyboard input.
// Characters accumulate in a buffer; KEYCODE_ENTER (or IME_ACTION_SEARCH) flushes
// the buffer and calls onScanned, identical to the CameraX path.
//
// Formats: Code128, Code39, EAN-13, UPC-A, UPC-E, QR, DataMatrix, ITF (ALL_FORMATS).

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BarcodeScanScreen(
    onScanned: (String) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val focusManager = LocalFocusManager.current

    // Permission state
    var hasCameraPermission by rememberSaveable {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED
        )
    }
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    // Multi-scan (stocktake) mode
    var multiScanMode by rememberSaveable { mutableStateOf(false) }
    var scannedResults by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }

    // Manual entry fallback
    var manualEntry by rememberSaveable { mutableStateOf("") }

    // Last scanned value for reticle highlight
    var lastScanned by remember { mutableStateOf<String?>(null) }
    var lastFormat by remember { mutableStateOf<String?>(null) }

    // Torch state
    var torchEnabled by rememberSaveable { mutableStateOf(false) }

    // §6.5: HID-scanner (Bluetooth barcode scanner in keyboard/HID mode).
    // We keep a character buffer + the timestamp of the last keystroke.
    // When ENTER arrives after a run of keystrokes that each came in <50 ms
    // apart we treat the whole buffer as a scanner result.
    val hidBuffer = remember { StringBuilder() }
    var hidLastKeyTimeMs by remember { mutableLongStateOf(0L) }
    // FocusRequester for the invisible HID sink so we can steal focus back
    // after the snackbar / manual-entry TextField dismisses.
    val hidFocusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        runCatching { hidFocusRequester.requestFocus() }
    }

    // CameraX controller
    val cameraController = remember { LifecycleCameraController(context) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    DisposableEffect(Unit) {
        onDispose { analysisExecutor.shutdown() }
    }

    // Haptic helper
    fun hapticHit() {
        runCatching {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                val vm = context.getSystemService(VibratorManager::class.java)
                vm?.defaultVibrator?.vibrate(
                    VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val v = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                @Suppress("DEPRECATION")
                v?.vibrate(50)
            }
        }
    }

    // Wire ML Kit analyzer to CameraX when permission is granted
    LaunchedEffect(hasCameraPermission) {
        if (!hasCameraPermission) return@LaunchedEffect
        cameraController.cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
        cameraController.setImageAnalysisAnalyzer(
            analysisExecutor,
            BarcodeAnalyzer { rawValue, format ->
                if (rawValue == lastScanned) return@BarcodeAnalyzer  // debounce same value
                lastScanned = rawValue
                lastFormat = BarcodeAnalyzer.formatName(format)
                hapticHit()
                if (multiScanMode) {
                    scannedResults = scannedResults + (rawValue to BarcodeAnalyzer.formatName(format))
                } else {
                    onScanned(rawValue)
                }
            },
        )
        cameraController.bindToLifecycle(lifecycleOwner)
    }

    LaunchedEffect(torchEnabled) {
        cameraController.enableTorch(torchEnabled)
    }

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
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // Multi-scan toggle
                    IconButton(onClick = { multiScanMode = !multiScanMode }) {
                        Icon(
                            if (multiScanMode) Icons.Default.DoneAll else Icons.Default.QrCodeScanner,
                            contentDescription = if (multiScanMode) "Exit multi-scan" else "Multi-scan (stocktake)",
                        )
                    }
                    // Torch
                    if (hasCameraPermission) {
                        IconButton(onClick = { torchEnabled = !torchEnabled }) {
                            Icon(
                                if (torchEnabled) Icons.Default.FlashOn else Icons.Default.FlashOff,
                                contentDescription = if (torchEnabled) "Torch on" else "Torch off",
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        // §6.5: Invisible 0×0 Box that holds keyboard focus for HID scanners.
        // The Box intercepts KeyDown events; character keys append to the HID
        // buffer; KEYCODE_ENTER flushes the buffer and fires onScanned.
        // Intra-key gap threshold 50 ms separates fast scanner input from
        // deliberate keyboard typing — scanners typically burst keys in <10 ms.
        Box(
            modifier = Modifier
                .size(0.dp)
                .focusRequester(hidFocusRequester)
                .focusable()
                .onKeyEvent { keyEvent ->
                    if (keyEvent.nativeKeyEvent.action != KeyEvent.ACTION_DOWN) return@onKeyEvent false
                    val now = System.currentTimeMillis()
                    val gap = now - hidLastKeyTimeMs
                    hidLastKeyTimeMs = now

                    when (val code = keyEvent.nativeKeyEvent.keyCode) {
                        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                            val scanned = hidBuffer.toString().trim()
                            hidBuffer.clear()
                            if (scanned.isNotBlank() && gap < 2000L) {
                                hapticHit()
                                if (multiScanMode) {
                                    scannedResults = scannedResults + (scanned to "HID")
                                } else {
                                    onScanned(scanned)
                                }
                            }
                            true
                        }
                        else -> {
                            // Only accumulate if this keystroke arrived quickly (scanner burst)
                            // OR the buffer is already non-empty (mid-scan).
                            val char = keyEvent.nativeKeyEvent.unicodeChar.toChar()
                            if (char.isLetterOrDigit() || char in "-._/\\") {
                                if (gap < 50L || hidBuffer.isNotEmpty()) {
                                    hidBuffer.append(char)
                                }
                            }
                            false
                        }
                    }
                },
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            if (hasCameraPermission) {
                // ── Live camera viewfinder + reticle overlay ──────────────────
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                ) {
                    AndroidView(
                        factory = { ctx ->
                            PreviewView(ctx).also { it.controller = cameraController }
                        },
                        modifier = Modifier.fillMaxSize(),
                    )

                    // Green reticle overlay
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val reticleSize = size.width * 0.6f
                        val left = (size.width - reticleSize) / 2f
                        val top = (size.height - reticleSize) / 2f
                        val cornerLen = reticleSize * 0.12f
                        val strokeWidth = 3.dp.toPx()

                        val reticleColor = if (lastScanned != null) Color(0xFF00E676) else Color.White
                        val reticleStroke = Stroke(width = strokeWidth)

                        // Draw four corner brackets
                        val corners = listOf(
                            Offset(left, top) to Pair(Offset(left + cornerLen, top), Offset(left, top + cornerLen)),
                            Offset(left + reticleSize, top) to Pair(Offset(left + reticleSize - cornerLen, top), Offset(left + reticleSize, top + cornerLen)),
                            Offset(left, top + reticleSize) to Pair(Offset(left + cornerLen, top + reticleSize), Offset(left, top + reticleSize - cornerLen)),
                            Offset(left + reticleSize, top + reticleSize) to Pair(Offset(left + reticleSize - cornerLen, top + reticleSize), Offset(left + reticleSize, top + reticleSize - cornerLen)),
                        )
                        corners.forEach { (corner, arms) ->
                            drawLine(reticleColor, corner, arms.first, strokeWidth = strokeWidth)
                            drawLine(reticleColor, corner, arms.second, strokeWidth = strokeWidth)
                        }

                        // Dim overlay outside reticle
                        drawRect(Color.Black.copy(alpha = 0.4f), size = Size(size.width, top))
                        drawRect(Color.Black.copy(alpha = 0.4f), topLeft = Offset(0f, top + reticleSize), size = Size(size.width, size.height - top - reticleSize))
                        drawRect(Color.Black.copy(alpha = 0.4f), topLeft = Offset(0f, top), size = Size(left, reticleSize))
                        drawRect(Color.Black.copy(alpha = 0.4f), topLeft = Offset(left + reticleSize, top), size = Size(size.width - left - reticleSize, reticleSize))
                    }

                    // Scan result announcement
                    if (lastScanned != null) {
                        Surface(
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .padding(16.dp)
                                .semantics {
                                    contentDescription = "Scanned: $lastScanned"
                                    liveRegion = LiveRegionMode.Polite
                                },
                            shape = MaterialTheme.shapes.medium,
                            color = MaterialTheme.colorScheme.secondaryContainer,
                        ) {
                            Column(
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Text(
                                    lastScanned!!,
                                    style = BrandMono,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                                )
                                Text(
                                    lastFormat ?: "",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.7f),
                                )
                            }
                        }
                    }
                }

                // Multi-scan results list
                if (multiScanMode && scannedResults.isNotEmpty()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceContainerLow)
                            .padding(12.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                "${scannedResults.size} scanned",
                                style = MaterialTheme.typography.labelMedium,
                            )
                            TextButton(onClick = { scannedResults = emptyList(); lastScanned = null }) {
                                Text("Clear")
                            }
                        }
                        scannedResults.takeLast(5).forEach { (value, fmt) ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(Icons.Default.CheckCircle, contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = MaterialTheme.colorScheme.primary)
                                Text(value, style = BrandMono,
                                    modifier = Modifier.weight(1f))
                                Text(fmt, style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        if (!multiScanMode || scannedResults.isEmpty()) return@Column
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = {
                                scannedResults.lastOrNull()?.first?.let { onScanned(it) }
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text("Use Last Scan")
                        }
                    }
                }
            } else {
                // ── Manual entry fallback ─────────────────────────────────────
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Icon(
                        Icons.Default.Keyboard,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Text("Enter barcode", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Type the barcode, SKU, or IMEI. A Bluetooth barcode scanner in HID mode " +
                            "can be used here too — it types into this field just like a keyboard.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = manualEntry,
                        onValueChange = { manualEntry = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { contentDescription = "Barcode input, numeric or scanner-compatible" },
                        label = { Text("Barcode / SKU / IMEI") },
                        textStyle = BrandMono,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            capitalization = KeyboardCapitalization.Characters,
                            imeAction = ImeAction.Search,
                        ),
                        keyboardActions = KeyboardActions(onSearch = { submit() }),
                        trailingIcon = {
                            if (manualEntry.isNotEmpty()) {
                                IconButton(onClick = { manualEntry = "" }) {
                                    Icon(Icons.Default.Clear, contentDescription = "Clear barcode input")
                                }
                            }
                        },
                    )
                    Button(
                        onClick = { submit() },
                        modifier = Modifier.fillMaxWidth()
                            .semantics { contentDescription = "Look up item by barcode" },
                        enabled = manualEntry.isNotBlank(),
                    ) {
                        Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Look Up")
                    }
                }
            }
        }
    }
}
