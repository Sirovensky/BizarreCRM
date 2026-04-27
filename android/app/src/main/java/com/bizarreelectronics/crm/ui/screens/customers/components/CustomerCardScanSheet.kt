package com.bizarreelectronics.crm.ui.screens.customers.components

import android.Manifest
import android.content.pm.PackageManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FlashOff
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.BarcodeAnalyzer
import java.util.concurrent.Executors

/**
 * §5.3 — Customer card barcode/QR scan bottom sheet.
 *
 * Shown from [CustomerCreateScreen] when the user taps "Scan customer card".
 * Uses CameraX + ML Kit [BarcodeAnalyzer] to scan a QR or barcode printed on
 * a tenant-issued customer loyalty/repair card. The raw value is handed to the
 * caller as a string (typically the customer ID or a lookup key); the caller
 * decides whether to navigate to an existing record or pre-fill the form.
 *
 * Permission flow:
 *   - CAMERA granted → live CameraX viewfinder with green reticle overlay.
 *   - CAMERA denied  → "No camera permission" prompt with "Grant" button.
 *
 * Haptic feedback on successful scan (50 ms pulse). Torch toggle available.
 *
 * @param onScanned Called once with the raw barcode value. The sheet does NOT
 *                  auto-dismiss — the caller must dismiss it in [onScanned].
 * @param onDismiss Called when the user taps X or swipes down.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerCardScanSheet(
    onScanned: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context       = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var hasCameraPermission by rememberSaveable {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    var torchEnabled  by rememberSaveable { mutableStateOf(false) }
    var lastScanned   by remember { mutableStateOf<String?>(null) }

    // CameraX
    val cameraController = remember { LifecycleCameraController(context) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    DisposableEffect(Unit) {
        onDispose { analysisExecutor.shutdown() }
    }

    fun hapticHit() {
        runCatching {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                context.getSystemService(VibratorManager::class.java)
                    ?.defaultVibrator
                    ?.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                (context.getSystemService(android.content.Context.VIBRATOR_SERVICE) as? Vibrator)
                    ?.vibrate(50)
            }
        }
    }

    LaunchedEffect(hasCameraPermission) {
        if (!hasCameraPermission) return@LaunchedEffect
        cameraController.cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
        cameraController.setImageAnalysisAnalyzer(
            analysisExecutor,
            BarcodeAnalyzer { rawValue, _ ->
                if (rawValue == lastScanned) return@BarcodeAnalyzer // debounce
                lastScanned = rawValue
                hapticHit()
                onScanned(rawValue)
            },
        )
        cameraController.bindToLifecycle(lifecycleOwner)
    }

    LaunchedEffect(torchEnabled) {
        cameraController.enableTorch(torchEnabled)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        dragHandle = null,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            // ── Sheet header ──────────────────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close")
                }
                Text(
                    "Scan customer card",
                    style = MaterialTheme.typography.titleMedium,
                )
                IconButton(
                    onClick = { torchEnabled = !torchEnabled },
                    enabled = hasCameraPermission,
                ) {
                    Icon(
                        if (torchEnabled) Icons.Default.FlashOn else Icons.Default.FlashOff,
                        contentDescription = if (torchEnabled) "Torch on" else "Torch off",
                        tint = if (torchEnabled) MaterialTheme.colorScheme.primary
                               else MaterialTheme.colorScheme.onSurface,
                    )
                }
            }

            HorizontalDivider()

            // ── Camera / permission body ──────────────────────────────────
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(320.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (hasCameraPermission) {
                    // Live viewfinder
                    AndroidView(
                        factory = { ctx ->
                            PreviewView(ctx).also { it.controller = cameraController }
                        },
                        modifier = Modifier.fillMaxSize(),
                    )

                    // Reticle overlay
                    Canvas(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics {
                                contentDescription = if (lastScanned != null)
                                    "Scanned: $lastScanned" else "Point camera at customer card barcode or QR"
                                liveRegion = LiveRegionMode.Polite
                            },
                    ) {
                        val reticleSize = size.width * 0.55f
                        val left  = (size.width  - reticleSize) / 2f
                        val top   = (size.height - reticleSize) / 2f
                        val arm   = reticleSize * 0.13f
                        val sw    = 3.dp.toPx()
                        val color = if (lastScanned != null) Color(0xFF00E676) else Color.White

                        // Dim outer
                        drawRect(Color.Black.copy(alpha = 0.45f), size = Size(size.width, top))
                        drawRect(Color.Black.copy(alpha = 0.45f), topLeft = Offset(0f, top + reticleSize), size = Size(size.width, size.height - top - reticleSize))
                        drawRect(Color.Black.copy(alpha = 0.45f), topLeft = Offset(0f, top), size = Size(left, reticleSize))
                        drawRect(Color.Black.copy(alpha = 0.45f), topLeft = Offset(left + reticleSize, top), size = Size(size.width - left - reticleSize, reticleSize))

                        // Corner brackets
                        listOf(
                            Triple(Offset(left, top),                         Offset(left + arm, top),             Offset(left, top + arm)),
                            Triple(Offset(left + reticleSize, top),            Offset(left + reticleSize - arm, top),Offset(left + reticleSize, top + arm)),
                            Triple(Offset(left, top + reticleSize),            Offset(left + arm, top + reticleSize),Offset(left, top + reticleSize - arm)),
                            Triple(Offset(left + reticleSize, top + reticleSize), Offset(left + reticleSize - arm, top + reticleSize), Offset(left + reticleSize, top + reticleSize - arm)),
                        ).forEach { (corner, h, v) ->
                            drawLine(color, corner, h, strokeWidth = sw)
                            drawLine(color, corner, v, strokeWidth = sw)
                        }
                    }

                    // Scan result chip
                    if (lastScanned != null) {
                        Surface(
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .padding(bottom = 12.dp),
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.secondaryContainer,
                        ) {
                            Text(
                                lastScanned!!,
                                style = BrandMono,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                        }
                    }
                } else {
                    // Permission denied — prompt
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.padding(24.dp),
                    ) {
                        Text(
                            "Camera permission is required to scan customer cards.",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        FilledTonalButton(
                            onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) },
                        ) {
                            Text("Grant camera access")
                        }
                    }
                }
            }

            // ── Hint footer ───────────────────────────────────────────────
            Text(
                "Point at the QR code or barcode on the customer's loyalty card.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }
    }
}
