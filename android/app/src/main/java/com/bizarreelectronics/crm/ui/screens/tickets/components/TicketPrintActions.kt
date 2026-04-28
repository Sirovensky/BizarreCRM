package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Picture
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.print.PrintAttributes
import android.print.PrintManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.QrCode
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream

/**
 * TicketPrintActions — §4.2 L674
 *
 * Overflow menu providing:
 * - "Print work order" → generates a minimal PDF and sends to [PrintManager].
 * - "Share PDF" → [Intent.ACTION_SEND] with PDF URI via [FileProvider].
 * - "Share via SMS" → pre-fills system SMS with a public tracking link.
 * - "Share via Email" → [ACTION_SENDTO] with mailto: + PDF attachment.
 *
 * PDF is generated from a simple text canvas (no WebView rendering required
 * for basic work-order format). Saved to `cacheDir/workorder-$id.pdf`.
 * [FileProvider] authority must be registered in AndroidManifest.xml as
 * `${applicationId}.fileprovider`.
 *
 * @param ticketId       Ticket ID used for file naming and deep-link.
 * @param orderId        Displayed order ID (e.g. "T-00042").
 * @param customerName   Customer display name for the work order header.
 * @param deviceName     First device name for the work order body.
 * @param serverUrl      Base server URL for the public tracking link stub.
 * @param trackingUrl    Full customer-facing tracking URL (§55.1); when non-null a
 *                       "Print tracking label" QR-label action is shown (§55.3).
 * @param snackbarHost   Snackbar host for error feedback.
 */
@Composable
fun TicketPrintActions(
    ticketId: Long,
    orderId: String,
    customerName: String,
    deviceName: String?,
    serverUrl: String,
    trackingUrl: String? = null,
    snackbarHost: SnackbarHostState,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var menuExpanded by remember { mutableStateOf(false) }

    // Lazily generate the PDF file when needed
    fun buildPdf(): File? {
        return runCatching {
            val pdfFile = File(context.cacheDir, "workorder-$ticketId.pdf")
            val doc = PdfDocument()
            val pageInfo = PdfDocument.PageInfo.Builder(595, 842, 1).create() // A4
            val page = doc.startPage(pageInfo)
            val canvas: Canvas = page.canvas

            val titlePaint = Paint().apply {
                textSize = 22f
                isFakeBoldText = true
            }
            val bodyPaint = Paint().apply { textSize = 14f }
            val mutedPaint = Paint().apply {
                textSize = 12f
                color = 0xFF666666.toInt()
            }

            canvas.drawText("Bizarre Electronics — Work Order", 40f, 60f, titlePaint)
            canvas.drawText("Order ID: $orderId", 40f, 100f, bodyPaint)
            canvas.drawText("Customer: $customerName", 40f, 125f, bodyPaint)
            if (!deviceName.isNullOrBlank()) {
                canvas.drawText("Device: $deviceName", 40f, 150f, bodyPaint)
            }
            canvas.drawText("Please sign when work is complete.", 40f, 200f, mutedPaint)

            doc.finishPage(page)
            FileOutputStream(pdfFile).use { doc.writeTo(it) }
            doc.close()
            pdfFile
        }.onFailure { e ->
            Timber.tag("TicketPrintActions").e(e, "Failed to build PDF for ticket $ticketId")
        }.getOrNull()
    }

    fun getPdfUri(pdfFile: File): Uri? = runCatching {
        FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            pdfFile,
        )
    }.onFailure { e ->
        Timber.tag("TicketPrintActions").w(e, "FileProvider failed for %s", pdfFile.name)
    }.getOrNull()

    IconButton(onClick = { menuExpanded = true }) {
        Icon(Icons.Default.MoreVert, contentDescription = "More options")
    }

    DropdownMenu(
        expanded = menuExpanded,
        onDismissRequest = { menuExpanded = false },
    ) {
        // Print work order
        DropdownMenuItem(
            text = { Text("Print work order") },
            leadingIcon = { Icon(Icons.Default.Print, contentDescription = null, modifier = Modifier.size(18.dp)) },
            onClick = {
                menuExpanded = false
                scope.launch {
                    val pdfFile = buildPdf()
                    if (pdfFile == null) {
                        snackbarHost.showSnackbar("Failed to generate PDF")
                        return@launch
                    }
                    val pdfUri = getPdfUri(pdfFile)
                    if (pdfUri == null) {
                        snackbarHost.showSnackbar("Cannot share PDF: FileProvider not configured")
                        return@launch
                    }
                    runCatching {
                        val printManager = context.getSystemService(PrintManager::class.java)
                        val adapter = object : android.print.PrintDocumentAdapter() {
                            override fun onLayout(
                                oldAttr: PrintAttributes?,
                                newAttr: PrintAttributes,
                                cancellationSignal: android.os.CancellationSignal?,
                                callback: LayoutResultCallback,
                                extras: android.os.Bundle?,
                            ) {
                                if (cancellationSignal?.isCanceled == true) {
                                    callback.onLayoutCancelled()
                                    return
                                }
                                val info = android.print.PrintDocumentInfo.Builder("workorder-$orderId.pdf")
                                    .setContentType(android.print.PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                    .setPageCount(1)
                                    .build()
                                callback.onLayoutFinished(info, oldAttr != newAttr)
                            }

                            override fun onWrite(
                                pages: Array<out android.print.PageRange>?,
                                destination: android.os.ParcelFileDescriptor,
                                cancellationSignal: android.os.CancellationSignal?,
                                callback: WriteResultCallback,
                            ) {
                                if (cancellationSignal?.isCanceled == true) {
                                    callback.onWriteCancelled()
                                    return
                                }
                                runCatching {
                                    pdfFile.inputStream().use { input ->
                                        FileOutputStream(destination.fileDescriptor).use { output ->
                                            input.copyTo(output)
                                        }
                                    }
                                    callback.onWriteFinished(arrayOf(android.print.PageRange.ALL_PAGES))
                                }.onFailure { e ->
                                    Timber.tag("TicketPrintActions").e(e, "onWrite failed")
                                    callback.onWriteFailed(e.message)
                                }
                            }
                        }
                        printManager?.print(
                            "Work Order $orderId",
                            adapter,
                            PrintAttributes.Builder().build(),
                        )
                    }.onFailure { e ->
                        Timber.tag("TicketPrintActions").e(e, "PrintManager failed")
                        snackbarHost.showSnackbar("Printing not available")
                    }
                }
            },
        )

        // Share PDF
        DropdownMenuItem(
            text = { Text("Share PDF") },
            onClick = {
                menuExpanded = false
                scope.launch {
                    val pdfFile = buildPdf()
                    val pdfUri = pdfFile?.let { getPdfUri(it) }
                    if (pdfUri == null) {
                        snackbarHost.showSnackbar("Failed to generate PDF")
                        return@launch
                    }
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, pdfUri)
                        putExtra(Intent.EXTRA_SUBJECT, "Work Order $orderId")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(Intent.createChooser(intent, "Share work order"))
                }
            },
        )

        // SMS with tracking link
        DropdownMenuItem(
            text = { Text("SMS tracking link") },
            onClick = {
                menuExpanded = false
                // Stub tracking link — server generates real link via /tickets/:id/tracking if endpoint exists
                val trackingLink = "$serverUrl/track/$orderId".ifBlank { "Order: $orderId" }
                val smsBody = Uri.encode("Your repair status for $orderId: $trackingLink")
                val smsUri = Uri.parse("sms:?body=$smsBody")
                runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, smsUri)) }
                    .onFailure { scope.launch { snackbarHost.showSnackbar("No SMS app found") } }
            },
        )

        // Email with PDF attachment
        DropdownMenuItem(
            text = { Text("Email work order") },
            onClick = {
                menuExpanded = false
                scope.launch {
                    val pdfFile = buildPdf()
                    val pdfUri = pdfFile?.let { getPdfUri(it) }
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = if (pdfUri != null) "application/pdf" else "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, "Work Order $orderId")
                        putExtra(Intent.EXTRA_TEXT, "Please find attached your work order for ticket $orderId.")
                        if (pdfUri != null) {
                            putExtra(Intent.EXTRA_STREAM, pdfUri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }
                    runCatching { context.startActivity(Intent.createChooser(intent, "Email work order")) }
                        .onFailure { snackbarHost.showSnackbar("No email app found") }
                }
            },
        )

        // §55.3 — Print tracking QR label for customer's repair bag.
        // Visible whenever trackingUrl is available (requires tracking_token on ticket).
        // Falls back to printing an orderId-only QR if trackingUrl is null but item is
        // still shown so staff can always produce a label.
        DropdownMenuItem(
            text = { Text("Print tracking label") },
            leadingIcon = {
                Icon(Icons.Default.QrCode, contentDescription = null, modifier = Modifier.size(18.dp))
            },
            onClick = {
                menuExpanded = false
                scope.launch {
                    // PDF generation touches the bitmap encoder — run off the main thread.
                    val opened = withContext(Dispatchers.IO) {
                        printTicketTrackingLabel(
                            context = context,
                            ticketId = ticketId,
                            orderId = orderId,
                            customerName = customerName.ifBlank { null },
                            trackingUrl = trackingUrl,
                        )
                    }
                    if (!opened) {
                        snackbarHost.showSnackbar("Could not open print dialog")
                    }
                }
            },
        )
    }
}
