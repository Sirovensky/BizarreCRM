package com.bizarreelectronics.crm.ui.screens.purchaseorders

import android.content.Intent
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderItem
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

/**
 * PurchaseOrderSendActions — §6.7 (ActionPlan lines 1538–1546)
 *
 * Top-bar overflow menu for PurchaseOrderDetailScreen providing:
 *   • "Send to supplier" — shares a plain-text PO summary via [Intent.ACTION_SEND]
 *     with [Intent.createChooser]; works with email, WhatsApp, etc.
 *   • "Print / Export PDF" — generates an A4 PDF from [android.graphics.pdf.PdfDocument]
 *     and opens it via [PrintManager] so the user can print or save via the system
 *     print-to-PDF driver (covers §6.7 "PDF export via SAF" item).
 *
 * PDF file is written to `cacheDir/purchase-orders/po-<id>.pdf` and shared via
 * [FileProvider] authority `${applicationId}.fileprovider`.  The path
 * `purchase-orders/` must be declared in `res/xml/file_paths.xml`
 * (cache-path element).
 *
 * No network calls; purely local document generation.
 */
@Composable
fun PurchaseOrderSendActions(
    order: PurchaseOrderRow,
    items: List<PurchaseOrderItem>,
    snackbarHost: SnackbarHostState,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var menuExpanded by remember { mutableStateOf(false) }

    // ── Build plain-text body ────────────────────────────────────────────────

    fun buildPlainText(): String = buildString {
        appendLine("PURCHASE ORDER: ${order.orderId}")
        if (!order.supplierName.isNullOrBlank()) {
            appendLine("Supplier: ${order.supplierName}")
        }
        order.expectedDate?.let { appendLine("Expected: $it") }
        appendLine("Status: ${order.status.replaceFirstChar { it.uppercaseChar() }}")
        appendLine()
        appendLine("ITEMS:")
        items.forEach { item ->
            val name = item.itemName ?: "Item #${item.inventoryItemId}"
            val sku  = if (!item.sku.isNullOrBlank()) " (SKU: ${item.sku})" else ""
            val qty  = item.quantityOrdered
            val cost = String.format(Locale.US, "%.2f", item.costPrice)
            val line = String.format(Locale.US, "%.2f", item.quantityOrdered * item.costPrice)
            appendLine("  • $name$sku — qty $qty @ \$$cost = \$$line")
        }
        appendLine()
        appendLine("TOTAL: $${String.format(Locale.US, "%.2f", order.total)}")
        if (!order.notes.isNullOrBlank()) {
            appendLine()
            appendLine("Notes: ${order.notes}")
        }
    }

    // ── Build PDF file ───────────────────────────────────────────────────────

    fun buildPdf(): File? = runCatching {
        val dir = File(context.cacheDir, "purchase-orders").apply { mkdirs() }
        val pdfFile = File(dir, "po-${order.id}.pdf")

        val doc   = PdfDocument()
        val pageH = 842   // A4 portrait pt
        val pageW = 595
        val margin = 40f
        val page  = doc.startPage(PdfDocument.PageInfo.Builder(pageW, pageH, 1).create())
        val cv: Canvas = page.canvas

        val titlePaint = Paint().apply { textSize = 20f; isFakeBoldText = true }
        val headPaint  = Paint().apply { textSize = 14f; isFakeBoldText = true }
        val bodyPaint  = Paint().apply { textSize = 12f }
        val mutedPaint = Paint().apply { textSize = 11f; color = 0xFF666666.toInt() }

        var y = 55f

        // Header
        cv.drawText("Bizarre Electronics", margin, y, titlePaint); y += 28f
        cv.drawText("Purchase Order: ${order.orderId}", margin, y, headPaint); y += 22f
        if (!order.supplierName.isNullOrBlank()) {
            cv.drawText("Supplier: ${order.supplierName}", margin, y, bodyPaint); y += 18f
        }
        order.expectedDate?.let {
            cv.drawText("Expected date: $it", margin, y, bodyPaint); y += 18f
        }
        cv.drawText(
            "Status: ${order.status.replaceFirstChar { it.uppercaseChar() }}",
            margin, y, mutedPaint,
        ); y += 26f

        // Divider
        val divPaint = Paint().apply { color = 0xFFCCCCCC.toInt(); strokeWidth = 1f }
        cv.drawLine(margin, y, pageW - margin, y, divPaint); y += 16f

        // Column headings
        cv.drawText("ITEM", margin, y, headPaint)
        cv.drawText("QTY", 370f, y, headPaint)
        cv.drawText("UNIT", 420f, y, headPaint)
        cv.drawText("LINE", 480f, y, headPaint)
        y += 18f
        cv.drawLine(margin, y, pageW - margin, y, divPaint); y += 14f

        // Line items
        items.forEach { item ->
            val name     = (item.itemName ?: "Item #${item.inventoryItemId}").take(42)
            val sku      = item.sku?.take(14)
            val qty      = item.quantityOrdered.toString()
            val unit     = String.format(Locale.US, "%.2f", item.costPrice)
            val lineAmt  = String.format(Locale.US, "%.2f", item.quantityOrdered * item.costPrice)

            if (y > pageH - 80) {
                // Avoid overflow on very long POs — truncate gracefully
                cv.drawText("  (... more items)", margin, y, mutedPaint)
                return@forEach
            }

            cv.drawText(name, margin, y, bodyPaint)
            sku?.let { cv.drawText(it, margin, y + 13f, mutedPaint) }
            val rowH = if (sku != null) 28f else 18f
            cv.drawText(qty, 370f, y, bodyPaint)
            cv.drawText(unit, 420f, y, bodyPaint)
            cv.drawText(lineAmt, 480f, y, bodyPaint)
            y += rowH
        }

        // Total
        y += 6f
        cv.drawLine(margin, y, pageW - margin, y, divPaint); y += 16f
        val totalText = "TOTAL: $${String.format(Locale.US, "%.2f", order.total)}"
        cv.drawText(totalText, margin, y, headPaint); y += 22f

        // Notes
        if (!order.notes.isNullOrBlank()) {
            y += 8f
            cv.drawText("Notes:", margin, y, mutedPaint); y += 16f
            // Wrap notes at ~70 chars
            val noteLines = order.notes.chunked(70)
            noteLines.forEach { line ->
                cv.drawText(line, margin, y, mutedPaint); y += 15f
            }
        }

        doc.finishPage(page)
        FileOutputStream(pdfFile).use { doc.writeTo(it) }
        doc.close()
        pdfFile
    }.onFailure { e ->
        Timber.tag("POSendActions").e(e, "PDF build failed for PO ${order.id}")
    }.getOrNull()

    fun getPdfUri(file: File): Uri? = runCatching {
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }.onFailure { e ->
        Timber.tag("POSendActions").w(e, "FileProvider failed for %s", file.name)
    }.getOrNull()

    // ── UI ───────────────────────────────────────────────────────────────────

    IconButton(onClick = { menuExpanded = true }) {
        Icon(Icons.Default.MoreVert, contentDescription = "More PO options")
    }

    DropdownMenu(
        expanded = menuExpanded,
        onDismissRequest = { menuExpanded = false },
    ) {
        // Send to supplier (plain text via any app)
        DropdownMenuItem(
            text = { Text("Send to supplier") },
            leadingIcon = {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
            },
            onClick = {
                menuExpanded = false
                val body = buildPlainText()
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, "Purchase Order ${order.orderId}")
                    putExtra(Intent.EXTRA_TEXT, body)
                }
                runCatching {
                    context.startActivity(Intent.createChooser(intent, "Send PO to supplier"))
                }.onFailure {
                    scope.launch { snackbarHost.showSnackbar("No sharing app available") }
                }
            },
        )

        // Print / Export PDF
        DropdownMenuItem(
            text = { Text("Print / Export PDF") },
            leadingIcon = {
                Icon(
                    Icons.Default.PictureAsPdf,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
            },
            onClick = {
                menuExpanded = false
                scope.launch {
                    val pdfFile = withContext(Dispatchers.IO) { buildPdf() }
                    if (pdfFile == null) {
                        snackbarHost.showSnackbar("Failed to generate PDF")
                        return@launch
                    }
                    val pdfUri = getPdfUri(pdfFile)
                    if (pdfUri == null) {
                        snackbarHost.showSnackbar("Cannot export PDF")
                        return@launch
                    }
                    runCatching {
                        val printManager =
                            context.getSystemService(PrintManager::class.java)
                        val adapter = object : PrintDocumentAdapter() {
                            override fun onLayout(
                                oldAttr: PrintAttributes?,
                                newAttr: PrintAttributes,
                                signal: android.os.CancellationSignal?,
                                callback: LayoutResultCallback,
                                extras: android.os.Bundle?,
                            ) {
                                if (signal?.isCanceled == true) {
                                    callback.onLayoutCancelled(); return
                                }
                                val info = PrintDocumentInfo
                                    .Builder("po-${order.orderId}.pdf")
                                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                    .setPageCount(1)
                                    .build()
                                callback.onLayoutFinished(info, oldAttr != newAttr)
                            }

                            override fun onWrite(
                                pages: Array<out android.print.PageRange>?,
                                dest: android.os.ParcelFileDescriptor,
                                signal: android.os.CancellationSignal?,
                                callback: WriteResultCallback,
                            ) {
                                if (signal?.isCanceled == true) {
                                    callback.onWriteCancelled(); return
                                }
                                runCatching {
                                    pdfFile.inputStream().use { src ->
                                        FileOutputStream(dest.fileDescriptor).use { dst ->
                                            src.copyTo(dst)
                                        }
                                    }
                                    callback.onWriteFinished(
                                        arrayOf(android.print.PageRange.ALL_PAGES),
                                    )
                                }.onFailure { e ->
                                    Timber.tag("POSendActions").e(e, "onWrite failed")
                                    callback.onWriteFailed(e.message)
                                }
                            }
                        }
                        printManager?.print(
                            "PO ${order.orderId}",
                            adapter,
                            PrintAttributes.Builder().build(),
                        )
                    }.onFailure { e ->
                        Timber.tag("POSendActions").e(e, "PrintManager failed")
                        snackbarHost.showSnackbar("Printing not available")
                    }
                }
            },
        )
    }
}
