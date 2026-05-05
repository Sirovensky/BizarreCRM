package com.bizarreelectronics.crm.ui.screens.inventory.components

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import androidx.core.content.FileProvider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.util.QrCodeGenerator
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.oned.Code128Writer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * Barcode display component with Code-128 and QR tabs (L1079).
 *
 * Two tabs:
 *  - **Code-128**: generated via ZXing [Code128Writer] at 300×100 px. Suitable for
 *    label printers. Encodes the item's SKU.
 *  - **QR code**: delegates to the existing [QrCodeGenerator.generateQrBitmap] at
 *    256×256 px.
 *
 * A share button exports the current tab's bitmap via the Android share sheet.
 * Both generators run on [Dispatchers.Default] to avoid blocking the main thread.
 *
 * @param sku      The SKU string to encode. If blank, a "No SKU set" placeholder
 *                 is shown and barcode generation is skipped.
 * @param modifier Applied to the root [BrandCard].
 */
@Composable
fun InventoryBarcodeDisplay(
    sku: String?,
    modifier: Modifier = Modifier,
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Code-128", "QR code")

    var code128Bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var qrBitmap by remember { mutableStateOf<Bitmap?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(sku) {
        if (sku.isNullOrBlank()) {
            code128Bitmap = null
            qrBitmap = null
            return@LaunchedEffect
        }
        withContext(Dispatchers.Default) {
            try {
                val hints = mapOf(EncodeHintType.MARGIN to 5)
                val matrix = Code128Writer().encode(sku, BarcodeFormat.CODE_128, 300, 100, hints)
                val bmp = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
                for (x in 0 until matrix.width) {
                    for (y in 0 until matrix.height) {
                        bmp.setPixel(x, y, if (matrix[x, y]) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
                    }
                }
                code128Bitmap = bmp
                qrBitmap = QrCodeGenerator.generateQrBitmap(sku, sizePx = 256)
                error = null
            } catch (e: Exception) {
                error = "Failed to generate barcode: ${e.message}"
            }
        }
    }

    val context = LocalContext.current

    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Barcode", style = MaterialTheme.typography.titleSmall)

                if (!sku.isNullOrBlank()) {
                    val currentBitmap = if (selectedTab == 0) code128Bitmap else qrBitmap
                    if (currentBitmap != null) {
                        IconButton(onClick = { shareBitmap(context, currentBitmap, sku) }) {
                            Icon(Icons.Default.Share, contentDescription = "Share barcode")
                        }
                    }
                }
            }

            if (sku.isNullOrBlank()) {
                Text(
                    "No SKU set — assign a SKU to generate barcodes.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
                return@Column
            }

            TabRow(selectedTabIndex = selectedTab) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = { Text(title) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            when {
                error != null -> Text(
                    error!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )

                selectedTab == 0 -> {
                    val bmp = code128Bitmap
                    if (bmp != null) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color.White)
                                .padding(8.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Image(
                                bitmap = bmp.asImageBitmap(),
                                // §26 — a11y_* string resource for custom-drawn barcode image
                                contentDescription = context.getString(R.string.a11y_barcode_code128, sku),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(80.dp),
                            )
                        }
                        Text(
                            sku,
                            style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 4.dp),
                        )
                    } else {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    }
                }

                else -> {
                    val bmp = qrBitmap
                    if (bmp != null) {
                        Box(
                            modifier = Modifier.fillMaxWidth(),
                            contentAlignment = Alignment.Center,
                        ) {
                            Image(
                                bitmap = bmp.asImageBitmap(),
                                // §26 — a11y_* string resource for custom-drawn QR image
                                contentDescription = context.getString(R.string.a11y_barcode_qr, sku),
                                modifier = Modifier.size(180.dp),
                            )
                        }
                    } else {
                        LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }
}

private fun shareBitmap(context: android.content.Context, bitmap: Bitmap, sku: String) {
    try {
        val cacheDir = File(context.cacheDir, "barcodes").also { it.mkdirs() }
        val file = File(cacheDir, "barcode_${sku}.png")
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.provider",
            file,
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Share barcode"))
    } catch (_: Exception) {
        // Sharing is non-critical; silently no-op if provider is not configured.
    }
}
